import Foundation
import Security

protocol KeychainClient {
    func loadData(service: String, account: String) throws -> Data?
    func saveData(_ data: Data, service: String, account: String) throws
    func deleteData(service: String, account: String) throws
}

enum KeychainClientError: Error, Equatable {
    case status(OSStatus)
}

struct SecurityKeychainClient: KeychainClient {
    func loadData(service: String, account: String) throws -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainClientError.status(status)
        }
        return data
    }

    func saveData(_ data: Data, service: String, account: String) throws {
        let query = baseQuery(service: service, account: account)
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw KeychainClientError.status(status)
        }
    }

    func deleteData(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainClientError.status(status)
        }
    }

    private func baseQuery(service: String, account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }
}

final class KeychainSessionStore: SessionStoring {
    private let service: String
    private let account = "game-center-session"
    private let client: KeychainClient
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let deletionStateStore: AccountDeletionStateStore

    init(
        service: String = "ru.avtabenskiy.Quizice.auth",
        client: KeychainClient = SecurityKeychainClient(),
        deletionStateStore: AccountDeletionStateStore = AccountDeletionStateStore()
    ) {
        self.service = service
        self.client = client
        self.deletionStateStore = deletionStateStore
    }

    func load() throws -> AuthSession? {
        guard let session = try loadForAccountDeletion(), !deletionStateStore.blocks(session) else { return nil }
        return session
    }

    func loadForAccountDeletion() throws -> AuthSession? {
        let data: Data?
        do {
            data = try client.loadData(service: service, account: account)
        } catch {
            throw mapClientError(error)
        }
        guard let data else { return nil }

        do {
            return try decoder.decode(AuthSession.self, from: data)
        } catch {
            try? clear()
            throw KeychainSessionStoreError.invalidData
        }
    }

    func save(_ session: AuthSession) throws {
        let data: Data
        do {
            data = try encoder.encode(session)
        } catch {
            throw KeychainSessionStoreError.invalidData
        }

        do {
            try client.saveData(data, service: service, account: account)
        } catch {
            throw mapClientError(error)
        }
    }

    func clear() throws {
        do {
            try client.deleteData(service: service, account: account)
        } catch {
            throw mapClientError(error)
        }
    }

    private func mapClientError(_ error: Error) -> Error {
        guard case let KeychainClientError.status(status) = error else { return error }
        return KeychainSessionStoreError.status(status)
    }
}

enum KeychainSessionStoreError: Error, Equatable {
    case status(OSStatus)
    case invalidData
}

#if DEBUG
/// A provisioned test session is scoped to one backend and never embedded in the app.
final class DebugBackendSessionStore {
    private struct ProvisionedSession: Codable {
        let backendBaseURL: String
        let session: AuthSession
    }

    private let client: KeychainClient
    private let service = "ru.avtabenskiy.Quizice.debug-backend"

    init(client: KeychainClient = SecurityKeychainClient()) {
        self.client = client
    }

    func load(
        configuration: BackendConfiguration,
        environment: [String: String] = [:],
        now: Date = Date()
    ) throws -> AuthSession? {
        let account = configuration.baseURL.absoluteString
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let encoded = environment["QUIZICE_DEBUG_SESSION_BASE64"] {
            guard let data = Data(base64Encoded: encoded) else {
                throw BackendAPIError.configurationMissing
            }
            let imported = try decoder.decode(ProvisionedSession.self, from: data)
            try validate(imported, configuration: configuration, now: now)
            try client.saveData(data, service: service, account: account)
            return imported.session
        }
        guard let data = try client.loadData(service: service, account: account) else { return nil }
        let stored = try decoder.decode(ProvisionedSession.self, from: data)
        try validate(stored, configuration: configuration, now: now)
        return stored.session
    }

    func save(_ session: AuthSession, configuration: BackendConfiguration) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let value = ProvisionedSession(backendBaseURL: configuration.baseURL.absoluteString, session: session)
        try validate(value, configuration: configuration, now: Date())
        try client.saveData(encoder.encode(value), service: service, account: configuration.baseURL.absoluteString)
    }

    func clear(configuration: BackendConfiguration) throws {
        try client.deleteData(service: service, account: configuration.baseURL.absoluteString)
    }

    private func validate(_ value: ProvisionedSession, configuration: BackendConfiguration, now: Date) throws {
        guard BackendConfiguration.configuration(from: value.backendBaseURL) == configuration,
              value.session.teamPlayerID.hasPrefix("dev:"),
              UUID(uuidString: String(value.session.teamPlayerID.dropFirst(4))) != nil,
              UUID(uuidString: value.session.userID) != nil,
              !value.session.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.session.expiresAt > now else {
            throw BackendAPIError.configurationMissing
        }
    }
}

/// A private, revocable key can only renew the server-selected test account.
struct DebugTestAccountProvider: AuthenticationProvider {
    static let didConnect = Notification.Name("Quizice.debugTestAccountDidConnect")
    private let keyService = "ru.avtabenskiy.Quizice.debug-test-account-key"
    let configuration: BackendConfiguration
    let client: KeychainClient
    let request: (String) async throws -> AuthSession
    let now: () -> Date

