import Foundation
import UIKit

@MainActor
final class GameCenterAuthenticationService: AccountManaging, AppAccountAccessProviding {
    private(set) var state: AuthSessionState = .initializing {
        didSet {
            initialAuthentication.resolveIfNeeded(state)
            accountAccessStateDidChange?(accountAccessState)
        }
    }
    var accountAccessStateDidChange: ((AppAccountAccessState) -> Void)? {
        didSet { accountAccessStateDidChange?(accountAccessState) }
    }

    private let gameCenter: GameCenterAuthenticating
    private let api: AuthAPI
    private let sessionStore: SessionStoring
    private let statisticsStore: StatisticsStore
    private let bundleIdentifier: String
    private let now: () -> Date
    private let notificationCenter: NotificationCenter
    private let aiQuizAccessStore: AIQuizAccessStore
    private let deletionStateStore: AccountDeletionStateStore
    private let eraseLocalAccountData: (String) throws -> Void
    private(set) var accountOperationInProgress = false {
        didSet { accountAccessStateDidChange?(accountAccessState) }
    }
    private var deferredPlayerState: GameCenterPlayerState?

    private var authenticationTask: Task<Void, Never>?
    private var authenticationAttemptID: UUID?
    private var synchronizationTask: Task<Void, Never>?
    private var synchronizationAttemptID: UUID?
    private var pendingSyncObserver: NSObjectProtocol?
    private var authenticationInvalidationObserver: NSObjectProtocol?
    private var currentTeamPlayerID: String?
    private var started = false
    private let initialAuthentication = InitialAuthenticationReadiness()
#if DEBUG
    private var devAuthenticationProvider: AuthenticationProvider?
#endif

    init(
        gameCenter: GameCenterAuthenticating,
        api: AuthAPI,
        sessionStore: SessionStoring,
        statisticsStore: StatisticsStore = StatisticsStore(),
        bundleIdentifier: String,
        now: @escaping () -> Date = Date.init,
        notificationCenter: NotificationCenter = .default,
        aiQuizAccessStore: AIQuizAccessStore = AIQuizAccessStore(),
        deletionStateStore: AccountDeletionStateStore = AccountDeletionStateStore(),
        eraseLocalAccountData: @escaping (String) throws -> Void = { _ in }
    ) {
        self.gameCenter = gameCenter
        self.api = api
        self.sessionStore = sessionStore
        self.statisticsStore = statisticsStore
        self.bundleIdentifier = bundleIdentifier
        self.now = now
        self.notificationCenter = notificationCenter
        self.aiQuizAccessStore = aiQuizAccessStore
        self.deletionStateStore = deletionStateStore
        self.eraseLocalAccountData = eraseLocalAccountData
        pendingSyncObserver = notificationCenter.addObserver(
            forName: .statisticsPendingSync,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.synchronizeStatistics()
            }
        }
        authenticationInvalidationObserver = notificationCenter.addObserver(
            forName: .backendAuthenticationInvalidated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleBackendAuthenticationInvalidation()
            }
        }
    }

    deinit {
        if let pendingSyncObserver {
            notificationCenter.removeObserver(pendingSyncObserver)
        }
        if let authenticationInvalidationObserver {
            notificationCenter.removeObserver(authenticationInvalidationObserver)
        }
    }

    static func live(bundle: Bundle = .main) -> GameCenterAuthenticationService {
        let api: AuthAPI
        if let configuration = BackendConfiguration.load(bundle: bundle) {
            let httpAPI = HTTPAuthAPI(
                configuration: configuration,
                metrics: AppMetricaAnalyticsTracker.shared
            )
            api = httpAPI
        } else {
            AppLog.auth.error("[Auth] Backend configuration is unavailable")
            api = UnavailableAuthAPI()
        }
        let service = GameCenterAuthenticationService(
            gameCenter: GameCenterClient(),
            api: api,
            sessionStore: KeychainSessionStore(),
            bundleIdentifier: bundle.bundleIdentifier ?? "ru.avtabenskiy.Quizice",
            aiQuizAccessStore: .shared,
            eraseLocalAccountData: { userID in
                try PersistentQuestionAnswerOutbox.shared.eraseData(for: userID)
                OnboardingProgressStore.shared.eraseData(for: userID)
                try ThemeCatalogRepository.shared.eraseCachedPersonalization()
                QuizSessionStore.shared.chosenTheme = nil
                URLCache.shared.removeAllCachedResponses()
            }
        )
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let enabled = ["1", "true", "yes"].contains(
            environment["DEV_AUTH_ENABLED"]?.lowercased() ?? ""
        )
        if enabled,
           let configuration = BackendConfiguration.load(bundle: bundle),
           let secret = environment["DEV_AUTH_SECRET"] {
            service.devAuthenticationProvider = DevAuthenticationProvider(
                api: HTTPAuthAPI(
                    configuration: configuration,
                    metrics: AppMetricaAnalyticsTracker.shared
                ),
                developerUserIDStore: KeychainDeveloperUserIDStore(),
                secret: secret
            )
        }
#endif
        return service
    }

    func start(present: @escaping (UIViewController) -> Void) {
        guard started == false else { return }
        started = true
        state = .initializing
        statisticsStore.activateGuest()
        aiQuizAccessStore.update(isAuthenticated: false)
        if let pending = deletionStateStore.pendingRecord {
            currentTeamPlayerID = pending.teamPlayerID
            state = .deletionPending
        }
#if DEBUG
        if let devAuthenticationProvider, deletionRecord == nil {
            beginDevAuthentication(using: devAuthenticationProvider)
            return
        }
#endif
        gameCenter.start(present: present) { [weak self] playerState in
            self?.handle(playerState)
        }
    }

    func waitForInitialAuthentication() async { await initialAuthentication.wait() }

    func signIn(present: @escaping (UIViewController) -> Void) {
        guard started else { start(present: present); return }
        guard !accountOperationInProgress, deletionRecord == nil,
              accountAccessState == .signInRequired else { return }
        state = .initializing
        gameCenter.start(present: present) { [weak self] playerState in
            self?.handle(playerState)
        }
    }

