import SwiftUI
import UIKit
import XCTest
@testable import Quizice

@MainActor
final class AppAccountAccessPresenterTests: XCTestCase {
    func testResolvedUnauthenticatedStatesKeepGameplayBehindOpaqueNonDismissibleGate() async throws {
        for state in [AppAccountAccessState.signInRequired, .deletionPending, .deleted] {
            let harness = try makeHarness(state: state)
            defer { harness.dispose() }
            harness.presenter.start()
            let launchContentReady = expectation(description: "Account gate is ready for launch reveal")

            harness.presenter.prepareInitialContent { launchContentReady.fulfill() }
            await fulfillment(of: [launchContentReady], timeout: 5)
            harness.presenter.launchDidFinish()

            let gate = try assertGameplayIsLocked(harness)
            XCTAssertEqual(gate.windowLevel.rawValue, harness.window.windowLevel.rawValue + 0.5)
            XCTAssertEqual(gate.alpha, 1)
            XCTAssertEqual(try XCTUnwrap(gate.backgroundColor).cgColor.alpha, 1)
            XCTAssertTrue(try XCTUnwrap(gate.rootViewController).isModalInPresentation)
            XCTAssertTrue(harness.events.prepareCompletions.isEmpty)
            XCTAssertEqual(harness.account.createCallCount, 0)
            XCTAssertEqual(harness.account.deleteCallCount, 0)
        }
    }

    func testLoadingDoesNotAllowSplashToRevealTheAccountGate() async throws {
        let harness = try makeHarness(state: .loading)
        defer { harness.dispose() }
        harness.presenter.start()
        var revealCount = 0
        harness.presenter.prepareInitialContent { revealCount += 1 }
        await Task.yield()
        XCTAssertEqual(revealCount, 0)
        XCTAssertTrue(try accountHost(in: harness).rootView.model.usesConnectionSplash)
        harness.account.send(.authenticated)
        try await waitUntil { harness.events.prepareCompletions.count == 1 }
        XCTAssertEqual(revealCount, 0)
        harness.events.prepareCompletions[0]()
        try await waitUntil { revealCount == 1 }
    }

    func testConnectionTimeoutOffersRetryOnSplashAndAcceptsLateAuthentication() async throws {
        let harness = try makeHarness(state: .loading, connectionTimeout: 0.05)
        defer { harness.dispose() }
        harness.presenter.start()
        var reveals = 0
        harness.presenter.prepareInitialContent { reveals += 1 }
        let host = try accountHost(in: harness)
        try await waitUntil { host.rootView.model.errorMessage != nil }
        XCTAssertEqual(reveals, 1)
        XCTAssertTrue(host.rootView.model.usesConnectionSplash)
        _ = try assertGameplayIsLocked(harness)
        host.rootView.onPrimaryAction()
        XCTAssertEqual(harness.account.signInCallCount, 1)
        XCTAssertNil(host.rootView.model.errorMessage)
        harness.account.send(.loading)
        try await waitUntil { host.rootView.model.errorMessage != nil }
        XCTAssertEqual(reveals, 1)
        harness.account.send(.authenticated)
        try await waitUntil { harness.events.prepareCompletions.count == 1 }
        harness.events.prepareCompletions[0]()
        try await waitUntil { self.visibleGate(in: harness) == nil }
    }

    func testStoppingLaunchCancelsThePendingConnectionTimeout() async throws {
        let harness = try makeHarness(state: .loading, connectionTimeout: 0.05)
        defer { harness.dispose() }
        harness.presenter.start()
        var reveals = 0
        harness.presenter.prepareInitialContent { reveals += 1 }
        let model = try accountHost(in: harness).rootView.model
        harness.presenter.stop()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(reveals, 0)
        XCTAssertNil(visibleGate(in: harness))
    }

    func testBackendFailureDoesNotAskAuthenticatedGameCenterPlayerToSignInAgain() async throws {
        let harness = try makeHarness(state: .signInRequired)
        defer { harness.dispose() }
        harness.account.needsGameCenterSignIn = false
        harness.presenter.start()
        let host = try accountHost(in: harness)
        XCTAssertTrue(host.rootView.model.usesConnectionSplash)
        host.rootView.onPrimaryAction()
        XCTAssertEqual(harness.account.signInCallCount, 1)
        XCTAssertEqual(harness.account.createCallCount, 0)
    }

