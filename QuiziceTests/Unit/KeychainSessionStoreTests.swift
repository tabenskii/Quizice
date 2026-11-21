import Foundation
import XCTest
@testable import Quizice

final class KeychainSessionStoreTests: XCTestCase {
#if DEBUG
    func testProvisionedSessionSurvivesRelaunchAndIsBoundToBackend() throws {
        let client = InMemoryKeychainClient()
        let store = DebugBackendSessionStore(client: client)
        let configuration = BackendConfiguration(baseURL: URL(string: "https://example.com/api")!)
        let imported = try store.load(configuration: configuration, environment: debugSessionEnvironment())
        XCTAssertEqual(try store.load(configuration: configuration), imported)
        XCTAssertNil(try store.load(configuration: .init(baseURL: URL(string: "https://other.example/api")!)))
        XCTAssertThrowsError(try store.load(configuration: configuration, now: .distantFuture))
        try store.clear(configuration: configuration)
        XCTAssertNil(try store.load(configuration: configuration))
    }

    func testProvisionedSessionRejectsRealPlayerIdentityAndWrongBackendBeforeSaving() throws {
        let store = DebugBackendSessionStore(client: InMemoryKeychainClient())
        let configuration = BackendConfiguration(baseURL: URL(string: "https://example.com/api")!)
        XCTAssertThrowsError(try store.load(configuration: configuration, environment: debugSessionEnvironment(playerID: "real-game-center-player")))
        XCTAssertThrowsError(try store.load(configuration: configuration, environment: debugSessionEnvironment(backend: "https://other.example/api")))
        XCTAssertThrowsError(try store.load(configuration: configuration, environment: ["QUIZICE_DEBUG_SESSION_BASE64": "invalid"]))
        XCTAssertNil(try store.load(configuration: configuration))
    }

    func testProvisionedProviderInvalidationRemovesCredential() async throws {
        let store = DebugBackendSessionStore(client: InMemoryKeychainClient())
        let configuration = BackendConfiguration(baseURL: URL(string: "https://example.com/api")!)
        _ = try store.load(configuration: configuration, environment: debugSessionEnvironment())
        let provider = DebugBackendSessionProvider(store: store, configuration: configuration)
        _ = try await provider.authenticate()
        try provider.invalidate()
        do {
            _ = try await provider.authenticate()
            XCTFail("Revoked credentials must not be reused")
        } catch { XCTAssertEqual(error as? BackendAPIError, .configurationMissing) }
    }

    func testTestAccountRenewsAutomaticallyAndPreservesIdentity() async throws {
        let client = InMemoryKeychainClient()
        let configuration = BackendConfiguration(baseURL: URL(string: "https://example.com/api")!)
        var current = Date()
        var calls = 0
        let provider = DebugTestAccountProvider(configuration: configuration, client: client, now: { current }) { key in
            XCTAssertEqual(key, String(repeating: "k", count: 43))
            calls += 1
            return AuthSession(userID: "550e8400-e29b-41d4-a716-446655440001", accessToken: "session-\(calls)",
                               expiresAt: current.addingTimeInterval(30 * 86_400),
                               teamPlayerID: "dev:550e8400-e29b-41d4-a716-446655440000")
        }
        let initial = try await provider.connect(key: String(repeating: "k", count: 43))
        let cached = try await provider.authenticate()
        XCTAssertEqual(cached.accessToken, initial.accessToken)
        XCTAssertEqual(calls, 1)
        current = current.addingTimeInterval(29.5 * 86_400)
        let renewed = try await provider.authenticate()
        XCTAssertEqual(renewed.userID, initial.userID)
        XCTAssertEqual(renewed.teamPlayerID, initial.teamPlayerID)
        XCTAssertEqual(renewed.accessToken, "session-2")
        current = current.addingTimeInterval(31 * 86_400)
        let afterExpiry = try await provider.authenticate()
        XCTAssertEqual(afterExpiry.accessToken, "session-3")
        try provider.invalidate()
        XCTAssertNotNil(try provider.loadKey())
        let afterRejection = try await provider.authenticate()
        XCTAssertEqual(afterRejection.accessToken, "session-4")
        let otherBackend = DebugTestAccountProvider(configuration: .init(baseURL: URL(string: "https://other.example/api")!), client: client)
        XCTAssertNil(try otherBackend.loadKey())
    }

