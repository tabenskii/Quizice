import Foundation
import UIKit

extension Notification.Name {
    static let backendAuthenticationInvalidated = Notification.Name(
        "ru.avtabenskiy.Quizice.backendAuthenticationInvalidated"
    )
    static let backendAuthenticationEstablished = Notification.Name(
        "ru.avtabenskiy.Quizice.backendAuthenticationEstablished"
    )
    static let backendAccountDeleted = Notification.Name("quizice.backend-account-deleted")
}

enum AuthSessionState: Equatable {
    case initializing
    case guest
    case authenticating
    case authenticated(userID: String, teamPlayerID: String)
    case deletionPending
}

/// Startup waiting has its own lifetime: cancelling a splash waiter must leave
/// Game Center and backend authentication running for the account presenter.
@MainActor
final class InitialAuthenticationReadiness {
    private var resolved = false
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    func wait() async {
        guard !resolved, !Task.isCancelled else { return }
        let waiterID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !resolved, !Task.isCancelled else {
                    continuation.resume()
                    return
                }
                waiters[waiterID] = continuation
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.waiters.removeValue(forKey: waiterID)?.resume()
            }
        }
    }

    func resolveIfNeeded(_ state: AuthSessionState) {
        switch state {
        case .initializing, .authenticating: return
        case .authenticated, .guest, .deletionPending: break
        }
        guard !resolved else { return }
        resolved = true
        let pending = Array(waiters.values)
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

enum GameCenterAuthenticationError: Error, Equatable {
    case playerChanged
}

/// Only authenticated accounts may enter the app's quiz screens. The legacy
/// guest storage scope is never an app-access state.
enum AppAccountAccessState: Equatable {
    case loading
    case signInRequired
    case authenticated
    case deletionPending
    case deleted
}

@MainActor
protocol AppAccountAccessProviding: AnyObject {
    var accountAccessState: AppAccountAccessState { get }
    var authenticatedAccountID: String? { get }
    var accountAccessStateDidChange: ((AppAccountAccessState) -> Void)? { get set }
    func signIn(present: @escaping (UIViewController) -> Void)
}

extension AppAccountAccessProviding {
    var authenticatedAccountID: String? { nil }
}

@MainActor
protocol AccountManaging: AnyObject {
    var accountDeletionAvailable: Bool { get }
    var canCreateAccount: Bool { get }
    func deleteAccount() async throws
    func createAccount() async throws
}

enum AccountDeletionError: Error, Equatable {
    case unavailable
    case inProgress
    case localCleanupFailed
    case sessionExpired
}

/// A small local receipt prevents Game Center from silently recreating a deleted
/// account, and preserves the same idempotency key after a lost server response.
final class AccountDeletionStateStore {
    struct Record: Equatable {
        let userID: String
        let teamPlayerID: String
        let idempotencyKey: String
        var serverConfirmed: Bool
        var cleanupCompleted: Bool
    }

    private let defaults: UserDefaults
    private let key = "quizice.account-deletion.receipts"
    private let knownUsersKey = "quizice.account-deletion.known-users"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func record(for teamPlayerID: String) -> Record? {
        guard let values = defaults.dictionary(forKey: key)?[teamPlayerID] as? [String: Any],
              let userID = values["userID"] as? String,
              let idempotencyKey = values["idempotencyKey"] as? String else { return nil }
        return Record(userID: userID, teamPlayerID: teamPlayerID, idempotencyKey: idempotencyKey,
                      serverConfirmed: values["serverConfirmed"] as? Bool ?? false,
                      cleanupCompleted: values["cleanupCompleted"] as? Bool ?? false)
    }

    func blocks(_ session: AuthSession) -> Bool {
        record(for: session.teamPlayerID)?.userID == session.userID
    }

    /// Keep the account scope independently of the bearer token. A failed token
    /// refresh must not lose the identity needed to erase data after a later 409.
    func remember(_ session: AuthSession) {
        var users = defaults.dictionary(forKey: knownUsersKey) as? [String: String] ?? [:]
        users[session.teamPlayerID] = session.userID
        defaults.set(users, forKey: knownUsersKey)
    }

    func lastKnownUserID(for teamPlayerID: String) -> String? {
        defaults.dictionary(forKey: knownUsersKey)?[teamPlayerID] as? String
    }

    func forgetUser(for teamPlayerID: String) {
        var users = defaults.dictionary(forKey: knownUsersKey) as? [String: String] ?? [:]
        users.removeValue(forKey: teamPlayerID)
        defaults.set(users, forKey: knownUsersKey)
    }

    var pendingRecord: Record? {
        (defaults.dictionary(forKey: key) ?? [:]).keys.sorted()
            .compactMap { record(for: $0) }.first { !$0.cleanupCompleted }
    }

    func save(_ record: Record) {
        var records = defaults.dictionary(forKey: key) ?? [:]
        records[record.teamPlayerID] = ["userID": record.userID, "idempotencyKey": record.idempotencyKey,
                                       "serverConfirmed": record.serverConfirmed,
                                       "cleanupCompleted": record.cleanupCompleted]
        defaults.set(records, forKey: key)
    }

    func remove(for teamPlayerID: String) {
        var records = defaults.dictionary(forKey: key) ?? [:]
        records.removeValue(forKey: teamPlayerID)
        defaults.set(records, forKey: key)
    }
}

protocol AIQuizAccessProviding: AnyObject {
    var isAIQuizAvailable: Bool { get }
}

protocol AIQuizAccessUpdating: AIQuizAccessProviding {
    func update(isAuthenticated: Bool)
}

final class AIQuizAccessStore: AIQuizAccessUpdating, @unchecked Sendable {
    static let shared = AIQuizAccessStore()

    private let lock = NSLock()
    private var isAuthenticated = false

    var isAIQuizAvailable: Bool {
        lock.withLock { isAuthenticated }
    }

    func update(isAuthenticated: Bool) {
        lock.withLock {
            self.isAuthenticated = isAuthenticated
        }
    }
}

struct AuthSession: Codable, Equatable {
    let userID: String
    let accessToken: String
    let expiresAt: Date
    let teamPlayerID: String

    func isValid(for teamPlayerID: String, now: Date) -> Bool {
        self.teamPlayerID == teamPlayerID && expiresAt > now
    }
}

protocol AuthenticationProvider {
    func authenticate() async throws -> AuthSession
}

struct GameCenterAuthenticationProvider: AuthenticationProvider {
    private let operation: () async throws -> AuthSession

    init(operation: @escaping () async throws -> AuthSession) {
        self.operation = operation
    }

    func authenticate() async throws -> AuthSession { try await operation() }
}

#if DEBUG
protocol DevAuthAPI {
    func authenticate(developerUserID: UUID, secret: String) async throws -> AuthSession
}

struct DevAuthenticationProvider: AuthenticationProvider {
    let api: DevAuthAPI
    let developerUserIDStore: DeveloperUserIDStoring
    let secret: String

    func authenticate() async throws -> AuthSession {
        let normalizedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSecret.isEmpty else { throw BackendAPIError.configurationMissing }
        return try await api.authenticate(
            developerUserID: try developerUserIDStore.loadOrCreate(),
            secret: normalizedSecret
        )
    }
}
#endif

struct GameCenterIdentity: Codable, Equatable {
    let teamPlayerId: String
    let bundleId: String
    let publicKeyUrl: String
    let signature: String
    let salt: String
    let timestamp: String
}

struct BackendErrorEnvelope: Codable, Equatable {
    let code: String
    let message: String
    let requestId: String?

    init(code: String, message: String, requestId: String? = nil) {
        self.code = code
        self.message = message
        self.requestId = requestId
    }
}

enum BackendAPIError: Error, Equatable {
    case configurationMissing
    case invalidResponse
    case transport(URLError.Code)
    case unauthorized(BackendErrorEnvelope?)
    case httpStatus(Int, BackendErrorEnvelope?)
    case encoding
    case decoding
    case contractViolation
}

protocol AuthAPI {
    func authenticate(identity: GameCenterIdentity) async throws -> AuthSession
    func authenticate(identity: GameCenterIdentity, recreateDeletedAccount: Bool) async throws -> AuthSession
    func deleteAccount(accessToken: String, idempotencyKey: String) async throws
    func syncStatistics(
        request: StatisticsStore.SyncRequest,
        accessToken: String
    ) async throws -> StatisticsStore.SyncResponse
}

extension AuthAPI {
    func authenticate(identity: GameCenterIdentity, recreateDeletedAccount: Bool) async throws -> AuthSession {
        try await authenticate(identity: identity)
    }

    func deleteAccount(accessToken: String, idempotencyKey: String) async throws {
        throw AccountDeletionError.unavailable
    }
}

protocol SessionStoring {
    func load() throws -> AuthSession?
    func loadForAccountDeletion() throws -> AuthSession?
    func save(_ session: AuthSession) throws
    func clear() throws
}

extension SessionStoring {
    func loadForAccountDeletion() throws -> AuthSession? { try load() }
}

enum GameCenterPlayerState: Equatable {
    case authenticated(teamPlayerID: String)
    case unavailable
}

@MainActor
protocol GameCenterAuthenticating: AnyObject {
    func start(
        present: @escaping (UIViewController) -> Void,
        stateChanged: @escaping (GameCenterPlayerState) -> Void
    )
    func fetchIdentity(bundleIdentifier: String) async throws -> GameCenterIdentity
}