    func testAuthenticationKeepsGameplayLockedUntilInitialUIKitContentCompletes() async throws {
        let harness = try makeHarness(state: .loading)
        defer { harness.dispose() }
        harness.presenter.start()
        harness.presenter.launchDidFinish()

        harness.account.send(.authenticated)
        try await waitUntil { harness.events.prepareCompletions.count == 1 }
        _ = try assertGameplayIsLocked(harness)

        harness.events.prepareCompletions[0]()
        try await waitUntil { self.visibleGate(in: harness) == nil }

        XCTAssertTrue(harness.window.isUserInteractionEnabled)
        XCTAssertFalse(harness.root.view.accessibilityElementsHidden)
    }

    func testAuthenticatedLaunchReadinessWaitsForUIKitPresentation() async throws {
        let harness = try makeHarness(state: .authenticated)
        defer { harness.dispose() }
        harness.presenter.start()
        var initialContentReadyCount = 0
        harness.presenter.prepareInitialContent { initialContentReadyCount += 1 }
        try await waitUntil { harness.events.prepareCompletions.count == 1 }

        XCTAssertEqual(initialContentReadyCount, 0)
        _ = try assertGameplayIsLocked(harness)

        let finish = harness.events.prepareCompletions[0]
        finish()
        finish()
        try await waitUntil { initialContentReadyCount == 1 }
        harness.presenter.launchDidFinish()
        try await waitUntil { self.visibleGate(in: harness) == nil }
        XCTAssertTrue(harness.window.isUserInteractionEnabled)
    }

    func testStaleAuthenticatedCompletionCannotUnlockAfterAccessIsRevoked() async throws {
        let harness = try makeHarness(state: .loading)
        defer { harness.dispose() }
        harness.presenter.start()
        harness.presenter.launchDidFinish()
        harness.account.send(.authenticated)
        try await waitUntil { harness.events.prepareCompletions.count == 1 }
        let staleCompletion = harness.events.prepareCompletions[0]

        harness.account.send(.deleted)
        // The state observer renders on a later MainActor turn. Even before
        // that turn, a stale UIKit callback must respect the current access state.
        staleCompletion()
        _ = try assertGameplayIsLocked(harness)
        await Task.yield()
        await Task.yield()
        staleCompletion()
        _ = try assertGameplayIsLocked(harness)
        XCTAssertEqual(harness.account.createCallCount, 0)

        harness.account.send(.authenticated)
        try await waitUntil { harness.events.prepareCompletions.count == 2 }
        staleCompletion()
        _ = try assertGameplayIsLocked(harness)
        harness.events.prepareCompletions[1]()
        try await waitUntil { self.visibleGate(in: harness) == nil }
        XCTAssertTrue(harness.window.isUserInteractionEnabled)
    }

    func testDeletingAnAdmittedAccountResetsNavigationAndRemainsLockedAfterRestart() async throws {
        let harness = try makeHarness(state: .authenticated)
        defer { harness.dispose() }
        harness.presenter.start()
        harness.presenter.launchDidFinish()
        try await waitUntil { harness.events.prepareCompletions.count == 1 }
        harness.events.prepareCompletions[0]()
        try await waitUntil { self.visibleGate(in: harness) == nil }

        harness.account.send(.deletionPending)
        try await waitUntil { !harness.events.resetCompletions.isEmpty }
        _ = try assertGameplayIsLocked(harness)
        harness.account.send(.deleted)
        await Task.yield()
        harness.events.resetCompletions.forEach { $0() }
        _ = try assertGameplayIsLocked(harness)
        XCTAssertEqual(harness.account.createCallCount, 0)
        XCTAssertEqual(harness.account.deleteCallCount, 0)

        harness.presenter.stop()
        let restartedPresenter = makePresenter(
            window: harness.window,
            account: harness.account,
            events: AccessPresenterEvents()
        )
        defer { restartedPresenter.stop() }
        restartedPresenter.start()
        let launchContentReady = expectation(description: "Deleted account gate survives restart")
        restartedPresenter.prepareInitialContent { launchContentReady.fulfill() }
        await fulfillment(of: [launchContentReady], timeout: 5)
        restartedPresenter.launchDidFinish()

        _ = try assertGameplayIsLocked(harness)
        XCTAssertEqual(harness.account.createCallCount, 0)
        XCTAssertEqual(harness.account.deleteCallCount, 0)
    }