    init(configuration: BackendConfiguration, client: KeychainClient = SecurityKeychainClient(),
         now: @escaping () -> Date = Date.init,
         request: ((String) async throws -> AuthSession)? = nil) {
        self.configuration = configuration
        self.client = client
        self.now = now
        self.request = request ?? { secret in
            try await HTTPAuthAPI(configuration: configuration).authenticateTestAccount(secret: secret)
        }
    }

    static func configured(configuration: BackendConfiguration,
                           environment: [String: String]) throws -> DebugTestAccountProvider? {
        let provider = DebugTestAccountProvider(configuration: configuration)
        if let key = environment["QUIZICE_TEST_ACCOUNT_KEY"] { try provider.saveKey(key) }
        return try provider.loadKey() == nil ? nil : provider
    }

    func loadKey() throws -> String? {
        guard let data = try client.loadData(service: keyService, account: configuration.baseURL.absoluteString),
              let key = String(data: data, encoding: .utf8) else { return nil }
        return key
    }

    func saveKey(_ key: String) throws {
        guard (32...256).contains(key.count),
              key.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-" )).contains($0) }) else {
            throw BackendAPIError.configurationMissing
        }
        if try loadKey() != key {
            try invalidate()
            try client.saveData(Data(key.utf8), service: keyService, account: configuration.baseURL.absoluteString)
        }
    }

    func authenticate() async throws -> AuthSession {
        guard let key = try loadKey() else { throw BackendAPIError.configurationMissing }
        let store = DebugBackendSessionStore(client: client)
        let cached = try? store.load(configuration: configuration, now: now())
        if let cached, cached.expiresAt.timeIntervalSince(now()) > 86_400 { return cached }
        do {
            let session = try await request(key)
            try Task.checkCancellation()
            try store.save(session, configuration: configuration)
            return session
        } catch {
            // Keep a still-valid session during a transient outage; never accept rejection.
            if let cached, Self.isTemporary(error) { return cached }
            throw error
        }
    }

    func connect(key: String) async throws -> AuthSession {
        // Validate remotely before replacing the existing account/key.
        let session = try await request(key)
        try Task.checkCancellation()
        try saveKey(key)
        try DebugBackendSessionStore(client: client).save(session, configuration: configuration)
        return session
    }

    func invalidate() throws {
        try DebugBackendSessionStore(client: client).clear(configuration: configuration)
    }

    private static func isTemporary(_ error: Error) -> Bool {
        switch error {
        case BackendAPIError.transport: return true
        case BackendAPIError.httpStatus(let status, _): return status >= 500
        default: return false
        }
    }
}

struct DebugBackendSessionProvider: AuthenticationProvider {
    let store: DebugBackendSessionStore
    let configuration: BackendConfiguration

    static func configured(bundle: Bundle) -> AuthenticationProvider? {
        guard let configuration = BackendConfiguration.load(bundle: bundle) else { return nil }
        let environment = ProcessInfo.processInfo.environment
        guard environment["QUIZICE_REQUIRE_GAME_CENTER"] != "1" else { return nil }
        if ["1", "true", "yes"].contains(environment["DEV_AUTH_ENABLED"]?.lowercased() ?? ""),
           let secret = environment["DEV_AUTH_SECRET"] {
            return DevAuthenticationProvider(
                api: HTTPAuthAPI(configuration: configuration, metrics: AppMetricaAnalyticsTracker.shared),
                developerUserIDStore: KeychainDeveloperUserIDStore(), secret: secret
            )
        }
#if targetEnvironment(simulator)
        if let provider = try? DebugTestAccountProvider.configured(configuration: configuration, environment: environment) {
            return provider
        }
        let store = DebugBackendSessionStore()
        do {
            if try store.load(configuration: configuration, environment: environment) != nil {
                return DebugBackendSessionProvider(store: store, configuration: configuration)
            }
        } catch let KeychainClientError.status(status) {
            AppLog.auth.error("Debug backend Keychain access failed: status=\(status, privacy: .public)")
        } catch {
            // Decoding errors can include credentials: log only a fixed diagnostic.
            AppLog.auth.error("Debug backend session is missing, expired, or invalid")
        }
#endif
        return nil
    }

    func authenticate() async throws -> AuthSession {
        guard let session = try store.load(configuration: configuration) else {
            throw BackendAPIError.configurationMissing
        }
        return session
    }

    func invalidate() throws { try store.clear(configuration: configuration) }
}

protocol DeveloperUserIDStoring {
    func loadOrCreate() throws -> UUID
    func replace() throws -> UUID
}

final class KeychainDeveloperUserIDStore: DeveloperUserIDStoring {
    private let service: String
    private let account = "developer-user-id"
    private let client: KeychainClient

    init(
        service: String = "ru.avtabenskiy.Quizice.auth",
        client: KeychainClient = SecurityKeychainClient()
    ) {
        self.service = service
        self.client = client
    }

    func loadOrCreate() throws -> UUID {
        if let data = try client.loadData(service: service, account: account),
           let value = String(data: data, encoding: .utf8),
           let identifier = UUID(uuidString: value) {
            return identifier
        }
        return try replace()
    }

    func replace() throws -> UUID {
        let identifier = UUID()
        try client.saveData(
            Data(identifier.uuidString.lowercased().utf8),
            service: service,
            account: account
        )
        return identifier
    }
}
#endif
