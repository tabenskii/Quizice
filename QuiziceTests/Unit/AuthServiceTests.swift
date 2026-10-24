import XCTest
import UIKit
@testable import Quizice
@MainActor
final class GameCenterAuthenticationServiceTests: XCTestCase {
    func testInitialAuthenticationWaitsForBackendAndResolvesOnlyOnce() async {
        let harness = makeHarness()
        let backendStarted = expectation(description: "Backend authentication started")
        let gate = SuspendedAuthSessionResponse { backendStarted.fulfill() }
        harness.api.authenticationHandler = { _ in try await gate.wait() }
        harness.service.start { _ in }
        let finishedWaiting = expectation(description: "Startup waiter finished")
        var waiterFinished = false
        let waiter = Task {
            await harness.service.waitForInitialAuthentication()
            XCTAssertEqual(harness.service.state, .authenticated(userID: "user-1", teamPlayerID: "team-1"))
            XCTAssertEqual(harness.sessionStore.session?.userID, "user-1")
            XCTAssertEqual(harness.statistics.activeUserID, "user-1")
            XCTAssertTrue(harness.aiAccess.isAIQuizAvailable)
            waiterFinished = true
            finishedWaiting.fulfill()
        }
        defer { waiter.cancel() }

        harness.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))
        await fulfillment(of: [backendStarted], timeout: 1)
        XCTAssertEqual(harness.service.state, .authenticating)
        XCTAssertFalse(waiterFinished)

        await gate.resume(with: startupSession)
        await fulfillment(of: [finishedWaiting], timeout: 1)
        harness.service.start { _ in }
        harness.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))
        harness.gameCenter.emit(.unavailable)
        XCTAssertEqual(harness.gameCenter.startCount, 1)

        let refreshStarted = expectation(description: "Later authentication started")
        let refreshGate = SuspendedAuthSessionResponse { refreshStarted.fulfill() }
        harness.api.authenticationHandler = { _ in try await refreshGate.wait() }
        harness.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))
        await fulfillment(of: [refreshStarted], timeout: 1)
        XCTAssertEqual(harness.service.state, .authenticating)
        let alreadyResolved = expectation(description: "Initial authentication remains resolved during refresh")
        let laterWaiter = Task {
            await harness.service.waitForInitialAuthentication()
            alreadyResolved.fulfill()
        }
        defer { laterWaiter.cancel() }
        await fulfillment(of: [alreadyResolved], timeout: 1)
        await refreshGate.resume(with: startupSession)
    }

    func testInitialAuthenticationRestoresCachedSessionBeforeReleasingWaiter() async {
        let harness = makeHarness(storedSession: startupSession)
        let finishedWaiting = expectation(description: "Cached authentication resolved")
        let waiter = Task {
            await harness.service.waitForInitialAuthentication()
            XCTAssertEqual(harness.service.state, .authenticated(userID: "user-1", teamPlayerID: "team-1"))
            finishedWaiting.fulfill()
        }
        defer { waiter.cancel() }
        harness.service.start { _ in }
        harness.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))

        await fulfillment(of: [finishedWaiting], timeout: 1)
        XCTAssertTrue(harness.api.authenticatedIdentities.isEmpty)
    }

    func testInitialAuthenticationResolvesGuestWhenGameCenterIsUnavailable() async {
        let harness = makeHarness()
        harness.service.start { _ in }
        let finishedWaiting = expectation(description: "Guest startup resolved")
        let waiter = Task {
            await harness.service.waitForInitialAuthentication()
            finishedWaiting.fulfill()
        }
        defer { waiter.cancel() }

        harness.gameCenter.emit(.unavailable)
        await fulfillment(of: [finishedWaiting], timeout: 1)
        XCTAssertEqual(harness.service.state, .guest)
        XCTAssertFalse(harness.aiAccess.isAIQuizAvailable)
    }

    func testInitialAuthenticationFailureReleasesWaiterInGuestMode() async {
        let harness = makeHarness()
        harness.api.authenticationErrors = [.transport(.notConnectedToInternet)]
        harness.service.start { _ in }
        let finishedWaiting = expectation(description: "Failed startup resolved")
        let waiter = Task {
            await harness.service.waitForInitialAuthentication()
            finishedWaiting.fulfill()
        }
        defer { waiter.cancel() }
        harness.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))

        await fulfillment(of: [finishedWaiting], timeout: 1)
        XCTAssertEqual(harness.service.state, .guest)
        XCTAssertNil(harness.sessionStore.session)
    }

    func testGameCenterPresentationDoesNotResolveInitialAuthentication() async {
        let harness = makeHarness()
        let controller = UIViewController()
        var presentedController: UIViewController?
        harness.service.start {
            presentedController = $0
        }
        let finishedWaiting = expectation(description: "Game Center completed after presentation")
        var waiterFinished = false
        let waiter = Task {
            await harness.service.waitForInitialAuthentication()
            waiterFinished = true
            finishedWaiting.fulfill()
        }
        defer { waiter.cancel() }

        harness.gameCenter.requestPresentation(controller)
        XCTAssertTrue(presentedController === controller)
        XCTAssertEqual(harness.service.state, .initializing)
        await Task.yield()
        XCTAssertFalse(waiterFinished)

        harness.gameCenter.emit(.unavailable)
        await fulfillment(of: [finishedWaiting], timeout: 1)
    }

    func testCancellingStartupWaiterLeavesOtherWaitersAndBackendAuthenticationRunning() async {
        let harness = makeHarness()
        let backendStarted = expectation(description: "Backend authentication suspended")
        let gate = SuspendedAuthSessionResponse { backendStarted.fulfill() }
        harness.api.authenticationHandler = { _ in
            let session = try await gate.wait()
            try Task.checkCancellation()
            return session
        }
        harness.service.start { _ in }
        let cancelledWaiterFinished = expectation(description: "Cancelled waiter finished")
        let cancelledWaiter = Task {
            await harness.service.waitForInitialAuthentication()
            cancelledWaiterFinished.fulfill()
        }
        let activeWaiterFinished = expectation(description: "Active waiter finished after authentication")
        var activeWaiterDidFinish = false
        let activeWaiter = Task {
            await harness.service.waitForInitialAuthentication()
            activeWaiterDidFinish = true
            activeWaiterFinished.fulfill()
        }
        defer { activeWaiter.cancel() }
        harness.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))
        await fulfillment(of: [backendStarted], timeout: 1)

        cancelledWaiter.cancel()
        await fulfillment(of: [cancelledWaiterFinished], timeout: 1)
        XCTAssertFalse(activeWaiterDidFinish)
        XCTAssertEqual(harness.service.state, .authenticating)

        await gate.resume(with: startupSession)
        await fulfillment(of: [activeWaiterFinished], timeout: 1)
        XCTAssertEqual(harness.service.state, .authenticated(userID: "user-1", teamPlayerID: "team-1"))
        XCTAssertEqual(harness.sessionStore.session, startupSession)
        XCTAssertEqual(harness.api.authenticatedIdentities.count, 1)
    }

    func testPendingDeletionResolvesInitialAuthenticationWithoutWaitingForGameCenter() async {
        let harness = makeHarness(pendingDeletion: true)
        harness.service.start { _ in }
        let finishedWaiting = expectation(description: "Pending deletion startup resolved")
        let waiter = Task {
            await harness.service.waitForInitialAuthentication()
            finishedWaiting.fulfill()
        }
        defer { waiter.cancel() }

        await fulfillment(of: [finishedWaiting], timeout: 1)
        XCTAssertEqual(harness.service.state, .deletionPending)
        XCTAssertEqual(harness.gameCenter.startCount, 1)
        XCTAssertTrue(harness.api.authenticatedIdentities.isEmpty)
    }

    func testAccountAccessObserverReplaysStateAndRequiresSignInAfterGameCenterCancellation() async {
        let h = makeHarness()
        var accessStates: [AppAccountAccessState] = []
        h.service.accountAccessStateDidChange = { accessStates.append($0) }
        XCTAssertEqual(accessStates, [.loading])

        h.service.start { _ in }
        h.gameCenter.emit(.unavailable)
        XCTAssertEqual(h.service.accountAccessState, .signInRequired)
        XCTAssertEqual(accessStates.last, .signInRequired)
        XCTAssertTrue(h.api.authenticatedIdentities.isEmpty)

        h.service.signIn { _ in }
        h.service.signIn { _ in }
        XCTAssertEqual(h.gameCenter.startCount, 2)
        XCTAssertEqual(h.service.accountAccessState, .loading)
        h.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))
        await waitUntil { h.service.accountAccessState == .authenticated }
        XCTAssertEqual(accessStates.last, .authenticated)
        XCTAssertEqual(h.service.authenticatedAccountID, "user-1")
    }

    func testBackendAuthenticationFailureKeepsAccessBlockedUntilSignInSucceeds() async {
        let h = makeHarness()
        h.api.authenticationErrors = [.transport(.notConnectedToInternet)]
        h.service.start { _ in }
        h.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))
        await waitUntil { h.service.accountAccessState == .signInRequired }
        XCTAssertNil(h.sessionStore.session)

        h.service.signIn { _ in }
        h.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))
        await waitUntil { h.service.accountAccessState == .authenticated }
        XCTAssertEqual(h.api.authenticatedIdentities.count, 2)
        XCTAssertEqual(h.gameCenter.startCount, 2)
    }

    func testValidCachedSessionKeepsAppAccessDuringOfflineStatisticsSync() async {
        let cached = AuthSession(userID: "cached-user", accessToken: "cached-token",
                                 expiresAt: .distantFuture, teamPlayerID: "team-1")
        let h = makeHarness(storedSession: cached)
        h.api.syncErrors = [.transport(.notConnectedToInternet)]
        h.service.start { _ in }
        h.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))
        await waitUntil { h.api.syncRequests.count == 1 }
        XCTAssertEqual(h.service.accountAccessState, .authenticated)
        XCTAssertTrue(h.api.authenticatedIdentities.isEmpty)
        XCTAssertEqual(h.sessionStore.session, cached)
    }

    func testSuccessfulAuthenticationMergesGuestAttemptAndSynchronizesIt() async {
        let harness = makeHarness()
        var authenticationEstablishedCount = 0
        let observer = harness.notificationCenter.addObserver(
            forName: .backendAuthenticationEstablished,
            object: nil,
            queue: nil
        ) { _ in
            authenticationEstablishedCount += 1
        }
        defer { harness.notificationCenter.removeObserver(observer) }
        harness.statistics.recordAttempt(correctAnswers: 4, totalQuestions: 5)
        harness.api.syncSummary = StatisticsSummary(
            playedQuizzes: 1,
            correctAnswers: 4,
            totalQuestions: 5,
            bestCorrectAnswers: 4,
            bestTotalQuestions: 5
        )

        harness.service.start { _ in }
        harness.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))

        await waitUntil { harness.api.syncRequests.count == 1 }

        XCTAssertEqual(
            harness.service.state,
            .authenticated(userID: "user-1", teamPlayerID: "team-1")
        )
        XCTAssertEqual(harness.api.authenticatedIdentities.count, 1)
        XCTAssertEqual(harness.api.syncRequests.first?.attempts.count, 1)
        XCTAssertEqual(harness.statistics.loadSummary(), harness.api.syncSummary)
        XCTAssertTrue(harness.aiAccess.isAIQuizAvailable)
        XCTAssertEqual(authenticationEstablishedCount, 1)
    }

    func testUnavailableGameCenterEntersGuestMode() async {
        let harness = makeHarness()

        harness.service.start { _ in }
        harness.gameCenter.emit(.unavailable)

        await waitUntil { harness.service.state == .guest }
        XCTAssertTrue(harness.api.authenticatedIdentities.isEmpty)
        XCTAssertFalse(harness.aiAccess.isAIQuizAvailable)
    }

    func testValidCachedSessionIsUsedOnlyForMatchingPlayer() async {
        let cached = AuthSession(
            userID: "cached-user",
            accessToken: "cached-token",
            expiresAt: Date(timeIntervalSince1970: 4_000_000_000),
            teamPlayerID: "team-1"
        )
        let harness = makeHarness(storedSession: cached)

        harness.service.start { _ in }
        harness.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))

        await waitUntil {
            harness.service.state == .authenticated(userID: "cached-user", teamPlayerID: "team-1")
        }
        XCTAssertTrue(harness.api.authenticatedIdentities.isEmpty)
    }

    func testCachedSessionForDifferentPlayerIsReplaced() async {
        let cached = AuthSession(
            userID: "old-user",
            accessToken: "old-token",
            expiresAt: Date(timeIntervalSince1970: 4_000_000_000),
            teamPlayerID: "old-team"
        )
        let harness = makeHarness(storedSession: cached)

        harness.service.start { _ in }
        harness.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))

        await waitUntil { harness.api.authenticatedIdentities.count == 1 }
        XCTAssertEqual(harness.sessionStore.session?.teamPlayerID, "team-1")
        XCTAssertEqual(harness.sessionStore.session?.userID, "user-1")
    }

    func testUnauthorizedStatisticsRequestRefreshesAndRetriesOnlyOnce() async {
        let cached = AuthSession(
            userID: "user-1",
            accessToken: "expired-server-token",
            expiresAt: Date(timeIntervalSince1970: 4_000_000_000),
            teamPlayerID: "team-1"
        )
        let harness = makeHarness(storedSession: cached)
        harness.api.syncErrors = [.unauthorized(nil)]

        harness.service.start { _ in }
        harness.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))

        await waitUntil { harness.api.syncRequests.count == 2 }
        XCTAssertEqual(harness.api.authenticatedIdentities.count, 1)
        XCTAssertEqual(harness.api.syncAccessTokens, ["expired-server-token", "access-token"])
    }

    func testSecondUnauthorizedResponseStopsRetryAndEntersGuestMode() async {
        let cached = AuthSession(
            userID: "user-1",
            accessToken: "expired-server-token",
            expiresAt: Date(timeIntervalSince1970: 4_000_000_000),
            teamPlayerID: "team-1"
        )
        let harness = makeHarness(storedSession: cached)
        harness.api.syncErrors = [.unauthorized(nil), .unauthorized(nil)]

        harness.service.start { _ in }
        harness.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))

        await waitUntil { harness.service.state == .guest }
        XCTAssertEqual(harness.api.syncRequests.count, 2)
        XCTAssertNil(harness.sessionStore.session)
        XCTAssertFalse(harness.aiAccess.isAIQuizAvailable)
    }

    func testRepeatedAuthenticatedCallbackDoesNotExchangeAgain() async {
        let harness = makeHarness()
        harness.service.start { _ in }

        harness.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))
        await waitUntil { harness.api.authenticatedIdentities.count == 1 }
        harness.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(harness.api.authenticatedIdentities.count, 1)
    }

    func testBackendAuthenticationInvalidationCoalescesAndRefreshesSession() async {
        let harness = makeHarness()
        harness.service.start { _ in }
        harness.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))
        await waitUntil {
            harness.service.state == .authenticated(userID: "user-1", teamPlayerID: "team-1")
        }

        harness.sessionStore.session = nil
        harness.aiAccess.update(isAuthenticated: false)
        harness.notificationCenter.post(name: .backendAuthenticationInvalidated, object: nil)
        harness.notificationCenter.post(name: .backendAuthenticationInvalidated, object: nil)

        await waitUntil {
            harness.api.authenticatedIdentities.count == 2 &&
                harness.service.state == .authenticated(userID: "user-1", teamPlayerID: "team-1")
        }
        XCTAssertEqual(harness.api.authenticatedIdentities.count, 2)
        XCTAssertTrue(harness.aiAccess.isAIQuizAvailable)
        XCTAssertEqual(harness.sessionStore.session?.accessToken, "access-token")
    }

    func testBackendAuthenticationRefreshFailureEntersGuestMode() async {
        let harness = makeHarness()
        harness.service.start { _ in }
        harness.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))
        await waitUntil {
            harness.service.state == .authenticated(userID: "user-1", teamPlayerID: "team-1")
        }

        harness.api.authenticationErrors = [.transport(.notConnectedToInternet)]
        harness.sessionStore.session = nil
        harness.aiAccess.update(isAuthenticated: false)
        harness.notificationCenter.post(name: .backendAuthenticationInvalidated, object: nil)

        await waitUntil { harness.service.state == .guest }
        XCTAssertFalse(harness.aiAccess.isAIQuizAvailable)
        XCTAssertNil(harness.sessionStore.session)
    }

    func testTransientRefreshFailureRetriesOnceOnForegroundAndRestoresAuthenticatedAccess() async {
        let harness = makeHarness()
        harness.service.start { _ in }
        harness.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))
        await waitUntil {
            harness.service.state == .authenticated(userID: "user-1", teamPlayerID: "team-1")
        }

        harness.api.authenticationErrors = [.transport(.notConnectedToInternet)]
        harness.notificationCenter.post(name: .backendAuthenticationInvalidated, object: nil)

        await waitUntil { harness.service.state == .guest }
        XCTAssertEqual(harness.api.authenticatedIdentities.count, 2)
        XCTAssertFalse(harness.aiAccess.isAIQuizAvailable)
        XCTAssertNil(harness.sessionStore.session)

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(harness.api.authenticatedIdentities.count, 2)

        harness.service.retrySynchronization()
        harness.service.retrySynchronization()

        await waitUntil {
            harness.api.authenticatedIdentities.count == 3 &&
                harness.service.state == .authenticated(userID: "user-1", teamPlayerID: "team-1")
        }
        XCTAssertEqual(harness.api.authenticatedIdentities.count, 3)
        XCTAssertTrue(harness.aiAccess.isAIQuizAvailable)
        XCTAssertEqual(harness.sessionStore.session?.teamPlayerID, "team-1")
    }

    func testSynchronizationDrainsOneHundredAndOneAttemptsInTwoBatches() async {
        let harness = makeHarness()
        for index in 0..<101 {
            harness.statistics.recordAttempt(
                correctAnswers: index % 5,
                totalQuestions: 5
            )
        }

        harness.service.start { _ in }
        harness.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))

        await waitUntil(timeout: 2) {
            harness.api.syncRequests.count == 2 &&
                harness.statistics.hasPendingSync(for: "user-1") == false
        }

        XCTAssertEqual(harness.api.syncRequests.map(\.attempts.count), [100, 1])
        XCTAssertEqual(
            Set(harness.api.syncRequests.flatMap { $0.attempts.map(\.id) }).count,
            101
        )
    }

    func testLateSuccessfulStatisticsResponseFromPreviousAccountIsIgnored() async {
        await assertLateStatisticsResponseIsIgnored(unauthorized: false)
    }

    func testLateUnauthorizedStatisticsResponseDoesNotRefreshTheNewAccount() async {
        await assertLateStatisticsResponseIsIgnored(unauthorized: true)
    }

    private func assertLateStatisticsResponseIsIgnored(unauthorized: Bool) async {
        let previousSession = AuthSession(
            userID: "user-1", accessToken: "previous-token",
            expiresAt: Date(timeIntervalSince1970: 4_000_000_000), teamPlayerID: "team-1"
        )
        let newSession = AuthSession(
            userID: "user-2", accessToken: "new-token",
            expiresAt: Date(timeIntervalSince1970: 4_000_000_000), teamPlayerID: "team-2"
        )
        let harness = makeHarness(storedSession: previousSession)
        harness.api.sessionsByTeamPlayerID["team-2"] = newSession
        harness.statistics.recordAttempt(
            correctAnswers: 4, totalQuestions: 5, accessibilityMode: false, for: "user-1"
        )
        harness.statistics.recordAttempt(
            correctAnswers: 2, totalQuestions: 5, accessibilityMode: false, for: "user-2"
        )
        let previousRequest = harness.statistics.makeSyncRequest(for: "user-1")
        let previousSummary = StatisticsSummary(
            playedQuizzes: 1, correctAnswers: 4, totalQuestions: 5,
            bestCorrectAnswers: 4, bestTotalQuestions: 5
        )
        let newSummary = StatisticsSummary(
            playedQuizzes: 1, correctAnswers: 2, totalQuestions: 5,
            bestCorrectAnswers: 2, bestTotalQuestions: 5
        )
        let suspended = expectation(description: "Previous account sync is in flight")
        let gate = SuspendedAuthStatisticsResponse { suspended.fulfill() }
        harness.api.syncHandler = { request, token in
            if token == previousSession.accessToken { return try await gate.wait() }
            return StatisticsStore.SyncResponse(
                summary: newSummary,
                acceptedAttemptIds: request.attempts.map(\.id),
                legacySummaryAccepted: false
            )
        }

        harness.service.start { _ in }
        harness.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))
        await fulfillment(of: [suspended], timeout: 1)

        harness.gameCenter.identity = GameCenterIdentity(
            teamPlayerId: "team-2", bundleId: "ru.avtabenskiy.Quizice",
            publicKeyUrl: "https://apple.example/key", signature: "signature",
            salt: "salt", timestamp: "123"
        )
        harness.gameCenter.emit(.authenticated(teamPlayerID: "team-2"))
        await waitUntil {
            harness.service.state == .authenticated(userID: "user-2", teamPlayerID: "team-2")
                && !harness.statistics.hasPendingSync(for: "user-2")
        }

        if unauthorized {
            await gate.resume(with: .failure(BackendAPIError.unauthorized(nil)))
        } else {
            await gate.resume(with: .success(StatisticsStore.SyncResponse(
                summary: previousSummary,
                acceptedAttemptIds: previousRequest.attempts.map(\.id),
                legacySummaryAccepted: false
            )))
        }
        // Allow the cancelled task to deliver its late value or error on MainActor.
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(harness.service.state, .authenticated(userID: "user-2", teamPlayerID: "team-2"))
        XCTAssertEqual(harness.sessionStore.session, newSession)
        XCTAssertEqual(harness.statistics.activeUserID, "user-2")
        XCTAssertEqual(harness.statistics.loadSummary(), newSummary)
        XCTAssertEqual(harness.statistics.makeSyncRequest(for: "user-1"), previousRequest)
        XCTAssertEqual(harness.api.authenticatedIdentities.map(\.teamPlayerId), ["team-2"])
        XCTAssertEqual(harness.api.syncAccessTokens, ["previous-token", "new-token"])
        XCTAssertTrue(harness.aiAccess.isAIQuizAvailable)
    }

    private var startupSession: AuthSession {
        AuthSession(
            userID: "user-1", accessToken: "access-token",
            expiresAt: Date(timeIntervalSince1970: 4_000_000_000), teamPlayerID: "team-1"
        )
    }

    private func makeHarness(storedSession: AuthSession? = nil, pendingDeletion: Bool = false) -> (
        service: GameCenterAuthenticationService,
        gameCenter: FakeGameCenterClient,
        api: FakeAuthAPI,
        sessionStore: MemorySessionStore,
        statistics: StatisticsStore,
        notificationCenter: NotificationCenter,
        aiAccess: AIQuizAccessStore
    ) {
        let suiteName = "GameCenterAuthenticationServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let notificationCenter = NotificationCenter()
        let statistics = StatisticsStore(
            userDefaults: defaults,
            key: "attempts",
            notificationCenter: notificationCenter
        )
        let gameCenter = FakeGameCenterClient()
        let api = FakeAuthAPI()
        let sessionStore = MemorySessionStore(session: storedSession)
        let aiAccess = AIQuizAccessStore()
        let deletionStateStore = AccountDeletionStateStore(defaults: defaults)
        if pendingDeletion {
            deletionStateStore.save(.init(
                userID: "user-1", teamPlayerID: "team-1", idempotencyKey: "pending-deletion",
                serverConfirmed: false, cleanupCompleted: false
            ))
        }
        let service = GameCenterAuthenticationService(
            gameCenter: gameCenter,
            api: api,
            sessionStore: sessionStore,
            statisticsStore: statistics,
            bundleIdentifier: "ru.avtabenskiy.Quizice",
            now: { Date(timeIntervalSince1970: 1_000) },
            notificationCenter: notificationCenter,
            aiQuizAccessStore: aiAccess,
            deletionStateStore: deletionStateStore
        )
        return (
            service,
            gameCenter,
            api,
            sessionStore,
            statistics,
            notificationCenter,
            aiAccess
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ predicate: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while predicate() == false, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(predicate(), "Condition was not met before timeout", file: file, line: line)
    }
}

