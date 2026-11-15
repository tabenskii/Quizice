import Foundation
import Network

protocol QuestionAnswerOutboxing {
    var currentUserID: String? { get }
    var isNetworkUnavailable: Bool { get }
    func enqueue(_ event: QuestionAnswerEvent)
    func enqueue(_ event: QuestionAnswerEvent, for userID: String?)
    func enqueue(_ event: QuestionAnswerEvent, for userID: String?, isCorrect: Bool)
    func synchronize() async
    func synchronizeBeforeFetchingQuestions(for userID: String) async throws
}

extension QuestionAnswerOutboxing {
    func enqueue(_ event: QuestionAnswerEvent, for userID: String?, isCorrect: Bool) { enqueue(event, for: userID) }
    var currentUserID: String? { nil }
    var isNetworkUnavailable: Bool { false }
    func enqueue(_ event: QuestionAnswerEvent, for userID: String?) { enqueue(event) }
    func synchronizeBeforeFetchingQuestions(for userID: String) async throws { await synchronize() }
}

struct NoopQuestionAnswerOutbox: QuestionAnswerOutboxing {
    func enqueue(_ event: QuestionAnswerEvent) {}
    func synchronize() async {}
}

enum QuestionAnswerSyncError: Error {
    case accountChanged
    case unacknowledgedEvents
}

final class PersistentQuestionAnswerOutbox: QuestionAnswerOutboxing, @unchecked Sendable {
    static let shared = PersistentQuestionAnswerOutbox.live()

    struct OwnedEvent: Codable {
        let userID: String?
        let event: QuestionAnswerEvent
    }

    struct RejectedEvent: Codable {
        let ownedEvent: OwnedEvent
        let status: Int
        let code: String?
    }

    private struct State: Codable {
        var pending: [OwnedEvent] = []
        var rejected: [RejectedEvent] = []
    }

    private struct Flight {
        let id: UUID
        let userID: String
        let task: Task<Void, Error>
    }

    private let offlineCache: OfflineQuestionCache
    private let api: BackendContentAPI?
    private let fileURL: URL
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let sessionProvider: () -> AuthSession?
    private let retryDelay: UInt64
    private var flight: Flight?
    private var networkMonitor: NWPathMonitor?
    private var networkUnavailable = false
    var isNetworkUnavailable: Bool { lock.withLock { networkUnavailable } }
    private var authenticationObserver: NSObjectProtocol?
    private let automaticallySynchronizesOnEnqueue: Bool
    private var erasedUserIDs: Set<String> = []

    var currentUserID: String? {
        guard let userID = sessionProvider()?.userID else { return nil }
        return lock.withLock { erasedUserIDs.contains(userID) ? nil : userID }
    }