    func testAuthenticationCannotUnlockWhilePreviousAccountNavigationIsStillResetting() async throws {
        let harness = try makeHarness(state: .authenticated)
        defer { harness.dispose() }
        harness.presenter.start()
        harness.presenter.launchDidFinish()
        try await waitUntil { harness.events.prepareCompletions.count == 1 }
        harness.events.prepareCompletions[0]()
        try await waitUntil { self.visibleGate(in: harness) == nil }

        harness.account.send(.deletionPending)
        try await waitUntil { harness.events.resetCompletions.count == 1 }
        harness.account.send(.authenticated)
        await Task.yield()
        await Task.yield()
        // An implementation may prepare the next content before or after reset;
        // either way, pending reset must keep the previous account inaccessible.
        harness.events.prepareCompletions.dropFirst().forEach { $0() }
        _ = try assertGameplayIsLocked(harness)

        harness.events.resetCompletions[0]()
        try await waitUntil { harness.events.prepareCompletions.count >= 2 }
        harness.events.prepareCompletions.dropFirst().forEach { $0() }
        try await waitUntil { self.visibleGate(in: harness) == nil }
        XCTAssertTrue(harness.window.isUserInteractionEnabled)
        XCTAssertFalse(harness.root.view.accessibilityElementsHidden)
    }

    func testSwitchingAuthenticatedAccountWaitsForOldAccountNavigationReset() async throws {
        let harness = try makeHarness(state: .authenticated)
        defer { harness.dispose() }
        harness.account.authenticatedAccountID = "account-A"
        harness.presenter.start()
        harness.presenter.launchDidFinish()
        try await waitUntil { harness.events.prepareCompletions.count == 1 }
        harness.events.prepareCompletions[0]()
        try await waitUntil { self.visibleGate(in: harness) == nil }

        harness.account.send(.loading)
        try await waitUntil { self.visibleGate(in: harness) != nil }
        harness.account.authenticatedAccountID = "account-B"
        harness.account.send(.authenticated)
        try await waitUntil { harness.events.resetCompletions.count == 1 }
        harness.events.prepareCompletions.dropFirst().forEach { $0() }
        _ = try assertGameplayIsLocked(harness)

        harness.events.resetCompletions[0]()
        try await waitUntil { harness.events.prepareCompletions.count >= 2 }
        harness.events.prepareCompletions.dropFirst().forEach { $0() }
        try await waitUntil { self.visibleGate(in: harness) == nil }

        XCTAssertTrue(harness.window.isUserInteractionEnabled)
        XCTAssertFalse(harness.root.view.accessibilityElementsHidden)
        XCTAssertEqual(harness.account.createCallCount, 0)
        XCTAssertEqual(harness.account.deleteCallCount, 0)
    }

    func testGameCenterPresentationWaitsForLaunchAndAppearsAboveLockedGate() async throws {
        let harness = try makeHarness(state: .signInRequired)
        defer { harness.dispose() }
        harness.presenter.start()
        let systemController = UIViewController()
        let gate = try assertGameplayIsLocked(harness)
        let host = try XCTUnwrap(gate.rootViewController)
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        harness.presenter.presentSystemViewController(systemController)

        XCTAssertNil(systemController.presentingViewController)
        XCTAssertTrue(harness.events.systemControllers.isEmpty)
        harness.presenter.launchDidFinish()
        try await waitUntil { systemController.presentingViewController === host }
        _ = try assertGameplayIsLocked(harness)
        XCTAssertTrue(harness.events.systemControllers.isEmpty)
        host.dismiss(animated: false)
    }

    func testGameCenterSheetQueuedBeforeAuthenticationIsDiscardedAfterSuccessfulSignIn() async throws {
        let harness = try makeHarness(state: .loading)
        defer { harness.dispose() }
        harness.presenter.start()
        let systemController = UIViewController()
        harness.presenter.presentSystemViewController(systemController)
        harness.presenter.prepareInitialContent {}

        harness.account.send(.authenticated)
        try await waitUntil { harness.events.prepareCompletions.count == 1 }
        harness.events.prepareCompletions[0]()
        harness.presenter.launchDidFinish()
        await Task.yield()

        XCTAssertNil(systemController.presentingViewController)
        XCTAssertTrue(harness.events.systemControllers.isEmpty)
        XCTAssertNil(visibleGate(in: harness))
    }