final class HTTPAuthAPITests: XCTestCase {
    override func tearDown() {
        AuthURLProtocol.requestHandler = nil
        AuthURLProtocol.hangingRequestHandler = nil
        AuthURLProtocol.stopHandler = nil
        super.tearDown()
    }

    func testLiveCamelCaseContractEncodesRequestsAndDecodesResponses() async throws {
        let metrics = AuthBackendMetricSpy()
        let api = makeAPI(metrics: metrics)
        var requestNumber = 0
        AuthURLProtocol.requestHandler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            requestNumber += 1
            if requestNumber == 1 {
                XCTAssertEqual(request.url?.path, "/api/v1/auth/game-center")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
                let body = try XCTUnwrap(Self.bodyData(from: request))
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
                XCTAssertEqual(
                    json,
                    [
                        "teamPlayerId": "team-1",
                        "bundleId": "ru.avtabenskiy.Quizice",
                        "publicKeyUrl": "https://apple.example/key",
                        "signature": "c2lnbmF0dXJl",
                        "salt": "c2FsdA==",
                        "timestamp": "123456"
                    ]
                )
                let data = Data(
                    #"{"userId":"018f4f5e-7b6a-7c8d-9e0f-123456789abc","accessToken":"token","expiresAt":"2030-01-01T00:00:00Z"}"#.utf8
                )
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }

            XCTAssertEqual(request.url?.path, "/api/v1/me/statistics/sync")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Quizice-Authorization"), "Bearer token")
            let body = try XCTUnwrap(Self.bodyData(from: request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(Set(json.keys), ["migrationId", "legacySummary", "attempts"])
            XCTAssertEqual(json["migrationId"] as? String, "migration-1")
            XCTAssertEqual(
                json["legacySummary"] as? [String: Int],
                [
                    "playedQuizzes": 1,
                    "correctAnswers": 4,
                    "totalQuestions": 5,
                    "bestCorrectAnswers": 4,
                    "bestTotalQuestions": 5
                ]
            )
            let attempts = try XCTUnwrap(json["attempts"] as? [[String: Any]])
            XCTAssertEqual(attempts.count, 1)
            XCTAssertEqual(attempts[0] as NSDictionary, [
                "id": "attempt-1", "correctAnswers": 3, "totalQuestions": 5,
                "completedAt": "1970-01-01T00:20:34Z", "accessibilityMode": false
            ] as NSDictionary)
            let data = Data(
                #"{"summary":{"playedQuizzes":2,"correctAnswers":7,"totalQuestions":10,"bestCorrectAnswers":4,"bestTotalQuestions":5},"acceptedAttemptIds":["attempt-1"],"legacySummaryAccepted":true}"#.utf8
            )
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let authSession = try await api.authenticate(identity: Self.identity)
        XCTAssertEqual(authSession.teamPlayerID, "team-1")
        XCTAssertEqual(authSession.userID, "018f4f5e-7b6a-7c8d-9e0f-123456789abc")

        let response = try await api.syncStatistics(
            request: StatisticsStore.SyncRequest(
                migrationId: "migration-1",
                legacySummary: StatisticsSummary(
                    playedQuizzes: 1,
                    correctAnswers: 4,
                    totalQuestions: 5,
                    bestCorrectAnswers: 4,
                    bestTotalQuestions: 5
                ),
                attempts: [
                    StatisticsStore.PendingAttempt(
                        id: "attempt-1",
                        correctAnswers: 3,
                        totalQuestions: 5,
                        completedAt: Date(timeIntervalSince1970: 1_234)
                    )
                ]
            ),
            accessToken: authSession.accessToken
        )
        XCTAssertEqual(response.summary.playedQuizzes, 2)
        XCTAssertEqual(response.acceptedAttemptIds, ["attempt-1"])
        XCTAssertEqual(metrics.values.map(\.operation), [.authentication, .statisticsSync])
        XCTAssertEqual(metrics.values.map(\.result), [.success, .success])
        XCTAssertTrue(metrics.values.allSatisfy { $0.statusCode == 200 })
        XCTAssertTrue(metrics.values.allSatisfy { $0.durationMilliseconds >= 0 })
    }

#if DEBUG
    func testDeveloperAuthenticationUsesDevEndpointUUIDBodyAndSecretHeader() async throws {
        let developerUserID = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!
        let api = makeAPI()
        AuthURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/auth/dev")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Dev-Auth-Secret"), "local-secret")
            let body = try XCTUnwrap(Self.bodyData(from: request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
            XCTAssertEqual(json, ["developerUserId": developerUserID.uuidString])
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(
                    #"{"userId":"018f4f5e-7b6a-7c8d-9e0f-123456789abc","accessToken":"dev-token","expiresAt":"2030-01-01T00:00:00Z"}"#.utf8
                )
            )
        }

        let session = try await api.authenticate(
            developerUserID: developerUserID,
            secret: "local-secret"
        )

        XCTAssertEqual(session.accessToken, "dev-token")
        XCTAssertEqual(session.teamPlayerID, "dev:\(developerUserID.uuidString.lowercased())")
    }
#endif

