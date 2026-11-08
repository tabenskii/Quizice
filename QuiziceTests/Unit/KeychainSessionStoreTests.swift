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
