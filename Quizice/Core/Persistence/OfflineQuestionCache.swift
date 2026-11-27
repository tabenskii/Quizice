import CryptoKit
import Foundation

struct OfflineQuestionPack: Codable {
    let locale: String
    let userId: String
    let questions: [OfflineCatalogQuestion]

    func isValid(locale: String, userID: String) -> Bool {
        guard self.locale == locale, userId == userID, questions.count <= 20_000 else { return false }
        var ids = Set<String>()
        var generations: [String: UUID] = [:]
        return questions.allSatisfy { item in
            let question = item.question
            guard let id = question.questionId, let version = question.questionVersion else { return false }
            guard let generation = question.progressGeneration,
                  generations[item.themeId] == nil || generations[item.themeId] == generation else { return false }
            generations[item.themeId] = generation
            return question.question.count <= 500 && question.answers.count == 4
                && Set(question.answers).count == 4
                && question.answers.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 300 }
                && (question.explanation?.count ?? 0) <= 2_000
                && id.hasPrefix(item.themeId + ":") && ids.insert(id).inserted && version > 0
                && question.progressGeneration != nil && !item.themeId.isEmpty
                && ["easy", "medium", "hard"].contains(item.difficulty)
                && (item.country == nil || QuestionCountryStore.supportedCodes.contains(item.country!))
                && item.subtopicIds.allSatisfy(QuizSubtopic.isValidID)
                && Set(item.subtopicIds).count == item.subtopicIds.count
                && (!item.wasCorrect || item.wasAnswered)
                && QuizQuestionCountPolicy.isUsable(QuestionModel(quizQuestion: question.makeModel(locale: locale)))
        }
    }
}

struct OfflineCatalogQuestion: Codable {
    let themeId: String
    let country: String?
    let subtopicIds: [String]
    let difficulty: String
    let wasAnswered: Bool
    let wasCorrect: Bool
    let question: BackendQuestionDTO

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        themeId = try container.decode(String.self, forKey: .themeId)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        subtopicIds = try container.decodeIfPresent([String].self, forKey: .subtopicIds) ?? []
        difficulty = try container.decode(String.self, forKey: .difficulty)
        wasAnswered = try container.decode(Bool.self, forKey: .wasAnswered)
        wasCorrect = try container.decode(Bool.self, forKey: .wasCorrect)
        question = try BackendQuestionDTO(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try question.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(themeId, forKey: .themeId)
        try container.encodeIfPresent(country, forKey: .country)
        if !subtopicIds.isEmpty {
            try container.encode(subtopicIds, forKey: .subtopicIds)
        }
        try container.encode(difficulty, forKey: .difficulty)
        try container.encode(wasAnswered, forKey: .wasAnswered)
        try container.encode(wasCorrect, forKey: .wasCorrect)
    }

    private enum CodingKeys: String, CodingKey { case themeId, country, subtopicIds, difficulty, wasAnswered, wasCorrect }
}