#if DEBUG
    private func beginDevAuthentication(using provider: AuthenticationProvider) {
        authenticationTask?.cancel()
        synchronizationTask?.cancel()
        synchronizationTask = nil
        synchronizationAttemptID = nil
        statisticsStore.activateGuest()
        let attemptID = UUID()
        authenticationAttemptID = attemptID
        state = .authenticating
        authenticationTask = Task { [weak self] in
            guard let self else { return }
            do {
                if let cached = self.loadStoredSession(),
                   cached.teamPlayerID.hasPrefix("dev:"),
                   cached.expiresAt > self.now() {
                    self.currentTeamPlayerID = cached.teamPlayerID
                    self.completeAuthentication(
                        with: cached,
                        attemptID: attemptID,
                        statisticsMayRefreshToken: false
                    )
                    return
                }
                self.clearStoredSession()
                let session = try await provider.authenticate()
                try Task.checkCancellation()
                try self.sessionStore.save(session)
                self.currentTeamPlayerID = session.teamPlayerID
                self.completeAuthentication(
                    with: session,
                    attemptID: attemptID,
                    statisticsMayRefreshToken: false
                )
            } catch is CancellationError {
                return
            } catch {
                AppLog.auth.error(
                    "DEBUG dev authentication failed: \(String(describing: error), privacy: .public)"
                )
                self.enterGuestMode()
            }
        }
    }