    init(
        api: BackendContentAPI?,
        offlineCache: OfflineQuestionCache = OfflineQuestionCache(),
        fileURL: URL,
        automaticallySynchronizesOnEnqueue: Bool = true,
        sessionProvider: @escaping () -> AuthSession? = { StoredBackendAccessTokenProvider().currentSession() },
        retryDelay: UInt64 = BackendRetry.defaultBaseDelay
    ) {
        self.offlineCache = offlineCache
        self.api = api
        self.fileURL = fileURL
        self.automaticallySynchronizesOnEnqueue = automaticallySynchronizesOnEnqueue
        self.sessionProvider = sessionProvider
        self.retryDelay = retryDelay
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    deinit {
        networkMonitor?.cancel()
        if let authenticationObserver { NotificationCenter.default.removeObserver(authenticationObserver) }
    }

    static func live(bundle: Bundle = .main) -> PersistentQuestionAnswerOutbox {
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil
            || environment["QUIZICE_XCTEST_SMOKE_HOST"] == "1"
            || NSClassFromString("XCTestCase") != nil {
            return PersistentQuestionAnswerOutbox(
                api: nil,
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("quizice-test-outbox-\(UUID().uuidString).json"),
                automaticallySynchronizesOnEnqueue: false,
                sessionProvider: { nil }
            )
        }
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let fileURL = directory.appendingPathComponent("Quizice", isDirectory: true)
            .appendingPathComponent("question-answer-outbox.json")
        let api = BackendConfiguration.load(bundle: bundle).map {
            HTTPBackendContentAPI(
                configuration: $0,
                metrics: AppMetricaAnalyticsTracker.shared,
                accessTokenProvider: StoredBackendAccessTokenProvider(),
                authenticationRecoverer: NotificationBackendAuthenticationRecoverer()
            )
        }
        let outbox = PersistentQuestionAnswerOutbox(api: api, offlineCache: .shared, fileURL: fileURL)
        if api != nil { outbox.startMonitoring() }
        return outbox
    }

    func enqueue(_ event: QuestionAnswerEvent, for userID: String?, isCorrect: Bool) {
        enqueue(event, for: userID)
        if let userID { offlineCache.record(event, userID: userID, isCorrect: isCorrect) }
    }

    func enqueue(_ event: QuestionAnswerEvent) { enqueue(event, for: currentUserID) }

    func enqueue(_ event: QuestionAnswerEvent, for userID: String?) {
        do {
            try lock.withLock {
                if let userID, erasedUserIDs.contains(userID) { return }
                var state = try loadLocked()
                guard !state.pending.contains(where: { $0.event.eventId == event.eventId }),
                      !state.rejected.contains(where: { $0.ownedEvent.event.eventId == event.eventId }) else { return }
                state.pending.append(OwnedEvent(userID: userID, event: event))
                try saveLocked(state)
            }
            if automaticallySynchronizesOnEnqueue { Task { await synchronize() } }
        } catch {
            AppLog.persistence.error("Question answer outbox persistence failed")
        }
    }

    /// Called only after server-confirmed deletion. The guard survives any late
    /// callbacks in this instance; the authentication owner persists its separate
    /// deletion state and prevents automatic recreation after an app restart.
    func eraseData(for userID: String) throws {
        try lock.withLock {
            try offlineCache.eraseData(for: userID)
            erasedUserIDs.insert(userID)
            if flight?.userID == userID {
                flight?.task.cancel()
                flight = nil
            }
            var state = try loadLocked()
            state.pending.removeAll { $0.userID == userID }
            state.rejected.removeAll { $0.ownedEvent.userID == userID }
            try saveLocked(state)

            // Corrupt backups cannot be scoped reliably. Keeping them could
            // retain the erased account's answers indefinitely.
            let directory = fileURL.deletingLastPathComponent()
            let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for backup in backups where backup.lastPathComponent.hasPrefix(fileURL.lastPathComponent + ".corrupt-") {
                try FileManager.default.removeItem(at: backup)
            }
        }
    }

    func synchronize() async {
        guard let userID = currentUserID else { return }
        do { try await synchronizeBeforeFetchingQuestions(for: userID) }
        catch { AppLog.persistence.notice("Question answer synchronization deferred") }
    }

    /// Shares in-flight uploads with automatic synchronization. A failed upload must
    /// prevent a personalized fetch from racing ahead of unconfirmed progress.
    func synchronizeBeforeFetchingQuestions(for userID: String) async throws {
        while true {
            try Task.checkCancellation()
            guard currentUserID == userID else { throw QuestionAnswerSyncError.accountChanged }
            let active = lock.withLock { () -> Flight in
                if let flight { return flight }
                let created = Flight(id: UUID(), userID: userID, task: Task {
                    try await self.drain(for: userID)
                })
                flight = created
                return created
            }
            let result = await active.task.result
            lock.withLock { if flight?.id == active.id { flight = nil } }
            try Task.checkCancellation()
            guard currentUserID == userID else { throw QuestionAnswerSyncError.accountChanged }
            if active.userID != userID { continue }
            try result.get()
            // Include answers enqueued while a previous upload was completing.
            let hasPending = try lock.withLock { try loadLocked().pending.contains { $0.userID == userID } }
            if !hasPending { return }
        }
    }

    private func drain(for userID: String) async throws {
        guard let api else { throw BackendContentError.unauthenticated }
        while true {
            try Task.checkCancellation()
            guard currentUserID == userID else { throw QuestionAnswerSyncError.accountChanged }
            let batch = try lock.withLock {
                Array(try loadLocked().pending.filter { $0.userID == userID }.prefix(100).map(\.event))
            }
            guard !batch.isEmpty else { return }
            try await upload(batch, for: userID, api: api)
        }
    }

    private func upload(_ batch: [QuestionAnswerEvent], for userID: String, api: BackendContentAPI) async throws {
        do {
            let response = try await BackendRetry.withExponentialBackoff(baseDelay: retryDelay, isRetryable: Self.isRetryable) {
                try Task.checkCancellation()
                guard self.currentUserID == userID,
                      let session = self.sessionProvider(), session.userID == userID else {
                    throw QuestionAnswerSyncError.accountChanged
                }
                return try await api.submitQuestionAnswers(batch, session: session)
            }
            try Task.checkCancellation()
            let processed = Set(response.processedEventIds)
            guard !processed.isEmpty, processed.isSubset(of: Set(batch.map(\.eventId))) else {
                throw QuestionAnswerSyncError.unacknowledgedEvents
            }
            try lock.withLock {
                guard !erasedUserIDs.contains(userID) else { throw QuestionAnswerSyncError.accountChanged }
                var state = try loadLocked()
                state.pending.removeAll { $0.userID == userID && processed.contains($0.event.eventId) }
                try saveLocked(state)
            }
        } catch BackendContentError.httpStatus(let status, let envelope) where status == 409 || status == 422 {
            // The server rejects the whole batch. Split it to isolate invalid events;
            // valid neighbours are retried with their original IDs and payloads.
            guard currentUserID == userID else { throw QuestionAnswerSyncError.accountChanged }
            if batch.count > 1 {
                let middle = batch.count / 2
                try await upload(Array(batch.prefix(middle)), for: userID, api: api)
                try await upload(Array(batch.dropFirst(middle)), for: userID, api: api)
            } else if let event = batch.first {
                try lock.withLock {
                    guard !erasedUserIDs.contains(userID) else { throw QuestionAnswerSyncError.accountChanged }
                    var state = try loadLocked()
                    if let index = state.pending.firstIndex(where: { $0.userID == userID && $0.event.eventId == event.eventId }) {
                        let owned = state.pending.remove(at: index)
                        state.rejected.append(RejectedEvent(ownedEvent: owned, status: status, code: envelope?.code))
                        try saveLocked(state)
                    }
                }
                AppLog.persistence.error("Question answer quarantined: status=\(status) code=\(envelope?.code ?? "unknown", privacy: .public)")
            }
        }
    }

    private static func isRetryable(_ error: Error) -> Bool {
        switch error {
        case BackendContentError.transport(let code): return code != .cancelled
        case BackendContentError.timedOut: return true
        case BackendContentError.httpStatus(let status, _): return status == 429 || (500...599).contains(status)
        default: return false
        }
    }

    private func loadLocked() throws -> State {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return State() }
        let data = try Data(contentsOf: fileURL)
        if let state = try? decoder.decode(State.self, from: data) { return state }
        // The old format has no owner. Preserve it without assigning another user's
        // history to whoever happens to sign in after upgrading.
        if let legacy = try? decoder.decode([QuestionAnswerEvent].self, from: data) {
            return State(pending: legacy.map { OwnedEvent(userID: nil, event: $0) })
        }
        // Quarantine damaged storage so a single corrupt write cannot disable
        // all future answers. Preserve original bytes for recovery.
        let quarantine = fileURL.appendingPathExtension("corrupt-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: fileURL, to: quarantine)
        AppLog.persistence.error("Corrupt question answer outbox quarantined")
        return State()
    }

    func pendingEvents() -> [QuestionAnswerEvent] {
        lock.withLock { (try? loadLocked().pending.map(\.event)) ?? [] }
    }

    func rejectedEvents() -> [RejectedEvent] {
        lock.withLock { (try? loadLocked().rejected) ?? [] }
    }

    private func saveLocked(_ state: State) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var bounded = state
        // Guest events cannot be assigned to an account. Keep only a bounded
        // diagnostic history; never truncate an authenticated pending queue.
        let retainedGuestIDs = Set(state.pending.filter { $0.userID == nil }.suffix(1_000).map { $0.event.eventId })
        bounded.pending.removeAll { $0.userID == nil && !retainedGuestIDs.contains($0.event.eventId) }
        bounded.rejected = Array(state.rejected.suffix(1_000))
        try encoder.encode(bounded).write(to: fileURL, options: .atomic)
    }

    private func startMonitoring() {
        authenticationObserver = NotificationCenter.default.addObserver(
            forName: .backendAuthenticationEstablished, object: nil, queue: nil
        ) { [weak self] _ in Task { await self?.synchronize() } }
        let monitor = NWPathMonitor()
        networkMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            self?.lock.withLock { self?.networkUnavailable = path.status != .satisfied }
            guard path.status == .satisfied else { return }
            Task { await self?.synchronize() }
        }
        monitor.start(queue: DispatchQueue(label: "ru.avtabenskiy.Quizice.answer-outbox-network"))
    }
}