    func testAuthenticationDecodesRFC3339ExpirationWithAndWithoutFractionalSeconds() async throws {
        let fixtures: [(value: String, expectedTimestamp: TimeInterval)] = [
            ("2030-01-01T00:00:00Z", 1_893_456_000),
            ("2030-01-01T00:00:00.123Z", 1_893_456_000.123)
        ]

        for fixture in fixtures {
            let api = makeAPI()
            AuthURLProtocol.requestHandler = { request in
                let data = Data(
                    #"{"userId":"user-1","accessToken":"token","expiresAt":"\#(fixture.value)"}"#.utf8
                )
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    data
                )
            }

            let session = try await api.authenticate(identity: Self.identity)

            XCTAssertEqual(
                session.expiresAt.timeIntervalSince1970,
                fixture.expectedTimestamp,
                accuracy: 0.001
            )
        }
    }

    func testUnauthorizedResponseDecodesLiveErrorEnvelopeIncludingRequestID() async {
        let api = makeAPI()
        AuthURLProtocol.requestHandler = { request in
            let data = Data(
                #"{"requestId":"request-42","code":"unauthorized","message":"invalid token"}"#.utf8
            )
            return (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, data)
        }

        do {
            _ = try await api.syncStatistics(request: Self.emptySyncRequest, accessToken: "expired")
            XCTFail("Expected unauthorized error")
        } catch let error as BackendAPIError {
            XCTAssertEqual(
                error,
                .unauthorized(
                    BackendErrorEnvelope(
                        code: "unauthorized",
                        message: "invalid token",
                        requestId: "request-42"
                    )
                )
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMalformedSuccessJSONThrowsDecodingError() async {
        let api = makeAPI()
        AuthURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"userId":"user-1"}"#.utf8)
            )
        }

        await assertError(.decoding) {
            try await api.authenticate(identity: Self.identity)
        }
    }

    func testNonHTTPResponseThrowsInvalidResponse() async {
        let api = makeAPI()
        AuthURLProtocol.requestHandler = { request in
            (
                URLResponse(
                    url: request.url!,
                    mimeType: "application/json",
                    expectedContentLength: 0,
                    textEncodingName: nil
                ),
                Data()
            )
        }

        await assertError(.invalidResponse) {
            try await api.authenticate(identity: Self.identity)
        }
    }

    func testTimeoutIsInjectedIntoRequestAndMappedToTransportError() async {
        let api = makeAPI(requestTimeout: 0.25)
        AuthURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.timeoutInterval, 0.25, accuracy: 0.001)
            throw URLError(.timedOut)
        }

        await assertError(.transport(.timedOut)) {
            try await api.authenticate(identity: Self.identity)
        }
    }

    func testCancellingRequestPropagatesCancellationError() async {
        let api = makeAPI()
        let requestStarted = expectation(description: "Request started")
        let requestStopped = expectation(description: "Request stopped")
        AuthURLProtocol.hangingRequestHandler = { _ in requestStarted.fulfill() }
        AuthURLProtocol.stopHandler = { requestStopped.fulfill() }

        let task = Task {
            try await api.authenticate(identity: Self.identity)
        }
        await fulfillment(of: [requestStarted], timeout: 1)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected: cancellation is not converted into a recoverable transport error.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        await fulfillment(of: [requestStopped], timeout: 1)
    }

    func testInvalidAuthenticationSuccessValuesThrowContractViolation() async {
        let invalidFixtures = [
            #"{"userId":"","accessToken":"token","expiresAt":"2030-01-01T00:00:00Z"}"#,
            #"{"userId":"user-1","accessToken":"   ","expiresAt":"2030-01-01T00:00:00Z"}"#,
            #"{"userId":"user-1","accessToken":"token","expiresAt":"2020-01-01T00:00:00Z"}"#
        ]

        for fixture in invalidFixtures {
            let api = makeAPI()
            AuthURLProtocol.requestHandler = { request in
                (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(fixture.utf8)
                )
            }

            await assertError(.contractViolation) {
                try await api.authenticate(identity: Self.identity)
            }
        }
    }

    func testInconsistentStatisticsSuccessThrowsContractViolation() async {
        let api = makeAPI()
        AuthURLProtocol.requestHandler = { request in
            let data = Data(
                #"{"summary":{"playedQuizzes":1,"correctAnswers":6,"totalQuestions":5,"bestCorrectAnswers":6,"bestTotalQuestions":5},"acceptedAttemptIds":[],"legacySummaryAccepted":true}"#.utf8
            )
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        await assertError(.contractViolation) {
            try await api.syncStatistics(request: Self.emptySyncRequest, accessToken: "token")
        }
    }

    func testLegacyAllWrongStatisticsAcknowledgementClearsOutboxWithoutInventingBestGame() async throws {
        let suiteName = "HTTPAuthAPITests.zero-best.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = StatisticsStore(userDefaults: defaults, key: "statistics", idGenerator: { "zero-attempt" })
        store.activateAuthenticatedUser("user-1")
        store.recordAttempt(correctAnswers: 0, totalQuestions: 5)
        let api = makeAPI()
        AuthURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"summary":{"playedQuizzes":1,"correctAnswers":0,"totalQuestions":5,"bestCorrectAnswers":0,"bestTotalQuestions":0},"acceptedAttemptIds":["zero-attempt"],"legacySummaryAccepted":false}"#.utf8)
            )
        }

        let response = try await api.syncStatistics(
            request: store.makeSyncRequest(for: "user-1"), accessToken: "token"
        )
        store.applySyncResponse(response, for: "user-1")

        XCTAssertEqual(response.acceptedAttemptIds, ["zero-attempt"])
        XCTAssertEqual(response.summary.bestTotalQuestions, 0)
        XCTAssertEqual(store.loadSummary(), response.summary)
        XCTAssertFalse(store.hasPendingSync(for: "user-1"))
        let reloaded = StatisticsStore(userDefaults: defaults, key: "statistics")
        XCTAssertFalse(reloaded.hasPendingSync(for: "user-1"))
        XCTAssertEqual(reloaded.loadSummary().playedQuizzes, 1)
    }

    func testLegacyZeroBestExceptionRejectsContradictoryStatisticsAndMissingAcknowledgement() async {
        let invalidFixtures = [
            #"{"summary":{"playedQuizzes":1,"correctAnswers":1,"totalQuestions":5,"bestCorrectAnswers":0,"bestTotalQuestions":0},"acceptedAttemptIds":["zero-attempt"],"legacySummaryAccepted":false}"#,
            #"{"summary":{"playedQuizzes":0,"correctAnswers":0,"totalQuestions":5,"bestCorrectAnswers":0,"bestTotalQuestions":0},"acceptedAttemptIds":["zero-attempt"],"legacySummaryAccepted":false}"#,
            #"{"summary":{"playedQuizzes":1,"correctAnswers":0,"totalQuestions":0,"bestCorrectAnswers":0,"bestTotalQuestions":0},"acceptedAttemptIds":["zero-attempt"],"legacySummaryAccepted":false}"#,
            #"{"summary":{"playedQuizzes":1,"correctAnswers":0,"totalQuestions":5,"bestCorrectAnswers":0,"bestTotalQuestions":0},"acceptedAttemptIds":[],"legacySummaryAccepted":false}"#
        ]
        let request = StatisticsStore.SyncRequest(
            migrationId: "migration-1", legacySummary: nil,
            attempts: [.init(id: "zero-attempt", correctAnswers: 0, totalQuestions: 5,
                             completedAt: Date(timeIntervalSince1970: 1_234))]
        )
        for fixture in invalidFixtures {
            AuthURLProtocol.requestHandler = { request in
                (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(fixture.utf8)
                )
            }
            await assertError(.contractViolation) {
                try await self.makeAPI().syncStatistics(request: request, accessToken: "token")
            }
        }
    }

    func testStatisticsResponseMustAcknowledgeEveryAttemptInBatch() async {
        let api = makeAPI()
        AuthURLProtocol.requestHandler = { request in
            let data = Data(
                #"{"summary":{"playedQuizzes":1,"correctAnswers":3,"totalQuestions":5,"bestCorrectAnswers":3,"bestTotalQuestions":5},"acceptedAttemptIds":[],"legacySummaryAccepted":true}"#.utf8
            )
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data
            )
        }
        let request = StatisticsStore.SyncRequest(
            migrationId: "migration-1",
            legacySummary: nil,
            attempts: [
                StatisticsStore.PendingAttempt(
                    id: "attempt-1",
                    correctAnswers: 3,
                    totalQuestions: 5,
                    completedAt: Date(timeIntervalSince1970: 1_234)
                )
            ]
        )

        await assertError(.contractViolation) {
            try await api.syncStatistics(request: request, accessToken: "token")
        }
    }

    private func makeAPI(
        requestTimeout: TimeInterval = 15,
        metrics: BackendRequestMetricRecording = NoopBackendRequestMetricRecorder()
    ) -> HTTPAuthAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return HTTPAuthAPI(
            configuration: BackendConfiguration(
                baseURL: URL(string: "https://backend.example/api")!
            ),
            session: session,
            requestTimeout: requestTimeout,
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            metrics: metrics
        )
    }

    private func assertError<T>(
        _ expectedError: BackendAPIError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expectedError)", file: file, line: line)
        } catch let error as BackendAPIError {
            XCTAssertEqual(error, expectedError, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private static let identity = GameCenterIdentity(
        teamPlayerId: "team-1",
        bundleId: "ru.avtabenskiy.Quizice",
        publicKeyUrl: "https://apple.example/key",
        signature: "c2lnbmF0dXJl",
        salt: "c2FsdA==",
        timestamp: "123456"
    )

    private static let emptySyncRequest = StatisticsStore.SyncRequest(
        migrationId: "migration-1",
        legacySummary: nil,
        attempts: []
    )

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

final class BackendConfigurationTests: XCTestCase {
    func testProductionEndpointIsAccepted() throws {
        let configuration = try XCTUnwrap(
            BackendConfiguration.configuration(
                from: "https://bbav8b1v6032q53l8360.containers.yandexcloud.net/api"
            )
        )

        XCTAssertEqual(
            configuration.baseURL.absoluteString,
            "https://bbav8b1v6032q53l8360.containers.yandexcloud.net/api"
        )
    }

    func testRelativeMissingHostAndInsecureRemoteURLsAreRejected() {
        XCTAssertNil(BackendConfiguration.configuration(from: "api/v1"))
        XCTAssertNil(BackendConfiguration.configuration(from: "https:///api"))
        XCTAssertNil(BackendConfiguration.configuration(from: "http://backend.example/api"))
        XCTAssertNil(BackendConfiguration.configuration(from: "$(BACKEND_BASE_URL)"))
    }

    #if DEBUG
    func testSchemeAPIBaseURLOverridesBundledConfiguration() throws {
        let suiteName = "BackendConfigurationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = try XCTUnwrap(
            BackendConfiguration.load(
                bundle: .main,
                userDefaults: defaults,
                environment: ["API_BASE_URL": "http://localhost:9000/api"]
            )
        )

        XCTAssertEqual(configuration.baseURL, URL(string: "http://localhost:9000/api"))
    }

    func testLocalhostOverrideWinsWhenEnabled() throws {
        let suiteName = "BackendConfigurationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: DebugBackendSettings.useLocalhostKey)

        let configuration = try XCTUnwrap(
            BackendConfiguration.load(bundle: .main, userDefaults: defaults)
        )

        XCTAssertEqual(configuration.baseURL, URL(string: "http://localhost:8000/api"))
    }

    func testLocalContentOnlyDisablesBackendConfiguration() throws {
        let suiteName = "BackendConfigurationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: DebugBackendSettings.useLocalhostKey)
        defaults.set(true, forKey: DebugBackendSettings.useLocalContentOnlyKey)

        XCTAssertNil(BackendConfiguration.load(bundle: .main, userDefaults: defaults))
    }

    func testHTTPLocalhostIsAcceptedOnlyByDebugValidation() throws {
        let configuration = try XCTUnwrap(
            BackendConfiguration.configuration(from: "http://localhost:8000/api")
        )
        XCTAssertEqual(configuration.baseURL, DebugBackendSettings.localhostBaseURL)
    }
    #endif
}

@MainActor
final class AccountDeletionServiceTests: XCTestCase {
    func testSuccessfulDeletionClearsDataAndSuppressesAutomaticRecreationAcrossLaunches() async throws {
        let h = Harness()
        await h.signIn()
        h.statistics.recordAttempt(correctAnswers: 2, totalQuestions: 5)
        var accessStates: [AppAccountAccessState] = []
        h.service.accountAccessStateDidChange = { accessStates.append($0) }
        try await h.service.deleteAccount()
        XCTAssertTrue(accessStates.contains(.loading))
        XCTAssertEqual(accessStates.filter { $0 != .loading }, [.authenticated, .deleted])
        XCTAssertNil(h.store.session)
        XCTAssertEqual(h.statistics.loadSummary(), .empty)
        XCTAssertEqual(h.erasedUsers, ["user-1"])
        XCTAssertTrue(h.service.canCreateAccount)
        XCTAssertFalse(h.access.isAIQuizAvailable)
        h.service.retrySynchronization()
        let startCount = h.gameCenter.startCount
        h.service.signIn { _ in }
        XCTAssertEqual(h.gameCenter.startCount, startCount)
        XCTAssertEqual(h.service.accountAccessState, .deleted)
        h.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))
        h.notifications.post(name: .backendAuthenticationInvalidated, object: nil)
        await Task.yield()
        XCTAssertEqual(h.api.authenticatedIdentities.count, 1)
        let restarted = h.makeService()
        restarted.start { _ in }
        h.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))
        await Task.yield()
        XCTAssertTrue(restarted.canCreateAccount)
        XCTAssertEqual(restarted.accountAccessState, .deleted)
        XCTAssertEqual(h.api.authenticatedIdentities.count, 1)
        XCTAssertEqual(h.api.recreationRequests, 0)
    }

    func testFailedDeletionPreservesDataAndReusesKeyAfterRestart() async throws {
        let h = Harness()
        await h.signIn()
        h.api.deletionHandler = { throw BackendAPIError.transport(.timedOut) }
        h.statistics.recordAttempt(correctAnswers: 2, totalQuestions: 5)
        let previous = h.statistics.loadSummary()
        do { try await h.service.deleteAccount(); XCTFail("Expected timeout") } catch { }
        XCTAssertNotNil(h.store.session)
        XCTAssertEqual(h.statistics.loadSummary(), previous)
        XCTAssertTrue(h.erasedUsers.isEmpty)
        XCTAssertEqual(h.service.accountAccessState, .deletionPending)
        let restarted = h.makeService()
        restarted.start { _ in }
        XCTAssertEqual(restarted.accountAccessState, .deletionPending)
        let startCount = h.gameCenter.startCount
        restarted.signIn { _ in }
        XCTAssertEqual(h.gameCenter.startCount, startCount)
        h.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))
        XCTAssertTrue(restarted.accountDeletionAvailable)
        h.api.deletionHandler = nil
        try await restarted.deleteAccount()
        XCTAssertEqual(h.api.deletionRequests.count, 2)
        XCTAssertEqual(h.api.deletionRequests[0].1, h.api.deletionRequests[1].1)
        XCTAssertEqual(h.api.authenticatedIdentities.count, 1)
    }

    func testLocalCleanupRetryDoesNotRepeatServerDeletion() async throws {
        let h = Harness()
        await h.signIn()
        h.cleanupFails = true
        do { try await h.service.deleteAccount(); XCTFail("Expected cleanup failure") }
        catch { XCTAssertEqual(error as? AccountDeletionError, .localCleanupFailed) }
        XCTAssertNil(h.store.session)
        XCTAssertTrue(h.service.accountDeletionAvailable)
        XCTAssertFalse(h.service.canCreateAccount)
        XCTAssertEqual(h.service.accountAccessState, .deletionPending)
        let startCount = h.gameCenter.startCount
        h.service.signIn { _ in }
        XCTAssertEqual(h.gameCenter.startCount, startCount)
        h.cleanupFails = false
        try await h.service.deleteAccount()
        XCTAssertEqual(h.api.deletionRequests.count, 1)
        XCTAssertTrue(h.service.canCreateAccount)
        XCTAssertEqual(h.service.accountAccessState, .deleted)
    }

    func testPendingDeletionSurvivesUnavailableOrDifferentGameCenterOnRestart() async throws {
        for playerState in [GameCenterPlayerState.unavailable, .authenticated(teamPlayerID: "other-player")] {
            let h = Harness()
            await h.signIn()
            h.api.deletionHandler = { throw BackendAPIError.transport(.timedOut) }
            do { try await h.service.deleteAccount() } catch { }
            let restarted = h.makeService()
            restarted.start { _ in }
            h.gameCenter.emit(playerState)
            XCTAssertEqual(h.store.session?.userID, "user-1")
            XCTAssertTrue(restarted.accountDeletionAvailable)
            XCTAssertEqual(h.api.authenticatedIdentities.count, 1)
        }
    }

    func testMissingEndpointPreservesUsableExistingAccount() async throws {
        let h = Harness()
        await h.signIn()
        h.api.deletionHandler = { throw BackendAPIError.httpStatus(404, nil) }
        do { try await h.service.deleteAccount(); XCTFail("Expected missing endpoint") } catch { }
        XCTAssertNotNil(h.store.session)
        XCTAssertTrue(h.access.isAIQuizAvailable)
        XCTAssertTrue(h.service.accountDeletionAvailable)
        XCTAssertNil(h.deletionState.record(for: "team-1"))
    }

    func testFirstUnauthorizedDeletionRefreshesWithoutRecreationAndCanBeRetried() async throws {
        let h = Harness()
        await h.signIn()
        h.api.sessionsByTeamPlayerID["team-1"] = AuthSession(
            userID: "user-1", accessToken: "refreshed-token", expiresAt: .distantFuture, teamPlayerID: "team-1"
        )
        h.api.deletionHandler = { throw AccountDeletionError.sessionExpired }

        do { try await h.service.deleteAccount(); XCTFail("Expected expired session") }
        catch { XCTAssertEqual(error as? AccountDeletionError, .sessionExpired) }
        await waitFor { h.service.accountDeletionAvailable && h.store.session?.accessToken == "refreshed-token" }

        XCTAssertNil(h.deletionState.record(for: "team-1"))
        XCTAssertEqual(h.api.authenticatedIdentities.count, 2)
        XCTAssertEqual(h.api.recreationRequests, 0)
        XCTAssertTrue(h.erasedUsers.isEmpty)
        h.api.deletionHandler = nil
        try await h.service.deleteAccount()
        XCTAssertEqual(h.api.deletionRequests.count, 2)
        XCTAssertEqual(h.api.deletionRequests.last?.0, "refreshed-token")
        XCTAssertNotEqual(h.api.deletionRequests.first?.1, h.api.deletionRequests.last?.1)
        XCTAssertEqual(h.erasedUsers, ["user-1"])
    }

    func testUnauthorizedRetryPreservesReceiptAndCredentialWhenVerifiedRecoveryFails() async throws {
        let h = Harness()
        await h.signIn()
        h.api.deletionHandler = { throw BackendAPIError.transport(.timedOut) }
        do { try await h.service.deleteAccount(); XCTFail("Expected lost response") } catch { }
        let receipt = try XCTUnwrap(h.deletionState.record(for: "team-1"))
        h.api.deletionHandler = { throw AccountDeletionError.sessionExpired }
        h.api.authenticationErrors = [.transport(.notConnectedToInternet)]

        do { try await h.service.deleteAccount(); XCTFail("Expected recovery failure") }
        catch { XCTAssertEqual(error as? BackendAPIError, .transport(.notConnectedToInternet)) }

        XCTAssertEqual(h.deletionState.record(for: "team-1"), receipt)
        XCTAssertEqual(h.store.session?.accessToken, "access-token")
        XCTAssertEqual(h.service.state, .deletionPending)
        XCTAssertEqual(h.api.authenticatedIdentities.count, 2)
        XCTAssertEqual(h.api.recreationRequests, 0)
        XCTAssertEqual(h.api.deletionRequests.first?.1, h.api.deletionRequests.last?.1)
        XCTAssertTrue(h.erasedUsers.isEmpty)
    }

    func testUnauthorizedDeletionRefreshHandlesServerDeletedAccountWithoutRecreation() async throws {
        let h = Harness()
        await h.signIn()
        h.api.deletionHandler = { throw AccountDeletionError.sessionExpired }
        h.api.authenticationErrors = [.httpStatus(409, .init(code: "account_deleted", message: "Deleted"))]

        do { try await h.service.deleteAccount(); XCTFail("Expected expired session") } catch { }
        await waitFor { h.service.canCreateAccount }

        XCTAssertEqual(h.erasedUsers, ["user-1"])
        XCTAssertNil(h.store.session)
        XCTAssertEqual(h.api.deletionRequests.count, 1)
        XCTAssertEqual(h.api.recreationRequests, 0)
        XCTAssertEqual(h.deletionState.record(for: "team-1")?.userID, "user-1")
    }

    func testServerDeletionAfterFailedRefreshAndRelaunchErasesActualAccountScope() async throws {
        let h = Harness()
        // Model an existing installation before the remembered-identity mapping
        // was introduced: only its expired Keychain session identifies the scope.
        h.store.session = AuthSession(userID: "user-1", accessToken: "expired-token",
                                      expiresAt: .distantPast, teamPlayerID: "team-1")
        h.statistics.activateAuthenticatedUser("user-1")
        h.statistics.recordAttempt(correctAnswers: 2, totalQuestions: 5)
        h.api.authenticationErrors = [.transport(.timedOut)]
        h.service.start { _ in }
        h.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))
        await waitFor { h.service.state == .guest }
        XCTAssertNil(h.store.session)
        XCTAssertTrue(h.statistics.hasPendingSync(for: "user-1"))

        let reloadedDeletionState = AccountDeletionStateStore(defaults: h.defaults)
        XCTAssertEqual(reloadedDeletionState.lastKnownUserID(for: "team-1"), "user-1")
        let restarted = h.makeService(deletionState: reloadedDeletionState)
        h.api.authenticationErrors = [.httpStatus(409, .init(code: "account_deleted", message: "Deleted"))]
        restarted.start { _ in }
        h.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))
        await waitFor { restarted.canCreateAccount }

        XCTAssertEqual(h.erasedUsers, ["user-1"])
        XCTAssertEqual(reloadedDeletionState.record(for: "team-1")?.userID, "user-1")
        XCTAssertNil(reloadedDeletionState.lastKnownUserID(for: "team-1"))
        XCTAssertFalse(h.statistics.hasPendingSync(for: "user-1"))
        XCTAssertTrue(h.api.deletionRequests.isEmpty)
        XCTAssertEqual(h.api.recreationRequests, 0)
        h.statistics.activateAuthenticatedUser("user-1")
        XCTAssertEqual(h.statistics.loadSummary(), .empty)
    }

    func testNewAccountRequiresExplicitRecreationAndDoesNotRestoreOldData() async throws {
        let h = Harness()
        await h.signIn()
        try await h.service.deleteAccount()
        h.api.sessionsByTeamPlayerID["team-1"] = AuthSession(
            userID: "new-user", accessToken: "new-token", expiresAt: .distantFuture, teamPlayerID: "team-1"
        )
        try await h.service.createAccount()
        XCTAssertEqual(h.api.recreationRequests, 1)
        XCTAssertEqual(h.service.accountAccessState, .authenticated)
        XCTAssertEqual(h.store.session?.userID, "new-user")
        XCTAssertTrue(h.service.accountDeletionAvailable)
        XCTAssertFalse(h.service.canCreateAccount)
        XCTAssertTrue(h.access.isAIQuizAvailable)
        XCTAssertEqual(h.statistics.loadSummary(), .empty)
    }

    func testChangedGameCenterIdentityDuringRecreationSwitchesAccountWithoutRecreatingOldUser() async throws {
        let h = Harness()
        await h.signIn()
        try await h.service.deleteAccount()
        h.gameCenter.identity = GameCenterIdentity(
            teamPlayerId: "other-player", bundleId: "com.example.quiz",
            publicKeyUrl: "https://apple.example/key", signature: "signature", salt: "salt", timestamp: "123"
        )
        h.api.sessionsByTeamPlayerID["other-player"] = AuthSession(
            userID: "other-user", accessToken: "other-token", expiresAt: .distantFuture, teamPlayerID: "other-player"
        )

        do { try await h.service.createAccount(); XCTFail("Expected Game Center account change") }
        catch { XCTAssertEqual(error as? GameCenterAuthenticationError, .playerChanged) }
        await waitFor { h.service.accountAccessState == .authenticated }

        XCTAssertEqual(h.store.session?.userID, "other-user")
        XCTAssertEqual(h.deletionState.record(for: "team-1")?.cleanupCompleted, true)
        XCTAssertEqual(h.api.recreationRequests, 0)
        XCTAssertEqual(h.api.authenticatedIdentities.map(\.teamPlayerId), ["team-1", "other-player"])
    }

    func testLostGameCenterSessionDuringRecreationOffersSignInWithoutBypassingDeletionReceipt() async throws {
        let h = Harness()
        await h.signIn()
        try await h.service.deleteAccount()
        h.gameCenter.identityError = GameCenterClientError.notAuthenticated

        do { try await h.service.createAccount(); XCTFail("Expected Game Center sign-out") }
        catch { XCTAssertEqual(error as? GameCenterClientError, .notAuthenticated) }

        XCTAssertEqual(h.service.accountAccessState, .signInRequired)
        XCTAssertEqual(h.deletionState.record(for: "team-1")?.cleanupCompleted, true)
        XCTAssertEqual(h.api.recreationRequests, 0)
        h.service.signIn { _ in }
        XCTAssertEqual(h.gameCenter.startCount, 2)
        h.gameCenter.identityError = nil
        h.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))
        XCTAssertEqual(h.service.accountAccessState, .deleted)
        XCTAssertEqual(h.api.authenticatedIdentities.count, 1)
        XCTAssertEqual(h.api.recreationRequests, 0)
    }

    func testFailedExplicitRecreationStaysLockedAndCanBeRetried() async throws {
        let h = Harness()
        await h.signIn()
        try await h.service.deleteAccount()
        var accessStates: [AppAccountAccessState] = []
        h.service.accountAccessStateDidChange = { accessStates.append($0) }
        h.api.authenticationErrors = [.transport(.notConnectedToInternet)]

        do { try await h.service.createAccount(); XCTFail("Expected offline recreation failure") }
        catch { XCTAssertEqual(error as? BackendAPIError, .transport(.notConnectedToInternet)) }

        XCTAssertEqual(accessStates, [.deleted, .loading, .deleted])
        XCTAssertEqual(h.service.accountAccessState, .deleted)
        XCTAssertNil(h.store.session)
        XCTAssertTrue(h.service.canCreateAccount)
        h.api.sessionsByTeamPlayerID["team-1"] = AuthSession(
            userID: "new-user", accessToken: "new-token", expiresAt: .distantFuture, teamPlayerID: "team-1"
        )
        try await h.service.createAccount()
        XCTAssertEqual(h.service.accountAccessState, .authenticated)
        XCTAssertEqual(h.api.recreationRequests, 2)
    }

    func testPendingDeletionWithExpiredTokenReauthenticatesSameUserAndReusesOperationKey() async throws {
        let h = Harness()
        let receipt = try await makeExpiredPendingDeletion(h)
        h.api.sessionsByTeamPlayerID["team-1"] = AuthSession(
            userID: "user-1", accessToken: "fresh-token", expiresAt: .distantFuture, teamPlayerID: "team-1"
        )
        h.api.deletionHandler = {
            if h.api.deletionRequests.last?.0 == "access-token" { throw AccountDeletionError.sessionExpired }
        }

        try await h.service.deleteAccount()

        XCTAssertEqual(h.api.deletionRequests.map(\.0), ["access-token", "access-token", "fresh-token"])
        XCTAssertEqual(Set(h.api.deletionRequests.map(\.1)), [receipt.idempotencyKey])
        XCTAssertEqual(h.api.authenticatedIdentities.count, 2)
        XCTAssertEqual(h.api.recreationRequests, 0)
        XCTAssertEqual(h.service.accountAccessState, .deleted)
        XCTAssertNil(h.service.authenticatedAccountID)
        XCTAssertNil(h.store.session)
        XCTAssertEqual(h.erasedUsers, ["user-1"])
    }

    func testVerifiedDeletedIdentityResolvesPendingDeletionWithoutRepeatingDelete() async throws {
        let h = Harness()
        let receipt = try await makeExpiredPendingDeletion(h)
        h.api.authenticationErrors = [.httpStatus(409, .init(code: "account_deleted", message: "Deleted"))]

        try await h.service.deleteAccount()

        XCTAssertEqual(h.api.deletionRequests.count, 2)
        XCTAssertEqual(Set(h.api.deletionRequests.map(\.1)), [receipt.idempotencyKey])
        XCTAssertEqual(h.api.recreationRequests, 0)
        XCTAssertEqual(h.service.accountAccessState, .deleted)
        XCTAssertNil(h.store.session)
        XCTAssertEqual(h.erasedUsers, ["user-1"])
    }

    func testPendingDeletionRecoveryRejectsDifferentGameCenterIdentity() async throws {
        let h = Harness()
        let receipt = try await makeExpiredPendingDeletion(h)
        h.gameCenter.identity = GameCenterIdentity(
            teamPlayerId: "other-player", bundleId: "com.example.quiz",
            publicKeyUrl: "https://apple.example/key", signature: "signature", salt: "salt", timestamp: "123"
        )

        do { try await h.service.deleteAccount(); XCTFail("Expected identity mismatch") }
        catch { XCTAssertEqual(error as? GameCenterAuthenticationError, .playerChanged) }

        XCTAssertEqual(h.deletionState.record(for: "team-1"), receipt)
        XCTAssertEqual(h.store.session?.accessToken, "access-token")
        XCTAssertEqual(h.service.accountAccessState, .deletionPending)
        XCTAssertEqual(h.api.authenticatedIdentities.count, 1)
        XCTAssertEqual(h.api.deletionRequests.count, 2)
        XCTAssertTrue(h.erasedUsers.isEmpty)
    }

    func testPendingDeletionRecoveryRejectsDifferentBackendUserOrTeam() async throws {
        for (userID, teamPlayerID) in [("other-user", "team-1"), ("user-1", "other-player")] {
            let h = Harness()
            let receipt = try await makeExpiredPendingDeletion(h)
            h.api.sessionsByTeamPlayerID["team-1"] = AuthSession(
                userID: userID, accessToken: "fresh-token", expiresAt: .distantFuture, teamPlayerID: teamPlayerID
            )

            do { try await h.service.deleteAccount(); XCTFail("Expected session mismatch") }
            catch { XCTAssertEqual(error as? BackendAPIError, .contractViolation) }

            XCTAssertEqual(h.deletionState.record(for: "team-1"), receipt)
            XCTAssertEqual(h.store.session?.accessToken, "access-token")
            XCTAssertEqual(h.service.accountAccessState, .deletionPending)
            XCTAssertEqual(h.api.authenticatedIdentities.count, 2)
            XCTAssertEqual(h.api.recreationRequests, 0)
            XCTAssertEqual(h.api.deletionRequests.count, 2)
            XCTAssertTrue(h.erasedUsers.isEmpty)
        }
    }

    func testLostRecoveryDeleteResponsePreservesOriginalCredentialAndResolvesAfterRestart() async throws {
        let h = Harness()
        let receipt = try await makeExpiredPendingDeletion(h)
        h.api.sessionsByTeamPlayerID["team-1"] = AuthSession(
            userID: "user-1", accessToken: "fresh-token", expiresAt: .distantFuture, teamPlayerID: "team-1"
        )
        h.api.deletionHandler = {
            if h.api.deletionRequests.last?.0 == "access-token" { throw AccountDeletionError.sessionExpired }
            throw BackendAPIError.transport(.timedOut)
        }
        do { try await h.service.deleteAccount(); XCTFail("Expected lost recovery response") } catch { }
        XCTAssertEqual(h.store.session?.accessToken, "access-token")
        XCTAssertEqual(h.deletionState.record(for: "team-1"), receipt)
        XCTAssertEqual(h.service.accountAccessState, .deletionPending)

        let restarted = h.makeService()
        restarted.start { _ in }
        h.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))
        h.api.authenticationErrors = [.httpStatus(409, .init(code: "account_deleted", message: "Deleted"))]
        try await restarted.deleteAccount()

        XCTAssertEqual(h.api.deletionRequests.map(\.0), ["access-token", "access-token", "fresh-token", "access-token"])
        XCTAssertEqual(Set(h.api.deletionRequests.map(\.1)), [receipt.idempotencyKey])
        XCTAssertEqual(restarted.accountAccessState, .deleted)
        XCTAssertNil(h.store.session)
        XCTAssertEqual(h.erasedUsers, ["user-1"])
        XCTAssertEqual(h.api.recreationRequests, 0)
    }

    private func makeExpiredPendingDeletion(_ h: Harness) async throws -> AccountDeletionStateStore.Record {
        await h.signIn()
        h.api.deletionHandler = { throw BackendAPIError.transport(.timedOut) }
        do { try await h.service.deleteAccount(); XCTFail("Expected initial timeout") } catch { }
        let receipt = try XCTUnwrap(h.deletionState.record(for: "team-1"))
        h.api.deletionHandler = { throw AccountDeletionError.sessionExpired }
        return receipt
    }

    private func waitFor(_ condition: @escaping () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(condition())
    }

    @MainActor
    private final class Harness {
        let gameCenter = FakeGameCenterClient()
        let api = FakeAuthAPI()
        let store = MemorySessionStore()
        let notifications = NotificationCenter()
        let access = AIQuizAccessStore()
        let defaults: UserDefaults
        let deletionState: AccountDeletionStateStore
        let statistics: StatisticsStore
        var erasedUsers: [String] = []
        var cleanupFails = false
        lazy var service = makeService()

        init() {
            defaults = UserDefaults(suiteName: "AccountDeletionServiceTests.\(UUID())")!
            deletionState = AccountDeletionStateStore(defaults: defaults)
            statistics = StatisticsStore(userDefaults: defaults, notificationCenter: notifications)
        }

        func makeService(deletionState: AccountDeletionStateStore? = nil) -> GameCenterAuthenticationService {
            GameCenterAuthenticationService(
                gameCenter: gameCenter, api: api, sessionStore: store, statisticsStore: statistics,
                bundleIdentifier: "com.example.quiz", notificationCenter: notifications,
                aiQuizAccessStore: access, deletionStateStore: deletionState ?? self.deletionState,
                eraseLocalAccountData: { [weak self] userID in
                    guard let self else { return }
                    if self.cleanupFails { throw CocoaError(.fileWriteUnknown) }
                    self.erasedUsers.append(userID)
                }
            )
        }

        func signIn() async {
            service.start { _ in }
            gameCenter.emit(.authenticated(teamPlayerID: "team-1"))
            for _ in 0..<100 where !service.accountDeletionAvailable {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            XCTAssertTrue(service.accountDeletionAvailable)
        }
    }
}

