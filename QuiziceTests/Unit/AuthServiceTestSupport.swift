import Foundation
import UIKit
import XCTest
@testable import Quizice

@MainActor
final class FakeGameCenterClient: GameCenterAuthenticating {
    private var stateChanged: ((GameCenterPlayerState) -> Void)?
    private(set) var startCount = 0
    private(set) var present: ((UIViewController) -> Void)?
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
        self.present = present
        startCount += 1
    }

    func fetchIdentity(bundleIdentifier: String) async throws -> GameCenterIdentity {
        if let identityError { throw identityError }
        return identity
    }

    func emit(_ state: GameCenterPlayerState) {
        stateChanged?(state)
    }

    func requestPresentation(_ viewController: UIViewController) {
        present?(viewController)
    }
}

final class FakeAuthAPI: AuthAPI {
    var deletionRequests: [(String, String)] = []
    var deletionHandler: (() async throws -> Void)?
    var recreationRequests = 0
    var authenticatedIdentities: [GameCenterIdentity] = []
    var authenticationErrors: [BackendAPIError] = []
    var authenticationHandler: ((GameCenterIdentity) async throws -> AuthSession)?
    var syncRequests: [StatisticsStore.SyncRequest] = []
    var syncAccessTokens: [String] = []
    var syncErrors: [BackendAPIError] = []
    var syncSummary: StatisticsSummary = .empty
    var sessionsByTeamPlayerID: [String: AuthSession] = [:]
    var syncHandler: ((StatisticsStore.SyncRequest, String) async throws -> StatisticsStore.SyncResponse)?

    func authenticate(identity: GameCenterIdentity) async throws -> AuthSession {
        authenticatedIdentities.append(identity)
        if let authenticationHandler { return try await authenticationHandler(identity) }
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

actor SuspendedAuthSessionResponse {
    private var continuation: CheckedContinuation<AuthSession, Error>?
    private let onSuspend: () -> Void

    init(onSuspend: @escaping () -> Void) {
        self.onSuspend = onSuspend
    }

    func wait() async throws -> AuthSession {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            onSuspend()
        }
    }

    func resume(with session: AuthSession) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: session)
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
    static var requestHandler: ((URLRequest) throws -> (URLResponse, Data))?
    static var hangingRequestHandler: ((URLRequest) -> Void)?
    static var stopHandler: (() -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let hangingRequestHandler = Self.hangingRequestHandler {
            hangingRequestHandler(request)
            return
        }
        do {
            let handler = try XCTUnwrap(Self.requestHandler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        Self.stopHandler?()
    }
}

final class AuthBackendMetricSpy: BackendRequestMetricRecording {
    private(set) var values: [BackendRequestMetric] = []

    func record(_ metric: BackendRequestMetric) {
        values.append(metric)
    }
}
