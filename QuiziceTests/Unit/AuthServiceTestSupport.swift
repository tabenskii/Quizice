import Foundation
import UIKit
import XCTest
@testable import Quizice

@MainActor
final class FakeGameCenterClient: GameCenterAuthenticating {
    private var stateChanged: ((GameCenterPlayerState) -> Void)?
    private(set) var startCount = 0
    var identityError: Error?
    var identity = GameCenterIdentity(
        teamPlayerId: "team-1",
        bundleId: "ru.avtabenskiy.Quizice",
        publicKeyUrl: "https://apple.example/key",
        signature: "signature",
        salt: "salt",
        timestamp: "123"
    )

    func start(
        present: @escaping (UIViewController) -> Void,
        stateChanged: @escaping (GameCenterPlayerState) -> Void
    ) {
        self.stateChanged = stateChanged
        startCount += 1
    }

    func fetchIdentity(bundleIdentifier: String) async throws -> GameCenterIdentity {
        if let identityError { throw identityError }
        return identity
    }

    func emit(_ state: GameCenterPlayerState) {
        stateChanged?(state)
    }
}

final class FakeAuthAPI: AuthAPI {
    var deletionRequests: [(String, String)] = []
    var deletionHandler: (() async throws -> Void)?
    var recreationRequests = 0
    var authenticatedIdentities: [GameCenterIdentity] = []
    var authenticationErrors: [BackendAPIError] = []
    var syncRequests: [StatisticsStore.SyncRequest] = []
    var syncAccessTokens: [String] = []
    var syncErrors: [BackendAPIError] = []
    var syncSummary: StatisticsSummary = .empty
    var sessionsByTeamPlayerID: [String: AuthSession] = [:]
    var syncHandler: ((StatisticsStore.SyncRequest, String) async throws -> StatisticsStore.SyncResponse)?

    func authenticate(identity: GameCenterIdentity) async throws -> AuthSession {
        authenticatedIdentities.append(identity)
        if authenticationErrors.isEmpty == false {
            throw authenticationErrors.removeFirst()
        }
        if let session = sessionsByTeamPlayerID[identity.teamPlayerId] { return session }
        return AuthSession(
            userID: "user-1",
            accessToken: "access-token",
            expiresAt: Date(timeIntervalSince1970: 4_000_000_000),
            teamPlayerID: identity.teamPlayerId
        )
    }

    func authenticate(identity: GameCenterIdentity, recreateDeletedAccount: Bool) async throws -> AuthSession {
        if recreateDeletedAccount { recreationRequests += 1 }
        return try await authenticate(identity: identity)
    }

    func deleteAccount(accessToken: String, idempotencyKey: String) async throws {
        deletionRequests.append((accessToken, idempotencyKey))
        try await deletionHandler?()
    }

    func syncStatistics(
        request: StatisticsStore.SyncRequest,
        accessToken: String
    ) async throws -> StatisticsStore.SyncResponse {
        syncRequests.append(request)
        syncAccessTokens.append(accessToken)
        if let syncHandler { return try await syncHandler(request, accessToken) }
        if syncErrors.isEmpty == false {
            throw syncErrors.removeFirst()
        }
        return StatisticsStore.SyncResponse(
            summary: syncSummary,
            acceptedAttemptIds: request.attempts.map(\.id),
            legacySummaryAccepted: true
        )
    }
}

/// Deliberately ignores cancellation to model a response already delivered by
/// the transport when Game Center switches accounts.
actor SuspendedAuthStatisticsResponse {
    private var continuation: CheckedContinuation<StatisticsStore.SyncResponse, Error>?
    private let onSuspend: () -> Void

    init(onSuspend: @escaping () -> Void) {
        self.onSuspend = onSuspend
    }

    func wait() async throws -> StatisticsStore.SyncResponse {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            onSuspend()
        }
    }

    func resume(with result: Result<StatisticsStore.SyncResponse, Error>) {
        let pending = continuation
        continuation = nil
        pending?.resume(with: result)
    }
}

final class MemorySessionStore: SessionStoring {
    var session: AuthSession?