    func testStopRestoresExistingInteractionAndAccessibilityFlags() throws {
        for (interactionEnabled, accessibilityHidden) in [(true, false), (false, true)] {
            let harness = try makeHarness(state: .signInRequired)
            defer { harness.dispose() }
            harness.window.isUserInteractionEnabled = interactionEnabled
            harness.root.view.accessibilityElementsHidden = accessibilityHidden
            harness.presenter.start()
            let gate = try assertGameplayIsLocked(harness)

            harness.presenter.stop()

            XCTAssertEqual(harness.window.isUserInteractionEnabled, interactionEnabled)
            XCTAssertEqual(harness.root.view.accessibilityElementsHidden, accessibilityHidden)
            XCTAssertTrue(gate.isHidden)
            XCTAssertNil(gate.rootViewController)
            XCTAssertNil(harness.account.accountAccessStateDidChange)
            XCTAssertNil(visibleGate(in: harness))
        }
    }

    func testAuthenticatedContentStaysInaccessibleUntilOverlappingSplashIsDismissed() async throws {
        let harness = try makeHarness(state: .authenticated)
        defer { harness.dispose() }
        let splash = LaunchOverlayPresenter()
        defer { splash.dismiss(animated: false) }
        harness.presenter.start()
        splash.present(
            in: harness.window,
            appearance: AppAppearanceStore.shared.appearance(compatibleWith: harness.window.traitCollection),
            holdDuration: 60,
            prepareContentForReveal: { harness.presenter.prepareInitialContent(completion: $0) },
            onDismissed: { harness.presenter.launchDidFinish() }
        )
        try await waitUntil { harness.events.prepareCompletions.count == 1 }
        harness.events.prepareCompletions[0]()

        XCTAssertNil(visibleGate(in: harness))
        XCTAssertTrue(harness.root.view.accessibilityElementsHidden)
        XCTAssertFalse(harness.window.isUserInteractionEnabled)

        splash.dismiss(animated: false)

        XCTAssertFalse(harness.root.view.accessibilityElementsHidden)
        XCTAssertTrue(harness.window.isUserInteractionEnabled)
    }

    func testLockedAccountActionOnlyRunsTheExplicitOperationAndNeverAdmitsOnItsOwn() async throws {
        for state in [AppAccountAccessState.deleted, .deletionPending] {
            let harness = try makeHarness(state: state)
            defer { harness.dispose() }
            harness.presenter.start()
            let host = try accountHost(in: harness)

            host.rootView.onPrimaryAction()
            host.rootView.onPrimaryAction()
            try await waitUntil { harness.account.createCallCount + harness.account.deleteCallCount == 1 }

            XCTAssertEqual(harness.account.createCallCount, state == .deleted ? 1 : 0)
            XCTAssertEqual(harness.account.deleteCallCount, state == .deletionPending ? 1 : 0)
            XCTAssertEqual(harness.account.signInCallCount, 0)
            XCTAssertTrue(harness.events.prepareCompletions.isEmpty)
            _ = try assertGameplayIsLocked(harness)
        }
    }

    func testFailedCreateOrDeletionRetryKeepsTheAccountGateLocked() async throws {
        for state in [AppAccountAccessState.deleted, .deletionPending] {
            let harness = try makeHarness(state: state)
            defer { harness.dispose() }
            harness.account.operationError = AccountDeletionError.unavailable
            harness.presenter.start()
            let host = try accountHost(in: harness)

            host.rootView.onPrimaryAction()
            try await waitUntil { host.rootView.model.errorMessage != nil }

            XCTAssertTrue(harness.events.prepareCompletions.isEmpty)
            _ = try assertGameplayIsLocked(harness)
        }
    }

    func testDeletionRetryExplainsWhenOriginalGameCenterAccountIsRequired() async throws {
        let harness = try makeHarness(state: .deletionPending)
        defer { harness.dispose() }
        harness.account.operationError = GameCenterAuthenticationError.playerChanged
        harness.presenter.start()
        let host = try accountHost(in: harness)
        host.rootView.onPrimaryAction()
        try await waitUntil { host.rootView.model.errorMessage != nil }
        XCTAssertEqual(host.rootView.model.errorMessage, L10n.AccountStart.deletionSignInRequired)
        _ = try assertGameplayIsLocked(harness)
    }

    func testStoppingBeforeScheduledAccountActionPreventsTheOperation() async throws {
        for state in [AppAccountAccessState.deleted, .deletionPending] {
            let harness = try makeHarness(state: state)
            defer { harness.dispose() }
            harness.presenter.start()
            let host = try accountHost(in: harness)

            host.rootView.onPrimaryAction()
            harness.presenter.stop()
            await Task.yield()
            await Task.yield()

            XCTAssertEqual(harness.account.createCallCount, 0)
            XCTAssertEqual(harness.account.deleteCallCount, 0)
            XCTAssertNil(visibleGate(in: harness))
        }
    }

