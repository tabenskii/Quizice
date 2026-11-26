import XCTest
@testable import Quizice

@MainActor
final class OfflineQuestionTests: XCTestCase {
    private let generation = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    private var locale: String { AppLocalizationStore.shared.resolvedLanguageCode }

    private func pack(userID: String = "A", locale: String? = nil, generation: UUID? = nil,
                      musicCount: Int = 8) throws -> OfflineQuestionPack {
        var questions: [[String: Any]] = []
        for index in 0..<(musicCount + 4) {
            let theme = index < musicCount ? "music" : "space"
            var item: [String: Any] = ["themeId": theme, "difficulty": index == 0 ? "hard" : "medium"]
            item["country"] = index == 1 ? "US" as Any : NSNull()
            item["wasAnswered"] = index == 2
            item["wasCorrect"] = index == 2
            item["questionId"] = theme + ":" + String(index)
            item["questionVersion"] = 2
            item["progressGeneration"] = (generation ?? self.generation).uuidString
            item["question"] = "Question \(index)"
            item["answers"] = ["A", "B", "C", "D"]
            item["correctAnswer"] = "B"
            item["explanation"] = "Explanation"
            item["themeName"] = index < musicCount ? "Music" : "Space"
            questions.append(item)
        }
        let data = try JSONSerialization.data(withJSONObject: ["locale": locale ?? self.locale, "userId": userID, "questions": questions])
        return try JSONDecoder().decode(OfflineQuestionPack.self, from: data)
    }