    init(session: AuthSession? = nil) {
        self.session = session
    }

    func load() throws -> AuthSession? { session }
    func save(_ session: AuthSession) throws { self.session = session }
    func clear() throws { session = nil }
}

final class AuthURLProtocol: URLProtocol {
    private struct Handlers {
        var request: ((URLRequest) throws -> (URLResponse, Data))?
        var hangingRequest: ((URLRequest) -> Void)?
        var stop: (() -> Void)?
    }

    private static let handlersLock = NSLock()
    private static var handlers = Handlers()
    private let stopLock = NSLock()
    private var requestStopHandler: (() -> Void)?

    static var requestHandler: ((URLRequest) throws -> (URLResponse, Data))? {
        get { handlersLock.withLock { handlers.request } }
        set { handlersLock.withLock { handlers.request = newValue } }
    }

    static var hangingRequestHandler: ((URLRequest) -> Void)? {
        get { handlersLock.withLock { handlers.hangingRequest } }
        set { handlersLock.withLock { handlers.hangingRequest = newValue } }
    }

    static var stopHandler: (() -> Void)? {
        get { handlersLock.withLock { handlers.stop } }
        set { handlersLock.withLock { handlers.stop = newValue } }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let handlers = Self.handlersLock.withLock { Self.handlers }
        if let hangingRequestHandler = handlers.hangingRequest {
            // A late stop must notify this request's observer, never the next test's.
            stopLock.withLock { requestStopHandler = handlers.stop }
            hangingRequestHandler(request)
            return
        }
        do {
            let handler = try XCTUnwrap(handlers.request)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        let handler = stopLock.withLock {
            let handler = requestStopHandler
            requestStopHandler = nil
            return handler
        }
        handler?()
    }
}

final class AuthBackendMetricSpy: BackendRequestMetricRecording {
    private(set) var values: [BackendRequestMetric] = []

    func record(_ metric: BackendRequestMetric) {
        values.append(metric)
    }
}

final class AuthURLProtocolTests: XCTestCase {
    override func tearDown() {
        AuthURLProtocol.requestHandler = nil
        AuthURLProtocol.hangingRequestHandler = nil
        AuthURLProtocol.stopHandler = nil
        super.tearDown()
    }

    func testLateStopOfCompletedRequestDoesNotNotifyLaterHangingRequest() {
        AuthURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        }
        let completedRequest = makeProtocol()
        completedRequest.startLoading()

        var stops = 0
        AuthURLProtocol.hangingRequestHandler = { _ in }
        AuthURLProtocol.stopHandler = { stops += 1 }
        let hangingRequest = makeProtocol()
        hangingRequest.startLoading()

        completedRequest.stopLoading()
        XCTAssertEqual(stops, 0, "An earlier request must not consume the current cancellation expectation")
        hangingRequest.stopLoading()
        XCTAssertEqual(stops, 1)
        completedRequest.stopLoading()
        XCTAssertEqual(stops, 1)
    }

    func testStopUsesOriginalRequestObserverExactlyOnceAfterConfigurationChanges() {
        var firstStops = 0
        var secondStops = 0
        AuthURLProtocol.hangingRequestHandler = { _ in }
        AuthURLProtocol.stopHandler = { firstStops += 1 }
        let firstRequest = makeProtocol()
        firstRequest.startLoading()

        AuthURLProtocol.stopHandler = { secondStops += 1 }
        let secondRequest = makeProtocol()
        secondRequest.startLoading()
        firstRequest.stopLoading()
        firstRequest.stopLoading()
        XCTAssertEqual(firstStops, 1)
        XCTAssertEqual(secondStops, 0, "A delayed stop must retain its original owner")

        secondRequest.stopLoading()
        secondRequest.stopLoading()
        XCTAssertEqual(secondStops, 1)
    }

    private func makeProtocol() -> AuthURLProtocol {
        AuthURLProtocol(
            request: URLRequest(url: URL(string: "https://example.test/auth")!),
            cachedResponse: nil,
            client: nil
        )
    }
}