extension HTTPAuthAPITests {
    func testAccountDeletionUsesAuthenticatedDELETEAndAcceptsOnly204() async throws {
        let key = UUID().uuidString
        var status = 204
        AuthURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/me/account")
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.value(forHTTPHeaderField: BackendConfiguration.authorizationHeader), "Bearer token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Idempotency-Key"), key)
            XCTAssertNil(Self.bodyData(from: request))
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data())
        }
        try await makeAPI().deleteAccount(accessToken: "token", idempotencyKey: key)
        for invalidStatus in [200, 202, 401, 404, 500] {
            status = invalidStatus
            do {
                try await makeAPI().deleteAccount(accessToken: "token", idempotencyKey: key)
                XCTFail("Must not claim deletion for HTTP \(status)")
            } catch { }
        }
    }

    func testExplicitRecreationSendsOptInFlag() async throws {
        AuthURLProtocol.requestHandler = { request in
            let body = try XCTUnwrap(Self.bodyData(from: request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["recreateDeletedAccount"] as? Bool, true)
            XCTAssertEqual(json["teamPlayerId"] as? String, "team-1")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"userId":"new-user","accessToken":"new-token","expiresAt":"2030-01-01T00:00:00Z"}"#.utf8))
        }
        _ = try await makeAPI().authenticate(identity: Self.identity, recreateDeletedAccount: true)
    }
}