    private func accountHost(in harness: AccessPresenterHarness) throws -> UIHostingController<AccountStartView> {
        try XCTUnwrap(visibleGate(in: harness)?.rootViewController as? UIHostingController<AccountStartView>)
    }

    private func makeHarness(state: AppAccountAccessState, connectionTimeout: TimeInterval = 20) throws -> AccessPresenterHarness {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let root = UIViewController()
        root.view.backgroundColor = .systemGreen
        window.rootViewController = root
        window.isHidden = false
        window.layoutIfNeeded()
        let account = AccessPresenterAccountStub(state: state)
        let events = AccessPresenterEvents()
        return AccessPresenterHarness(
            window: window,
            previousKeyWindow: previousKeyWindow,
            root: root,
            account: account,
            events: events,
            presenter: makePresenter(window: window, account: account, events: events, connectionTimeout: connectionTimeout)
        )
    }

    private func makePresenter(
        window: UIWindow,
        account: AccessPresenterAccountStub,
        events: AccessPresenterEvents,
        connectionTimeout: TimeInterval = 20
    ) -> AppAccountAccessPresenter {
        AppAccountAccessPresenter(
            window: window,
            accessProvider: account,
            accountManager: account,
            prepareContentForReveal: { events.prepareCompletions.append($0) },
            resetContent: { events.resetCompletions.append($0) },
            presentSystemContent: { events.systemControllers.append($0) },
            waitForConnectionTimeout: { try await Task.sleep(nanoseconds: UInt64(connectionTimeout * 1_000_000_000)) }
        )
    }

    @discardableResult
    private func assertGameplayIsLocked(
        _ harness: AccessPresenterHarness,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> UIWindow {
        XCTAssertFalse(harness.window.isUserInteractionEnabled, file: file, line: line)
        XCTAssertTrue(harness.root.view.accessibilityElementsHidden, file: file, line: line)
        return try XCTUnwrap(visibleGate(in: harness), file: file, line: line)
    }

    private func visibleGate(in harness: AccessPresenterHarness) -> UIWindow? {
        harness.window.windowScene?.windows.first {
            $0 !== harness.window
                && $0.accessibilityIdentifier == AppAccountAccessPresenter.accessibilityIdentifier
                && !$0.isHidden
        }
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for account access presentation", file: file, line: line)
                throw AccessPresenterWaitError.timeout
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private enum AccessPresenterWaitError: Error {
    case timeout
}

@MainActor
private struct AccessPresenterHarness {
    let window: UIWindow
    let previousKeyWindow: UIWindow?
    let root: UIViewController
    let account: AccessPresenterAccountStub
    let events: AccessPresenterEvents
    let presenter: AppAccountAccessPresenter

    func dispose() {
        presenter.stop()
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
    }
}

@MainActor
private final class AccessPresenterEvents {
    var prepareCompletions: [() -> Void] = []
    var resetCompletions: [() -> Void] = []
    var systemControllers: [UIViewController] = []
}

@MainActor
private final class AccessPresenterAccountStub: AppAccountAccessProviding, AccountManaging {
    private(set) var accountAccessState: AppAccountAccessState
    var authenticatedAccountID: String?
    var needsGameCenterSignIn = true
    var accountAccessStateDidChange: ((AppAccountAccessState) -> Void)?
    private(set) var createCallCount = 0
    private(set) var deleteCallCount = 0
    private(set) var signInCallCount = 0
    var operationError: Error?

    var accountDeletionAvailable: Bool {
        accountAccessState == .authenticated || accountAccessState == .deletionPending
    }

    var canCreateAccount: Bool { accountAccessState == .deleted }

    init(state: AppAccountAccessState) {
        accountAccessState = state
    }

    func send(_ state: AppAccountAccessState) {
        accountAccessState = state
        accountAccessStateDidChange?(state)
    }

    func signIn(present: @escaping (UIViewController) -> Void) {
        signInCallCount += 1
    }

    func deleteAccount() async throws {
        deleteCallCount += 1
        if let operationError { throw operationError }
    }

    func createAccount() async throws {
        createCallCount += 1
        if let operationError { throw operationError }
    }
}