final class OfflineQuestionCache: @unchecked Sendable {
    static let shared = OfflineQuestionCache(directory: FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    ).first!.appendingPathComponent("Quizice/offline-questions", isDirectory: true))

    private struct Snapshot: Codable {
        let downloadedAt: Date
        let pack: OfflineQuestionPack
    }
    private struct Progress: Codable {
        let userID: String
        var correct: Bool
    }
    private let directory: URL?
    private let lock = NSLock()
    private var snapshots: [String: Snapshot] = [:]
    private var progress: [String: Progress]?
    private var erasedUsers = Set<String>()
    private var generations: [String: UUID] = [:]
    private var invalidatedUsers = Set<String>()

    init(directory: URL? = nil) { self.directory = directory }

    func needsDownload(locale: String, userID: String, now: Date = Date()) async -> Bool {
        await Task.detached(priority: .utility) {
            self.lock.withLock {
                guard !self.erasedUsers.contains(userID) else { return false }
                guard let snapshot = self.snapshot(locale: locale, userID: userID) else { return true }
                return now.timeIntervalSince(snapshot.downloadedAt) >= 6 * 60 * 60
            }
        }.value
    }

    func generation(for userID: String) -> UUID {
        lock.withLock {
            if let value = generations[userID] { return value }
            let value = UUID()
            generations[userID] = value
            return value
        }
    }

    func install(_ pack: OfflineQuestionPack, now: Date = Date(), expectedGeneration: UUID? = nil) async throws {
        try await Task.detached(priority: .utility) {
            try self.lock.withLock {
                guard !self.erasedUsers.contains(pack.userId) else { throw QuestionAnswerSyncError.accountChanged }
                if let expectedGeneration, self.generations[pack.userId] != expectedGeneration {
                    throw CancellationError()
                }
                guard pack.isValid(locale: pack.locale, userID: pack.userId) else {
                    throw BackendContentError.contractViolation
                }
                let key = self.scope(locale: pack.locale, userID: pack.userId)
                let snapshot = Snapshot(downloadedAt: now, pack: pack)
                try self.save(snapshot, name: key + ".json")
                self.snapshots[key] = snapshot
                self.invalidatedUsers.remove(pack.userId)
            }
        }.value
    }

    func record(_ event: QuestionAnswerEvent, userID: String, isCorrect: Bool) {
        lock.withLock {
            guard !erasedUsers.contains(userID), let generation = event.progressGeneration else { return }
            loadProgress()
            let key = progressKey(userID: userID, id: event.questionId, version: event.questionVersion, generation: generation)
            let wasCorrect = progress?[key]?.correct == true
            progress?[key] = Progress(userID: userID, correct: isCorrect || wasCorrect)
            do { try save(progress, name: "progress.json") }
            catch { AppLog.persistence.error("Offline progress persistence failed") }
        }
    }

    func eraseData(for userID: String) throws {
        try lock.withLock {
            erasedUsers.insert(userID)
            snapshots = snapshots.filter { $0.value.pack.userId != userID }
            loadProgress()
            progress = progress?.filter { $0.value.userID != userID }
            try save(progress, name: "progress.json")
            guard let directory, FileManager.default.fileExists(atPath: directory.path) else { return }
            for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                where file.lastPathComponent.hasPrefix(hash(userID) + "-") {
                try FileManager.default.removeItem(at: file)
            }
        }
    }

    func invalidate(userID: String) {
        lock.withLock {
            generations[userID] = UUID()
            invalidatedUsers.insert(userID)
            snapshots = snapshots.filter { $0.value.pack.userId != userID }
            guard let directory else { return }
            for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
                where file.lastPathComponent.hasPrefix(hash(userID) + "-") {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    func questions(locale: String, userID: String, themeIDs: Set<String>, count: Int,
                   difficulty: AIQuizDifficulty, strategy: QuestionRepeatStrategy, country: String?,
                   subtopicID: String? = nil, balanced: Bool = false) async throws -> [QuizQuestion] {
        let selected: [BackendQuestionDTO] = try await Task.detached(priority: .utility) {
            try self.lock.withLock {
                guard !self.erasedUsers.contains(userID),
                      let snapshot = self.snapshot(locale: locale, userID: userID) else {
                    throw QuizPreparationError.offlineQuestionsUnavailable
                }
                self.loadProgress()
                let eligible = snapshot.pack.questions.filter { item in
                    guard themeIDs.contains(item.themeId), item.difficulty == difficulty.rawValue,
                          item.country == nil || item.country == country,
                          subtopicID.map(item.subtopicIds.contains) ?? true,
                          let id = item.question.questionId, let version = item.question.questionVersion,
                          let generation = item.question.progressGeneration else { return false }
                    let local = self.progress?[self.progressKey(userID: userID, id: id, version: version, generation: generation)]
                    switch strategy {
                    case .showAll: return true
                    case .hideAnswered: return !item.wasAnswered && local == nil
                    case .retryIncorrect: return !item.wasCorrect && local?.correct != true
                    }
                }.shuffled()
                guard !eligible.isEmpty else { throw QuizPreparationError.offlineQuestionsUnavailable }
                if !balanced { return Array(eligible.prefix(count).map(\.question)) }
                var groups = Dictionary(grouping: eligible, by: \.themeId)
                let themes = groups.keys.sorted().shuffled()
                var result: [BackendQuestionDTO] = []
                while result.count < min(count, eligible.count) {
                    for theme in themes where result.count < count {
                        if let item = groups[theme]?.popLast() { result.append(item.question) }
                    }
                }
                return result
            }
        }.value
        try Task.checkCancellation()
        return selected.map { item in
            let model = item.makeModel(locale: locale)
            model.answers.shuffle()
            return model
        }
    }

    private func snapshot(locale: String, userID: String) -> Snapshot? {
        guard !invalidatedUsers.contains(userID) else { return nil }
        let key = scope(locale: locale, userID: userID)
        if let cached = snapshots[key] { return cached }
        guard let directory, let data = try? Data(contentsOf: directory.appendingPathComponent(key + ".json")),
              data.count <= 10 * 1024 * 1024,
              let value = try? JSONDecoder().decode(Snapshot.self, from: data),
              value.pack.isValid(locale: locale, userID: userID) else { return nil }
        snapshots[key] = value
        return value
    }

    private func loadProgress() {
        guard progress == nil else { return }
        if let directory, let data = try? Data(contentsOf: directory.appendingPathComponent("progress.json")),
           let value = try? JSONDecoder().decode([String: Progress].self, from: data) { progress = value }
        else { progress = [:] }
    }

    private func save<T: Encodable>(_ value: T, name: String) throws {
        guard let directory else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: directory.appendingPathComponent(name), options: .atomic)
        var directoryURL = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directoryURL.setResourceValues(values)
    }

    private func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func scope(locale: String, userID: String) -> String { hash(userID) + "-" + hash(locale) }
    private func progressKey(userID: String, id: String, version: Int, generation: UUID) -> String {
        hash(userID + "|" + id + "|" + String(version) + "|" + generation.uuidString)
    }
}
