import SwiftUI
import UIKit
import XCTest
@testable import Quizice

@MainActor
final class SceneLaunchTests: QuizFlowCoordinatorTestCase {
    func testSceneKeepsSilentBackendAuthenticationUnderSplashAfterCatalogIsReady() async throws {
        UIView.setAnimationsEnabled(false)
        let harness = try makeSceneLaunchHarness()
        let catalogLoaded = expectation(description: "Catalog loads while Game Center is unresolved")
        harness.repository.onRefresh = { catalogLoaded.fulfill() }
        let backendStarted = expectation(description: "Backend authentication starts")
        let response = SuspendedAuthSessionResponse(onSuspend: { backendStarted.fulfill() })
        harness.api.authenticationHandler = { _ in try await response.wait() }
        addTeardownBlock { await response.resume(with: Self.launchSession) }
        harness.scene.startLaunch(
            in: harness.window, coordinator: harness.coordinator,
            authenticationService: harness.authentication,
            appearance: makeLaunchAppearance(designStyle: .classic)
        )

        let overlay = try XCTUnwrap(launchOverlay(in: harness.window))
        XCTAssertEqual(harness.gameCenter.startCount, 1)
        await fulfillment(of: [catalogLoaded], timeout: 2)
        XCTAssertEqual(harness.authentication.state, .initializing)
        harness.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))
        await fulfillment(of: [backendStarted], timeout: 2)

        // Pass the normal minimum hold with animations disabled. A catalog-only
        // readiness check would reveal the loading account gate at this point.
        try await Task.sleep(nanoseconds: 1_300_000_000)
        XCTAssertFalse(overlay.isHidden)
        XCTAssertEqual(overlay.alpha, 1)
        XCTAssertEqual(harness.authentication.accountAccessState, .loading)

        await response.resume(with: Self.launchSession)
        try await waitForSceneLaunch { overlay.isHidden }

        XCTAssertEqual(harness.authentication.accountAccessState, .authenticated)
        XCTAssertEqual(harness.repository.refreshCount, 1)
        XCTAssertNil(accountGate(in: harness.window))
        XCTAssertTrue(harness.window.isUserInteractionEnabled)
        XCTAssertFalse(harness.navigationController.view.accessibilityElementsHidden)
        XCTAssertNil(harness.navigationController.presentedViewController)
    }

    func testSceneImmediatelyRevealsRequiredGameCenterUIAboveLockedAccountGate() async throws {
        UIView.setAnimationsEnabled(false)
        let harness = try makeSceneLaunchHarness(needsOnboarding: true)
        let catalogLoaded = expectation(description: "Catalog survives the early splash dismissal")
        harness.repository.onRefresh = { catalogLoaded.fulfill() }
        harness.scene.startLaunch(
            in: harness.window, coordinator: harness.coordinator,
            authenticationService: harness.authentication,
            appearance: makeLaunchAppearance(designStyle: .classic)
        )
        let overlay = try XCTUnwrap(launchOverlay(in: harness.window))
        let gate = try XCTUnwrap(accountGate(in: harness.window))
        let host = try XCTUnwrap(gate.rootViewController)
        let signIn = UIViewController()

        harness.gameCenter.requestPresentation(signIn)

        XCTAssertTrue(overlay.isHidden)
        XCTAssertTrue(gate.isKeyWindow)
        XCTAssertFalse(harness.window.isUserInteractionEnabled)
        XCTAssertTrue(harness.navigationController.view.accessibilityElementsHidden)
        XCTAssertNil(harness.navigationController.presentedViewController)
        try await waitForSceneLaunch {
            signIn.presentingViewController === host
                && signIn.viewIfLoaded?.window === gate
                && !signIn.isBeingPresented
        }
        XCTAssertTrue(signIn.view.window === gate)
        await fulfillment(of: [catalogLoaded], timeout: 2)
        XCTAssertEqual(harness.authentication.accountAccessState, .loading)

        await withCheckedContinuation { continuation in
            signIn.dismiss(animated: false) { continuation.resume() }
        }
        harness.gameCenter.emit(.unavailable)
        try await waitForSceneLaunch { harness.authentication.accountAccessState == .signInRequired }
        XCTAssertNotNil(accountGate(in: harness.window))
        XCTAssertFalse(harness.window.isUserInteractionEnabled)
        XCTAssertNil(harness.navigationController.presentedViewController)
    }

    func testSceneLaunchDeadlineRevealsLockedGateAndAcceptsLateAuthentication() async throws {
        UIView.setAnimationsEnabled(false)
        let harness = try makeSceneLaunchHarness()
        harness.scene.startLaunch(
            in: harness.window, coordinator: harness.coordinator,
            authenticationService: harness.authentication,
            appearance: makeLaunchAppearance(designStyle: .classic)
        )
        let overlay = try XCTUnwrap(launchOverlay(in: harness.window))
        try await waitForSceneLaunch { overlay.isHidden }

        XCTAssertEqual(harness.authentication.state, .initializing)
        XCTAssertEqual(harness.repository.refreshCount, 1)
        let gate = try XCTUnwrap(accountGate(in: harness.window))
        let host = try XCTUnwrap(gate.rootViewController)
        XCTAssertTrue(gate.isKeyWindow)
        XCTAssertFalse(harness.window.isUserInteractionEnabled)
        XCTAssertTrue(harness.navigationController.view.accessibilityElementsHidden)

        let signIn = UIViewController()
        harness.gameCenter.requestPresentation(signIn)
        try await waitForSceneLaunch {
            signIn.presentingViewController === host
                && signIn.viewIfLoaded?.window === gate
                && !signIn.isBeingPresented
        }
        await withCheckedContinuation { continuation in
            signIn.dismiss(animated: false) { continuation.resume() }
        }
        harness.gameCenter.emit(.authenticated(teamPlayerID: "team-1"))
        try await waitForSceneLaunch {
            harness.authentication.accountAccessState == .authenticated
                && self.accountGate(in: harness.window) == nil
        }

        XCTAssertTrue(overlay.isHidden)
        XCTAssertEqual(harness.gameCenter.startCount, 1)
        XCTAssertTrue(harness.window.isUserInteractionEnabled)
        XCTAssertFalse(harness.navigationController.view.accessibilityElementsHidden)
    }

    private static var launchSession: AuthSession {
        AuthSession(
            userID: "user-1", accessToken: "access-token",
            expiresAt: Date(timeIntervalSince1970: 4_000_000_000), teamPlayerID: "team-1"
        )
    }

    private func launchOverlay(in window: UIWindow) -> UIWindow? {
        window.windowScene?.windows.first {
            $0.accessibilityIdentifier == LaunchOverlayPresenter.accessibilityIdentifier && !$0.isHidden
        }
    }

    private func accountGate(in window: UIWindow) -> UIWindow? {
        window.windowScene?.windows.first {
            $0.accessibilityIdentifier == AppAccountAccessPresenter.accessibilityIdentifier && !$0.isHidden
        }
    }

    private func waitForSceneLaunch(
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for scene launch", file: file, line: line)
                throw SceneLaunchWaitError.timeout
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func makeSceneLaunchHarness(needsOnboarding: Bool = false) throws -> (
        scene: SceneDelegate, window: UIWindow, coordinator: QuizFlowCoordinator,
        navigationController: UINavigationController, authentication: GameCenterAuthenticationService,
        gameCenter: FakeGameCenterClient, api: FakeAuthAPI, repository: LaunchCatalogRepository
    ) {
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = windowScene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: windowScene)
        let scene = SceneDelegate()
        let defaultsName = "SceneLaunchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        let onboarding = OnboardingProgressStore(userDefaults: defaults)
        if !needsOnboarding { onboarding.complete(preferredThemeIDs: []) }
        let notifications = NotificationCenter()
        let gameCenter = FakeGameCenterClient()
        let api = FakeAuthAPI()
        let authentication = GameCenterAuthenticationService(
            gameCenter: gameCenter, api: api, sessionStore: MemorySessionStore(),
            statisticsStore: StatisticsStore(userDefaults: defaults, notificationCenter: notifications),
            bundleIdentifier: "ru.avtabenskiy.Quizice", notificationCenter: notifications,
            deletionStateStore: AccountDeletionStateStore(defaults: defaults)
        )
        let repository = LaunchCatalogRepository()
        let navigation = UINavigationController()
        let coordinator = QuizFlowCoordinator(
            window: window, navigationController: navigation,
            themeRepository: repository, session: RoutingSession(),
            aiQuizThemeService: MockAIQuizThemeService(),
            onboardingProgressStore: onboarding, notificationCenter: notifications
        )
        coordinator.start()
        addTeardownBlock { @MainActor in
            scene.sceneDidDisconnect(windowScene)
            navigation.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
            defaults.removePersistentDomain(forName: defaultsName)
        }
        return (scene, window, coordinator, navigation, authentication, gameCenter, api, repository)
    }

}

private enum SceneLaunchWaitError: Error {
    case timeout
}

private final class LaunchCatalogRepository: ThemeRepository {
    var themes: [QuizTheme]? = []
    private(set) var refreshCount = 0
    var onRefresh: (() -> Void)?

    func loadData(forceReload: Bool) {}
    func fetchQuizThemes() -> [QuizTheme] { [] }
    func refreshBackendCatalog(locale: String) async -> Bool {
        refreshCount += 1
        let refreshed = onRefresh
        onRefresh = nil
        refreshed?()
        return false
    }
}