#endif

    func retrySynchronization() {
        guard !accountOperationInProgress, deletionRecord == nil else { return }
        if case .guest = state, let teamPlayerID = currentTeamPlayerID {
            forceRefreshSession(
                for: teamPlayerID,
                statisticsMayRefreshToken: true
            )
            return
        }
        synchronizeStatistics()
    }

    private func handle(_ playerState: GameCenterPlayerState) {
        guard !accountOperationInProgress else {
            deferredPlayerState = playerState
            return
        }
        if deletionRecord?.cleanupCompleted == false {
            // Keep the deletion credential until the pending request/cleanup
            // is resolved, even if Game Center changes on this device.
            deferredPlayerState = playerState
            return
        }
        switch playerState {
        case let .authenticated(teamPlayerID):
            guard teamPlayerID.isEmpty == false else {
                enterGuestMode()
                return
            }
            if let record = deletionStateStore.record(for: teamPlayerID) {
                currentTeamPlayerID = teamPlayerID
                stopAccountWork()
                state = record.cleanupCompleted ? .guest : .deletionPending
                aiQuizAccessStore.update(isAuthenticated: false)
                return
            }
            if currentTeamPlayerID == teamPlayerID,
               case .authenticated = state {
                synchronizeStatistics()
                return
            }
            beginAuthentication(
                for: teamPlayerID,
                allowsCachedSession: true,
                statisticsMayRefreshToken: true
            )
        case .unavailable:
            enterGuestMode()
        }
    }

    private func beginAuthentication(
        for teamPlayerID: String,
        allowsCachedSession: Bool,
        statisticsMayRefreshToken: Bool
    ) {
        authenticationTask?.cancel()
        synchronizationTask?.cancel()
        synchronizationTask = nil
        synchronizationAttemptID = nil
        statisticsStore.activateGuest()
        if currentTeamPlayerID != teamPlayerID {
            // Remove the previous account before any asynchronous exchange starts.
            // Content, preferences and answer queues all read this same session.
            if let cached = loadStoredSession(), cached.teamPlayerID != teamPlayerID {
                clearStoredSession()
            }
        }
        let attemptID = UUID()
        authenticationAttemptID = attemptID
        currentTeamPlayerID = teamPlayerID
        state = .authenticating
        aiQuizAccessStore.update(isAuthenticated: false)
        authenticationTask = Task { [weak self] in
            await self?.restoreOrExchangeSession(
                for: teamPlayerID,
                allowsCachedSession: allowsCachedSession,
                statisticsMayRefreshToken: statisticsMayRefreshToken,
                attemptID: attemptID
            )
        }
    }

    private func restoreOrExchangeSession(
        for teamPlayerID: String,
        allowsCachedSession: Bool,
        statisticsMayRefreshToken: Bool,
        attemptID: UUID
    ) async {
        if allowsCachedSession,
           let cachedSession = loadStoredSession(),
           cachedSession.isValid(for: teamPlayerID, now: now()) {
            AppLog.auth.notice("[Auth] Restoring a valid cached backend session")
            completeAuthentication(
                with: cachedSession,
                attemptID: attemptID,
                statisticsMayRefreshToken: statisticsMayRefreshToken
            )
            return
        }
        clearStoredSession()

        do {
            let session = try await exchangeSession(
                for: teamPlayerID,
                attemptID: attemptID
            )
            try Task.checkCancellation()
            completeAuthentication(
                with: session,
                attemptID: attemptID,
                statisticsMayRefreshToken: statisticsMayRefreshToken
            )
        } catch is CancellationError {
            return
        } catch let BackendAPIError.httpStatus(_, envelope) where envelope?.code.lowercased() == "account_deleted" {
            guard currentTeamPlayerID == teamPlayerID, authenticationAttemptID == attemptID else { return }
            // Another device may have deleted this account. The server's
            // verified-identity response must never trigger automatic creation.
            let previousUserID = deletionStateStore.lastKnownUserID(for: teamPlayerID)
            deletionStateStore.save(.init(userID: previousUserID ?? "deleted:\(teamPlayerID)",
                                         teamPlayerID: teamPlayerID, idempotencyKey: UUID().uuidString,
                                         serverConfirmed: true, cleanupCompleted: false))
            state = .deletionPending
            do {
                try await deleteAccount()
            } catch {
                AppLog.auth.error("Local cleanup remains pending after server-reported account deletion")
            }
        } catch is GameCenterAuthenticationError {
            guard
                currentTeamPlayerID == teamPlayerID,
                authenticationAttemptID == attemptID
            else { return }
            enterGuestMode()
        } catch {
            guard
                currentTeamPlayerID == teamPlayerID,
                authenticationAttemptID == attemptID
            else { return }
            let diagnostic = error as NSError
            AppLog.auth.error(
                "[Auth] Backend session exchange failed: domain=\(diagnostic.domain, privacy: .public) code=\(diagnostic.code)"
            )
            enterGuestMode(preservingGameCenterPlayer: true)
        }
    }

    private func exchangeSession(
        for teamPlayerID: String,
        attemptID: UUID
    ) async throws -> AuthSession {
        let identity = try await gameCenter.fetchIdentity(bundleIdentifier: bundleIdentifier)
        try Task.checkCancellation()
        guard
            identity.teamPlayerId == teamPlayerID,
            currentTeamPlayerID == teamPlayerID,
            authenticationAttemptID == attemptID
        else {
            throw GameCenterAuthenticationError.playerChanged
        }
        AppLog.auth.notice("[Auth] Sending Game Center identity to backend")
        let session = try await api.authenticate(identity: identity)
        AppLog.auth.notice("[Auth] Backend issued a session; saving to Keychain")
        try Task.checkCancellation()
        guard
            session.teamPlayerID == teamPlayerID,
            currentTeamPlayerID == teamPlayerID,
            authenticationAttemptID == attemptID
        else {
            throw GameCenterAuthenticationError.playerChanged
        }
        try sessionStore.save(session)
        return session
    }

    private func completeAuthentication(
        with session: AuthSession,
        attemptID: UUID,
        statisticsMayRefreshToken: Bool
    ) {
        guard
            currentTeamPlayerID == session.teamPlayerID,
            authenticationAttemptID == attemptID
        else { return }
        authenticationAttemptID = nil
        authenticationTask = nil
        deletionStateStore.remember(session)
        statisticsStore.activateAuthenticatedUser(session.userID)
        state = .authenticated(userID: session.userID, teamPlayerID: session.teamPlayerID)
        AppLog.auth.notice("[Auth] Backend session established")
        aiQuizAccessStore.update(isAuthenticated: true)
        notificationCenter.post(name: .backendAuthenticationEstablished, object: nil)
        synchronizeStatistics(
            using: session,
            mayRefreshToken: statisticsMayRefreshToken
        )
    }

    private func enterGuestMode(preservingGameCenterPlayer: Bool = false) {
        if deletionRecord?.cleanupCompleted == false {
            stopAccountWork()
            state = .deletionPending
            aiQuizAccessStore.update(isAuthenticated: false)
            return
        }
        authenticationTask?.cancel()
        authenticationTask = nil
        authenticationAttemptID = nil
        synchronizationTask?.cancel()
        synchronizationTask = nil
        synchronizationAttemptID = nil
        if preservingGameCenterPlayer == false {
            currentTeamPlayerID = nil
        }
        clearStoredSession()
        statisticsStore.activateGuest()
        state = .guest
        aiQuizAccessStore.update(isAuthenticated: false)
    }

    private func synchronizeStatistics(
        using knownSession: AuthSession? = nil,
        mayRefreshToken: Bool = true
    ) {
        guard synchronizationTask == nil, !accountOperationInProgress, deletionRecord == nil else { return }
        let storedSession = knownSession ?? loadStoredSession()
        guard
            let session = storedSession,
            case let .authenticated(userID, teamPlayerID) = state,
            userID == session.userID,
            teamPlayerID == session.teamPlayerID
        else {
            return
        }

        let attemptID = UUID()
        synchronizationAttemptID = attemptID
        synchronizationTask = Task { [weak self] in
            guard let self else { return }
            let didSync = await self.performStatisticsSync(
                session: session,
                mayRefreshToken: mayRefreshToken
            )
            guard self.synchronizationAttemptID == attemptID else { return }
            self.synchronizationTask = nil
            self.synchronizationAttemptID = nil
            if didSync, self.statisticsStore.hasPendingSync(for: session.userID) {
                self.synchronizeStatistics()
            }
        }
    }

    private func performStatisticsSync(session: AuthSession, mayRefreshToken: Bool) async -> Bool {
        let request = statisticsStore.makeSyncRequest(for: session.userID)
        AppLog.auth.notice("[Auth] Synchronizing statistics: attempts=\(request.attempts.count)")
        do {
            let response = try await api.syncStatistics(
                request: request,
                accessToken: session.accessToken
            )
            guard !Task.isCancelled, state == .authenticated(userID: session.userID, teamPlayerID: session.teamPlayerID) else {
                return false
            }
            statisticsStore.applySyncResponse(response, for: session.userID)
            return true
        } catch BackendAPIError.unauthorized where mayRefreshToken {
            guard !Task.isCancelled, state == .authenticated(userID: session.userID, teamPlayerID: session.teamPlayerID) else { return false }
            forceRefreshSession(
                for: session.teamPlayerID,
                statisticsMayRefreshToken: false
            )
            return false
        } catch BackendAPIError.unauthorized {
            guard !Task.isCancelled, state == .authenticated(userID: session.userID, teamPlayerID: session.teamPlayerID) else { return false }
            enterGuestMode()
            return false
        } catch {
            // Keep the local outbox intact. Foregrounding or the next completed quiz retries it.
            return false
        }
    }

    private func handleBackendAuthenticationInvalidation() {
        guard !accountOperationInProgress, deletionRecord == nil else { return }
#if DEBUG
        if let devAuthenticationProvider {
            clearStoredSession()
            beginDevAuthentication(using: devAuthenticationProvider)
            return
        }
#endif
        guard let teamPlayerID = currentTeamPlayerID else {
            enterGuestMode()
            return
        }
        forceRefreshSession(
            for: teamPlayerID,
            statisticsMayRefreshToken: true
        )
    }

    private func forceRefreshSession(
        for teamPlayerID: String,
        statisticsMayRefreshToken: Bool
    ) {
        guard currentTeamPlayerID == teamPlayerID, !accountOperationInProgress,
              deletionStateStore.record(for: teamPlayerID) == nil else { return }
        if state == .authenticating, authenticationTask != nil {
            return
        }
        synchronizationTask?.cancel()
        synchronizationTask = nil
        synchronizationAttemptID = nil
        beginAuthentication(
            for: teamPlayerID,
            allowsCachedSession: false,
            statisticsMayRefreshToken: statisticsMayRefreshToken
        )
    }

    private func clearStoredSession() {
        do {
            if let session = try? sessionStore.loadForAccountDeletion() {
                deletionStateStore.remember(session)
            }
            try sessionStore.clear()
        } catch {
            AppLog.auth.error(
                "Failed to clear stored session: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func loadStoredSession() -> AuthSession? {
        do {
            return try sessionStore.load()
        } catch {
            AppLog.auth.error(
                "Failed to load stored session: \(String(describing: error), privacy: .public)"
            )
            return nil
        }
    }

    private var deletionRecord: AccountDeletionStateStore.Record? {
        currentTeamPlayerID.flatMap { deletionStateStore.record(for: $0) }
    }

    var accountDeletionAvailable: Bool {
        if let record = deletionRecord { return !record.cleanupCompleted }
        guard case .authenticated = state else { return false }
        return (try? sessionStore.loadForAccountDeletion()) != nil
    }

    var canCreateAccount: Bool { deletionRecord?.cleanupCompleted == true }

    func deleteAccount() async throws {
        guard !accountOperationInProgress else { throw AccountDeletionError.inProgress }
        guard accountDeletionAvailable else { throw AccountDeletionError.unavailable }
        let storedSession = try sessionStore.loadForAccountDeletion()
        let recordWasNew = deletionRecord == nil
        let record: AccountDeletionStateStore.Record
        if let existing = deletionRecord {
            record = existing
        } else if let session = storedSession, session.teamPlayerID == currentTeamPlayerID {
            record = .init(userID: session.userID, teamPlayerID: session.teamPlayerID,
                           idempotencyKey: UUID().uuidString, serverConfirmed: false, cleanupCompleted: false)
        } else {
            throw AccountDeletionError.unavailable
        }
        deletionStateStore.save(record)
        accountOperationInProgress = true
        stopAccountWork()
        state = .deletionPending
        aiQuizAccessStore.update(isAuthenticated: false)
        var refreshSessionAfterFailure = false
        defer {
            finishAccountOperation()
            if refreshSessionAfterFailure {
                forceRefreshSession(for: record.teamPlayerID, statisticsMayRefreshToken: true)
            }
        }
        var receipt = record
        if !receipt.serverConfirmed {
            guard let session = storedSession, session.userID == receipt.userID else {
                throw AccountDeletionError.sessionExpired
            }
            do {
                try await api.deleteAccount(accessToken: session.accessToken, idempotencyKey: receipt.idempotencyKey)
            } catch AccountDeletionError.sessionExpired where recordWasNew {
                // The server checks completed idempotency receipts before auth:
                // this first-request 401 confirms that this key did not delete.
                // Refresh normally; a tombstoned account returns account_deleted.
                deletionStateStore.remove(for: receipt.teamPlayerID)
                state = .guest
                refreshSessionAfterFailure = true
                throw AccountDeletionError.sessionExpired
            } catch AccountDeletionError.sessionExpired {
                try await AccountDeletionRecovery.confirmDeletion(
                    receipt: receipt, api: api, gameCenter: gameCenter, bundleIdentifier: bundleIdentifier,
                    isCurrentIdentity: { [weak self] in
                        self?.currentTeamPlayerID == receipt.teamPlayerID &&
                            (self?.deferredPlayerState == nil || self?.deferredPlayerState == .authenticated(teamPlayerID: receipt.teamPlayerID))
                    }
                )
            } catch let BackendAPIError.httpStatus(status, _) where [404, 405, 422, 501].contains(status) && recordWasNew {
                // The first request was rejected without performing deletion.
                // Keep the existing account usable while the API is unavailable.
                deletionStateStore.remove(for: receipt.teamPlayerID)
                state = .authenticated(userID: session.userID, teamPlayerID: session.teamPlayerID)
                aiQuizAccessStore.update(isAuthenticated: true)
                throw BackendAPIError.httpStatus(status, nil)
            }
            receipt.serverConfirmed = true
            deletionStateStore.save(receipt)
        }
        do {
            // Never clear a different account's Keychain session.
            if try sessionStore.loadForAccountDeletion()?.userID == receipt.userID {
                try sessionStore.clear()
            }
            statisticsStore.eraseData(for: receipt.userID)
            try eraseLocalAccountData(receipt.userID)
        } catch {
            throw AccountDeletionError.localCleanupFailed
        }
        receipt.cleanupCompleted = true
        deletionStateStore.save(receipt)
        deletionStateStore.forgetUser(for: receipt.teamPlayerID)
        statisticsStore.activateGuest()
        state = .guest
        notificationCenter.post(name: .backendAccountDeleted, object: nil)
    }

    func createAccount() async throws {
        guard !accountOperationInProgress else { throw AccountDeletionError.inProgress }
        guard let receipt = deletionRecord, receipt.cleanupCompleted else { throw AccountDeletionError.unavailable }
        accountOperationInProgress = true
        defer { finishAccountOperation() }
        let identity: GameCenterIdentity
        do { identity = try await gameCenter.fetchIdentity(bundleIdentifier: bundleIdentifier) }
        catch GameCenterClientError.notAuthenticated {
            enterGuestMode()
            throw GameCenterClientError.notAuthenticated
        }
        guard identity.teamPlayerId == receipt.teamPlayerID else {
            if deferredPlayerState == nil { deferredPlayerState = .authenticated(teamPlayerID: identity.teamPlayerId) }
            throw GameCenterAuthenticationError.playerChanged
        }
        let session = try await api.authenticate(identity: identity, recreateDeletedAccount: true)
        guard session.teamPlayerID == receipt.teamPlayerID, session.userID != receipt.userID else {
            throw BackendAPIError.contractViolation
        }
        try sessionStore.save(session)
        deletionStateStore.remove(for: receipt.teamPlayerID)
        let attemptID = UUID()
        authenticationAttemptID = attemptID
        completeAuthentication(with: session, attemptID: attemptID, statisticsMayRefreshToken: true)
    }

    private func stopAccountWork() {
        authenticationTask?.cancel()
        authenticationTask = nil
        authenticationAttemptID = nil
        synchronizationTask?.cancel()
        synchronizationTask = nil
        synchronizationAttemptID = nil
    }

    private func finishAccountOperation() {
        accountOperationInProgress = false
        if let deferredPlayerState {
            self.deferredPlayerState = nil
            handle(deferredPlayerState)
        } else if deletionRecord == nil {
            synchronizeStatistics()
        }
    }
}