    func testTestAccountOutageKeepsOnlyUnexpiredSessionAndRejectionNeverFallsBack() async throws {
        let client = InMemoryKeychainClient()
        let configuration = BackendConfiguration(baseURL: URL(string: "https://example.com/api")!)
        let current = Date()
        let session = AuthSession(userID: "550e8400-e29b-41d4-a716-446655440001", accessToken: "valid-session",
                                  expiresAt: current.addingTimeInterval(3_600),
                                  teamPlayerID: "dev:550e8400-e29b-41d4-a716-446655440000")
        var error: BackendAPIError = .transport(.notConnectedToInternet)
        let provider = DebugTestAccountProvider(configuration: configuration, client: client) { _ in throw error }
        try provider.saveKey(String(repeating: "k", count: 43))
        try DebugBackendSessionStore(client: client).save(session, configuration: configuration)
        let fallback = try await provider.authenticate()
        XCTAssertEqual(fallback.accessToken, session.accessToken)
        error = .unauthorized(nil)
        do { _ = try await provider.authenticate(); XCTFail("Do not reuse rejected credentials") }
        catch { XCTAssertEqual(error as? BackendAPIError, .unauthorized(nil)) }
        let expired = DebugTestAccountProvider(configuration: configuration, client: client,
                                              now: { current.addingTimeInterval(7_200) }) { _ in
            throw BackendAPIError.transport(.notConnectedToInternet)
        }
        do { _ = try await expired.authenticate(); XCTFail("Do not reuse expired sessions") }
        catch { XCTAssertEqual(error as? BackendAPIError, .transport(.notConnectedToInternet)) }
        do { _ = try await provider.connect(key: String(repeating: "x", count: 43)); XCTFail("Invalid key must fail") }
        catch { XCTAssertEqual(error as? BackendAPIError, .unauthorized(nil)) }
        XCTAssertEqual(try provider.loadKey(), String(repeating: "k", count: 43))
    }

    private func debugSessionEnvironment(
        playerID: String = "dev:550e8400-e29b-41d4-a716-446655440000",
        backend: String = "https://example.com/api"
    ) throws -> [String: String] {
        let data = try JSONSerialization.data(withJSONObject: [
            "backendBaseURL": backend,
            "session": ["userID": "550e8400-e29b-41d4-a716-446655440001",
                        "teamPlayerID": playerID, "accessToken": "test-only-token",
                        "expiresAt": "2099-01-01T00:00:00Z"]
        ])
        return ["QUIZICE_DEBUG_SESSION_BASE64": data.base64EncodedString()]
    }
#endif
    func testDeletionReceiptHidesCredentialFromNormalRequestsButPreservesRetryCredential() throws {
        let defaults = UserDefaults(suiteName: "KeychainDeletionTests.\(UUID())")!
        let deletionState = AccountDeletionStateStore(defaults: defaults)
        let store = KeychainSessionStore(client: InMemoryKeychainClient(), deletionStateStore: deletionState)
        let session = AuthSession(userID: "delete-me", accessToken: "secret", expiresAt: .distantFuture, teamPlayerID: "player")
        try store.save(session)
        deletionState.save(.init(userID: session.userID, teamPlayerID: session.teamPlayerID,
                                 idempotencyKey: UUID().uuidString, serverConfirmed: false, cleanupCompleted: false))
        XCTAssertNil(try store.load())
        XCTAssertEqual(try store.loadForAccountDeletion(), session)
        try store.clear()
        XCTAssertNil(try store.loadForAccountDeletion())
    }

    func testRoundTripAndClear() throws {
        let client = InMemoryKeychainClient()
        let store = KeychainSessionStore(
            service: "QuiziceTests.Auth.\(UUID().uuidString)",
            client: client
        )
        let session = AuthSession(
            userID: "user-1",
            accessToken: "secret",
            expiresAt: Date(timeIntervalSince1970: 2_000),
            teamPlayerID: "team-1"
        )
        try store.save(session)
        XCTAssertEqual(try store.load(), session)
        try store.clear()
        XCTAssertNil(try store.load())
    }
}

final class InMemoryKeychainClient: KeychainClient {
    private var values: [String: Data] = [:]

    func loadData(service: String, account: String) throws -> Data? {
        values[service + "|" + account]
    }

    func saveData(_ data: Data, service: String, account: String) throws {
        values[service + "|" + account] = data
    }

    func deleteData(service: String, account: String) throws {
        values[service + "|" + account] = nil
    }
}