    func testDiskRoundTripIsScopedAndPreservesIdentityAndFilters() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = OfflineQuestionCache(directory: directory)
        try await first.install(pack())
        let cache = OfflineQuestionCache(directory: directory)
        let questions = try await cache.questions(locale: locale, userID: "A", themeIDs: ["music"], count: 15,
            difficulty: .medium, strategy: .hideAnswered, country: nil)
        XCTAssertEqual(Set(questions.compactMap(\.questionID)), Set((3..<8).map { "music:\($0)" }))
        XCTAssertTrue(questions.allSatisfy { $0.questionVersion == 2 && $0.progressGeneration == generation && $0.locale == locale })
        for scope in [("B", locale), ("A", "other")] {
            do {
                _ = try await cache.questions(locale: scope.1, userID: scope.0, themeIDs: ["music"], count: 5,
                    difficulty: .medium, strategy: .showAll, country: nil)
                XCTFail("A different account/language must not reuse this pack")
            } catch { XCTAssertEqual(error as? QuizPreparationError, .offlineQuestionsUnavailable) }
        }
    }

    func testPendingAnswersSurviveRestartAndRespectEachRepeatStrategy() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = OfflineQuestionCache(directory: directory)
        try await cache.install(pack())
        let provider = ProgressSessionProvider()
        let outbox = PersistentQuestionAnswerOutbox(api: nil, offlineCache: cache,
            fileURL: directory.appendingPathComponent("outbox.json"), automaticallySynchronizesOnEnqueue: false,
            sessionProvider: { provider.session })
        for (index, correct) in [(3, true), (4, false)] {
            outbox.enqueue(QuestionAnswerEvent(eventId: UUID(), questionId: "music:\(index)", questionVersion: 2,
                locale: locale, answer: correct ? "B" : "A", answeredAt: Date(), progressGeneration: generation),
                for: "A", isCorrect: correct)
        }
        let restored = OfflineQuestionCache(directory: directory)
        for (strategy, expected) in [(QuestionRepeatStrategy.hideAnswered, [5,6,7]), (.retryIncorrect, [4,5,6,7]), (.showAll, [2,3,4,5,6,7])] {
            let questions = try await restored.questions(locale: locale, userID: "A", themeIDs: ["music"], count: 15,
                difficulty: .medium, strategy: strategy, country: nil)
            XCTAssertEqual(Set(questions.compactMap(\.questionID)), Set(expected.map { "music:\($0)" }))
        }
        XCTAssertEqual(outbox.pendingEvents().count, 2)
        try await restored.install(pack(generation: UUID()))
        let afterReset = try await restored.questions(locale: locale, userID: "A", themeIDs: ["music"], count: 15,
            difficulty: .medium, strategy: .hideAnswered, country: nil)
        XCTAssertTrue(afterReset.contains { $0.questionID == "music:3" })
    }

    func testDeletionBlocksLateDownloadsAndRemovesPersistedProgress() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = OfflineQuestionCache(directory: directory)
        try await cache.install(pack())
        try cache.eraseData(for: "A")
        do { try await cache.install(pack()); XCTFail("Deleted account resurrected") } catch {}
        let restored = OfflineQuestionCache(directory: directory)
        let needsDownload = await restored.needsDownload(locale: locale, userID: "A")
        XCTAssertTrue(needsDownload)
    }

    func testRefreshKeepsPreviousPackUntilACompleteValidatedReplacement() async throws {
        let cache = OfflineQuestionCache()
        let now = Date()
        try await cache.install(pack(), now: now)
        let fresh = await cache.needsDownload(locale: locale, userID: "A", now: now.addingTimeInterval(60))
        let stale = await cache.needsDownload(locale: locale, userID: "A", now: now.addingTimeInterval(21601))
        XCTAssertFalse(fresh)
        XCTAssertTrue(stale)
        let questions = try await cache.questions(locale: locale, userID: "A", themeIDs: ["music", "space"], count: 5,
            difficulty: .medium, strategy: .showAll, country: nil, balanced: true)
        XCTAssertEqual(questions.count, 5)
        XCTAssertEqual(Set(questions.compactMap(\.sourceThemeName)), ["Music", "Space"])
    }

    func testRepositoryUsesPackWhenPreflightUploadCannotReachBackend() async throws {
        let cache = OfflineQuestionCache()
        try await cache.install(pack())
        let provider = ProgressSessionProvider()
        let outbox = ProgressOutboxSpy()
        let repository = ThemeCatalogRepository(backendContentAPI: RecordingBackendContentAPI(), offlineCache: cache,
            accessTokenProvider: provider, answerOutbox: outbox, repeatStrategyProvider: { .hideAnswered }, countryProvider: { nil })
        _ = await repository.refreshBackendCatalog(locale: locale)
        outbox.isNetworkUnavailable = true
        outbox.beforeFetch = { XCTFail("Known offline state must not start an upload") }
        let immediate = try await repository.prepareQuiz(themeID: "music", questionCount: 5, difficulty: .medium, locale: locale)
        XCTAssertEqual(immediate.questions.count, 5)
        outbox.isNetworkUnavailable = false
        outbox.beforeFetch = { throw BackendContentError.transport(.notConnectedToInternet) }
        let theme = try await repository.prepareQuiz(themeID: "music", questionCount: 5, difficulty: .medium, locale: locale)
        XCTAssertEqual(theme.questionOrigin, .backend)
        XCTAssertEqual(theme.questions.count, 5)
        outbox.beforeFetch = { throw BackendContentError.httpStatus(401, nil) }
        do {
            _ = try await repository.prepareQuiz(themeID: "music", questionCount: 5, difficulty: .medium, locale: locale)
            XCTFail("An unauthorized response must not be hidden by the cache")
        } catch { XCTAssertEqual(error as? BackendContentError, .httpStatus(401, nil)) }
    }

    func testResetInvalidatesAnAlreadyDownloadingPack() async throws {
        let cache = OfflineQuestionCache()
        try await cache.install(pack())
        let generation = cache.generation(for: "A")
        cache.invalidate(userID: "A")
        do { try await cache.install(pack(), expectedGeneration: generation); XCTFail("Stale pack restored") }
        catch is CancellationError {}
        let needsDownload = await cache.needsDownload(locale: locale, userID: "A")
        XCTAssertTrue(needsDownload)
    }

    func testBackgroundDownloadDoesNotDelayCatalogAndCoalescesRequests() async throws {
        let cache = OfflineQuestionCache()
        let provider = ProgressSessionProvider()
        let api = RecordingBackendContentAPI()
        api.offlinePack = try pack()
        let gate = ProgressUploadGate()
        let started = expectation(description: "Background download started")
        api.onOffline = { started.fulfill(); await gate.wait() }
        let repository = ThemeCatalogRepository(backendContentAPI: api, offlineCache: cache,
            automaticallyDownloadsOfflineQuestions: true, accessTokenProvider: provider,
            answerOutbox: ProgressOutboxSpy(), countryProvider: { nil })
        let refreshed = await repository.refreshBackendCatalog(locale: locale)
        XCTAssertTrue(refreshed)
        await fulfillment(of: [started], timeout: 2)
        _ = await repository.refreshBackendCatalog(locale: locale)
        XCTAssertEqual(api.requestedOfflineLocales, [locale])
        await gate.open()
        for _ in 0..<100 {
            if !(await cache.needsDownload(locale: locale, userID: "A")) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let stillMissing = await cache.needsDownload(locale: locale, userID: "A")
        XCTAssertFalse(stillMissing)
    }

    func testQueuedOfflineEventsUploadWithTheirOriginalIDsAfterRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = ProgressSessionProvider()
        let cache = OfflineQuestionCache(directory: directory)
        try await cache.install(pack())
        let api = QuestionAnswerBackendContentAPI(submitResults: [])
        api.onSubmit = { _ in throw BackendContentError.transport(.notConnectedToInternet) }
        let url = directory.appendingPathComponent("outbox.json")
        let outbox = PersistentQuestionAnswerOutbox(api: api, offlineCache: cache, fileURL: url,
            automaticallySynchronizesOnEnqueue: false, sessionProvider: { provider.session }, retryDelay: 0)
        let event = QuestionAnswerEvent(eventId: UUID(), questionId: "music:3", questionVersion: 2,
            locale: locale, answer: "B", answeredAt: Date(timeIntervalSince1970: 100), progressGeneration: generation)
        outbox.enqueue(event, for: "A", isCorrect: true)
        await outbox.synchronize()
        XCTAssertEqual(outbox.pendingEvents(), [event])
        let restored = PersistentQuestionAnswerOutbox(api: api, offlineCache: OfflineQuestionCache(directory: directory),
            fileURL: url, automaticallySynchronizesOnEnqueue: false, sessionProvider: { provider.session }, retryDelay: 0)
        api.onSubmit = { batch in QuestionAnswerBatchResponse(processedEventIds: batch.map(\.eventId)) }
        await restored.synchronize()
        XCTAssertTrue(restored.pendingEvents().isEmpty)
        XCTAssertTrue(api.submittedBatches.allSatisfy { $0 == [event] })
        let requests = api.submittedBatches.count
        await restored.synchronize()
        XCTAssertEqual(api.submittedBatches.count, requests)
    }

    func testHTTPPackUsesAuthenticatedLocaleAndRejectsAnotherOwner() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BackendTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); BackendTestURLProtocol.requestHandler = nil }
        let provider = ProgressSessionProvider()
        let api = HTTPBackendContentAPI(configuration: BackendClientTests.configuration,
            session: session, accessTokenProvider: provider)
        let currentLocale = locale
        let validData = try JSONEncoder().encode(pack())
        BackendTestURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/themes/offline")
            XCTAssertEqual(request.url?.query, "locale=" + currentLocale)
            XCTAssertEqual(request.value(forHTTPHeaderField: BackendConfiguration.authorizationHeader), "Bearer token-A")
            return BackendClientTests.response(for: request, data: validData)
        }
        let response = try await api.fetchOfflineQuestions(locale: locale, userID: "A")
        XCTAssertEqual(response.questions.count, 12)
        let wrongData = try JSONEncoder().encode(pack(userID: "B"))
        BackendTestURLProtocol.requestHandler = { BackendClientTests.response(for: $0, data: wrongData) }
        do { _ = try await api.fetchOfflineQuestions(locale: locale, userID: "A"); XCTFail("Wrong owner accepted") }
        catch { XCTAssertEqual(error as? BackendContentError, .contractViolation) }
    }

    func testInvalidReplacementPreservesPreviousPack() async throws {
        let cache = OfflineQuestionCache()
        let original = try pack()
        try await cache.install(original)
        let duplicate = OfflineQuestionPack(locale: locale, userId: "A", questions: original.questions + original.questions)
        do { try await cache.install(duplicate); XCTFail("Duplicate identities accepted") }
        catch { XCTAssertEqual(error as? BackendContentError, .contractViolation) }
        let questions = try await cache.questions(locale: locale, userID: "A", themeIDs: ["music"], count: 5,
            difficulty: .medium, strategy: .hideAnswered, country: nil)
        XCTAssertEqual(questions.count, 5)
    }

    func testOfflineFallbackNeverMasksCancellationOrContractErrors() {
        for error in [BackendContentError.transport(.cancelled), .decoding, .contractViolation, .httpStatus(403, nil), .httpStatus(404, nil)] {
            XCTAssertFalse(OfflineQuestionDownloader.permitsFallback(error))
        }
        XCTAssertTrue(OfflineQuestionDownloader.permitsFallback(BackendContentError.httpStatus(503, nil)))
    }

    func testRandomQuizUsesCachedQuestionsForAllSelectedLengths() async throws {
        let cache = OfflineQuestionCache()
        try await cache.install(pack(musicCount: 20))
        let backend = RecordingBackendContentAPI()
        let outbox = ProgressOutboxSpy()
        let repository = ThemeCatalogRepository(
            backendContentAPI: backend, offlineCache: cache, accessTokenProvider: ProgressSessionProvider(),
            answerOutbox: outbox, repeatStrategyProvider: { .showAll }, countryProvider: { nil }
        )
        let didRefresh = await repository.refreshBackendCatalog(locale: locale)
        XCTAssertTrue(didRefresh)
        outbox.isNetworkUnavailable = true
        let selection = QuizTheme(
            id: RandomQuizSelection.themeID, theme: "Random", themeDescription: "", questions: []
        )

        for mode in CrossThemeQuestionSelectionMode.allCases {
            for count in QuizQuestionCountPolicy.supportedCounts {
                let round = try await repository.prepareRandomQuiz(
                    selectionMode: mode, localFallback: selection, questionCount: count,
                    difficulty: .medium, locale: locale
                )
                XCTAssertEqual(round.questions.count, count)
                XCTAssertTrue(round.questions.allSatisfy { $0.questionID?.hasPrefix("music:") == true })
            }
        }
        XCTAssertTrue(backend.randomSelectionModes.isEmpty)
    }
}
