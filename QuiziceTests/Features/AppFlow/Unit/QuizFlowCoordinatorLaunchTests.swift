import SwiftUI
import UIKit
import XCTest
@testable import Quizice

@MainActor
final class QuizFlowCoordinatorLaunchTests: QuizFlowCoordinatorTestCase {
    func testProvisionedDebugAccountUsesServerAIAndItsAccessState() {
        let backendAccess = BackendAIQuizAccessStub(isAvailable: false)
        let dependencies = AIQuizRuntimeDependencies.live(
            backendConfiguration: .init(baseURL: URL(string: "https://example.com/api")!),
            backendAccessProvider: backendAccess,
            usesDebugBackendAuthentication: true
        )
        XCTAssertTrue(dependencies.themeService is BackendAIQuizThemeService)
        XCTAssertTrue(dependencies.accessProvider === backendAccess)
        XCTAssertFalse(dependencies.accessProvider.isAIQuizAvailable)
    }

    func testDebugSimulatorAIRuntimeUsesDirectServiceWithoutBackendAccess() {
        let backendAccess = BackendAIQuizAccessStub(isAvailable: false)

        let dependencies = AIQuizRuntimeDependencies.resolve(
            usesDirectAI: true,
            backendConfiguration: BackendConfiguration(
                baseURL: URL(string: "https://example.com/api")!
            ),
            backendAccessProvider: backendAccess,
            directAPIKeyProvider: { "test-api-key" },
            directUnauthorizedHandler: {}
        )

        XCTAssertTrue(dependencies.accessProvider.isAIQuizAvailable)
        XCTAssertTrue(dependencies.themeService is YandexAIQuizThemeService)
        XCTAssertFalse(backendAccess.isAIQuizAvailable)
    }

    func testDeviceAIRuntimePreservesBackendAccessAndUsesBackendService() {
        let backendAccess = BackendAIQuizAccessStub(isAvailable: false)

        let dependencies = AIQuizRuntimeDependencies.resolve(
            usesDirectAI: false,
            backendConfiguration: BackendConfiguration(
                baseURL: URL(string: "https://example.com/api")!
            ),
            backendAccessProvider: backendAccess,
            directAPIKeyProvider: {
                XCTFail("Device path must not read a direct API key")
                return nil
            },
            directUnauthorizedHandler: {
                XCTFail("Device path must not manage a direct API key")
            }
        )

        XCTAssertTrue(dependencies.accessProvider === backendAccess)
        XCTAssertTrue(dependencies.themeService is BackendAIQuizThemeService)
        XCTAssertFalse(dependencies.accessProvider.isAIQuizAvailable)
    }

    func testStartInstallsHomeControllerAsNavigationRoot() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let navigationController = RoutingNavigationControllerSpy()
        let session = RoutingSession()
        let coordinator = QuizFlowCoordinator(
            window: window,
            navigationController: navigationController,
            themeRepository: RoutingThemeRepository(themes: []),
            session: session
        )

        coordinator.start()

        XCTAssertTrue(window.rootViewController === navigationController)
        XCTAssertTrue(navigationController.viewControllers.first is QuizViewController)
        XCTAssertTrue(navigationController.isNavigationBarHidden)
    }

    func testLaunchOverlayPresenterInstallsAndRemovesFakeLaunchAboveRoot() throws {
        let windowScene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: windowScene)
        let rootViewController = UINavigationController(rootViewController: UIViewController())
        window.rootViewController = rootViewController
        let presenter = LaunchOverlayPresenter()
        let appearance = makeLaunchAppearance(designStyle: .radar)
        defer {
            presenter.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
        }

        presenter.present(in: window, appearance: appearance, holdDuration: 60)

        let overlayWindow = try XCTUnwrap(
            windowScene.windows.first {
                $0.accessibilityIdentifier == LaunchOverlayPresenter.accessibilityIdentifier
                    && !$0.isHidden
            }
        )
        XCTAssertFalse(overlayWindow.isKeyWindow)
        XCTAssertEqual(overlayWindow.windowLevel.rawValue, window.windowLevel.rawValue + 1)
        let hostingController = try XCTUnwrap(
            overlayWindow.rootViewController as? UIHostingController<FakeLaunchScreenView>
        )
        XCTAssertEqual(hostingController.rootView.appearance.designStyle, .radar)
        assertColor(overlayWindow.backgroundColor, equals: .black)
        assertColor(hostingController.view.backgroundColor, equals: .black)
        XCTAssertTrue(rootViewController.view.accessibilityElementsHidden)
        XCTAssertEqual(rootViewController.children.count, 1)

        presenter.dismiss(animated: false)

        XCTAssertTrue(overlayWindow.isHidden)
        XCTAssertNil(overlayWindow.rootViewController)
        XCTAssertFalse(rootViewController.view.accessibilityElementsHidden)
        XCTAssertEqual(rootViewController.children.count, 1)
    }

    func testLaunchOverlayPresenterAutomaticallyRevealsHomeAndRestoresAccessibility() async throws {
        let windowScene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: windowScene)
        let rootViewController = UIViewController()
        window.rootViewController = rootViewController
        window.isHidden = false
        let presenter = LaunchOverlayPresenter()
        let appearance = makeLaunchAppearance(designStyle: .radar)
        defer {
            presenter.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
        }

        presenter.present(
            in: window,
            appearance: appearance,
            holdDuration: 0,
            motion: FakeLaunchMotion(logoZoomScale: 42, logoZoomDuration: 0.05)
        )

        let overlayWindow = try XCTUnwrap(
            windowScene.windows.first {
                $0.accessibilityIdentifier == LaunchOverlayPresenter.accessibilityIdentifier
            }
        )
        let dismissalExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                overlayWindow.isHidden && overlayWindow.rootViewController == nil
            },
            object: nil
        )

        await fulfillment(of: [dismissalExpectation], timeout: 2)

        XCTAssertFalse(rootViewController.view.accessibilityElementsHidden)
    }

    func testLaunchOverlayWaitsForCatalogPreparationBeforeRevealingContent() async throws {
        let windowScene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIViewController()
        window.isHidden = false
        let presenter = LaunchOverlayPresenter()
        let preparationStarted = expectation(description: "Catalog preparation starts")
        var preparationContinuation: CheckedContinuation<Void, Never>?
        defer {
            preparationContinuation?.resume()
            presenter.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
        }

        presenter.present(
            in: window,
            appearance: makeLaunchAppearance(designStyle: .classic),
            holdDuration: 0,
            motion: FakeLaunchMotion(logoZoomScale: 42, logoZoomDuration: 0.01),
            preparation: {
                preparationStarted.fulfill()
                await withCheckedContinuation { continuation in
                    preparationContinuation = continuation
                }
            }
        )

        let overlayWindow = try XCTUnwrap(
            windowScene.windows.first {
                $0.accessibilityIdentifier == LaunchOverlayPresenter.accessibilityIdentifier
                    && !$0.isHidden
            }
        )
        await fulfillment(of: [preparationStarted], timeout: 1)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(overlayWindow.isHidden)
        XCTAssertNotNil(overlayWindow.rootViewController)

        preparationContinuation?.resume()
        preparationContinuation = nil
        let dismissalExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in overlayWindow.isHidden },
            object: nil
        )
        await fulfillment(of: [dismissalExpectation], timeout: 2)
    }

    func testLaunchKeepsSplashOpaqueUntilInitialContentFinishesPresentation() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let root = UIViewController()
        window.rootViewController = root
        window.isHidden = false
        let presenter = LaunchOverlayPresenter()
        let contentPreparationStarted = expectation(description: "Initial content preparation started")
        let dismissed = expectation(description: "Prepared content revealed once")
        dismissed.assertForOverFulfill = true
        var finishContentPreparation: (() -> Void)?
        var didPrepareCatalog = false
        var didDismiss = false
        UIView.setAnimationsEnabled(false)
        defer {
            presenter.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
        }

        presenter.present(
            in: window,
            appearance: makeLaunchAppearance(designStyle: .classic),
            holdDuration: 0,
            preparation: { didPrepareCatalog = true },
            prepareContentForReveal: { completion in
                XCTAssertTrue(didPrepareCatalog)
                finishContentPreparation = completion
                contentPreparationStarted.fulfill()
            },
            onDismissed: { didDismiss = true; dismissed.fulfill() }
        )

        await fulfillment(of: [contentPreparationStarted], timeout: 5)
        let overlay = try XCTUnwrap(scene.windows.first {
            $0.accessibilityIdentifier == LaunchOverlayPresenter.accessibilityIdentifier && !$0.isHidden
        })
        XCTAssertEqual(overlay.alpha, 1)
        XCTAssertTrue(root.view.accessibilityElementsHidden)
        XCTAssertFalse(didDismiss)

        let finish = try XCTUnwrap(finishContentPreparation)
        finish()
        finish()
        await fulfillment(of: [dismissed], timeout: 5)
        XCTAssertTrue(overlay.isHidden)
        XCTAssertFalse(root.view.accessibilityElementsHidden)
    }

    func testLaunchPreparationTimeoutRevealsContentAndIgnoresLateCompletion() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let root = UIViewController()
        window.rootViewController = root
        window.isHidden = false
        let presenter = LaunchOverlayPresenter()
        var continuation: CheckedContinuation<Void, Never>?
        var finishContentPreparation: (() -> Void)?
        var contentPreparationCount = 0
        let started = expectation(description: "Preparation started")
        let preparingContent = expectation(description: "Deadline prepares initial screen before revealing it")
        preparingContent.assertForOverFulfill = true
        let latePreparationReturned = expectation(description: "Cancelled transport returned late")
        let dismissed = expectation(description: "Launch dismissed once")
        dismissed.assertForOverFulfill = true
        var dismissalCount = 0
        UIView.setAnimationsEnabled(false)
        defer {
            continuation?.resume()
            presenter.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
        }
        presenter.present(
            // The network deadline bypasses hold and zoom, but must still wait
            // for the first screen to finish its UIKit presentation.
            in: window, appearance: makeLaunchAppearance(designStyle: .classic), holdDuration: 60,
            motion: FakeLaunchMotion(logoZoomScale: 42, logoZoomDuration: 60),
            preparationTimeout: 0.05,
            preparation: {
                started.fulfill()
                await withCheckedContinuation { continuation = $0 }
                latePreparationReturned.fulfill()
            },
            prepareContentForReveal: { completion in
                contentPreparationCount += 1
                finishContentPreparation = completion
                preparingContent.fulfill()
            },
            onDismissed: { dismissalCount += 1; dismissed.fulfill() }
        )
        await fulfillment(of: [started, preparingContent], timeout: 5)
        let overlay = try XCTUnwrap(scene.windows.first {
            $0.accessibilityIdentifier == LaunchOverlayPresenter.accessibilityIdentifier && !$0.isHidden
        })
        XCTAssertEqual(overlay.alpha, 1)
        XCTAssertTrue(root.view.accessibilityElementsHidden)
        XCTAssertEqual(dismissalCount, 0)

        continuation?.resume()
        continuation = nil
        await fulfillment(of: [latePreparationReturned], timeout: 5)
        await Task.yield()
        XCTAssertEqual(contentPreparationCount, 1)
        XCTAssertEqual(dismissalCount, 0)

        let finish = try XCTUnwrap(finishContentPreparation)
        finish()
        finish()
        await fulfillment(of: [dismissed], timeout: 5)
        XCTAssertFalse(root.view.accessibilityElementsHidden)
        XCTAssertTrue(overlay.isHidden)
        XCTAssertEqual(dismissalCount, 1)
    }

    func testLateContentPreparationCannotDismissReplacementLaunchOverlay() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.isHidden = false
        let presenter = LaunchOverlayPresenter()
        var finishOldPreparation: (() -> Void)?
        let preparingContent = expectation(description: "Original launch prepares initial content")
        defer {
            presenter.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
        }
        presenter.present(
            in: window,
            appearance: makeLaunchAppearance(designStyle: .classic),
            holdDuration: 0,
            prepareContentForReveal: { completion in
                finishOldPreparation = completion
                preparingContent.fulfill()
            }
        )
        await fulfillment(of: [preparingContent], timeout: 5)
        presenter.dismiss(animated: false)
        presenter.present(
            in: window,
            appearance: makeLaunchAppearance(designStyle: .classic),
            holdDuration: 60
        )
        let replacementOverlay = try XCTUnwrap(scene.windows.first {
            $0.accessibilityIdentifier == LaunchOverlayPresenter.accessibilityIdentifier && !$0.isHidden
        })

        try XCTUnwrap(finishOldPreparation)()
        await Task.yield()

        XCTAssertFalse(replacementOverlay.isHidden)
        XCTAssertEqual(replacementOverlay.alpha, 1)
        XCTAssertNotNil(replacementOverlay.rootViewController)
        XCTAssertTrue(try XCTUnwrap(window.rootViewController).view.accessibilityElementsHidden)
    }

    func testDefaultLaunchDeadlineCancelsSlowPreparationAndRevealsHome() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let root = UIViewController()
        window.rootViewController = root
        window.isHidden = false
        let timeoutScheduled = expectation(description: "Default launch timeout scheduled")
        var timeoutContinuation: CheckedContinuation<Void, Never>?
        let presenter = LaunchOverlayPresenter(waitForPreparationTimeout: { duration in
            XCTAssertEqual(duration, 2)
            await withCheckedContinuation {
                timeoutContinuation = $0
                timeoutScheduled.fulfill()
            }
        })
        let started = expectation(description: "Slow request started")
        let cancelled = expectation(description: "Slow request cancelled")
        let dismissed = expectation(description: "Home revealed within launch budget")
        var didCancel = false
        var didDismiss = false
        // Animation timing is covered separately; this test controls the network deadline.
        UIView.setAnimationsEnabled(false)
        defer {
            presenter.dismiss(animated: false)
            timeoutContinuation?.resume()
            window.isHidden = true
            window.rootViewController = nil
        }

        presenter.present(
            in: window,
            appearance: makeLaunchAppearance(designStyle: .classic),
            preparation: {
                started.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                    XCTFail("Launch must not wait for the transport timeout")
                } catch {
                    XCTAssertTrue(Task.isCancelled)
                    didCancel = true
                    cancelled.fulfill()
                }
            },
            onDismissed: { didDismiss = true; dismissed.fulfill() }
        )

        await fulfillment(of: [started, timeoutScheduled], timeout: 5)
        XCTAssertFalse(didCancel)
        XCTAssertFalse(didDismiss)
        XCTAssertTrue(root.view.accessibilityElementsHidden)

        let deadline = try XCTUnwrap(timeoutContinuation)
        timeoutContinuation = nil
        deadline.resume()

        await fulfillment(of: [cancelled, dismissed], timeout: 5)
        XCTAssertFalse(root.view.accessibilityElementsHidden)
    }

    func testFakeLaunchDoesNotStartCompletionBeforeCatalogIsReady() async throws {
        let windowScene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: windowScene)
        let readiness = FakeLaunchReadiness(isReady: false)
        let completionExpectation = expectation(description: "Fake launch completes after catalog")
        completionExpectation.assertForOverFulfill = true
        var completionStyle: FakeLaunchCompletionStyle?
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        let rootView = FakeLaunchScreenView(
            appearance: makeLaunchAppearance(designStyle: .classic),
            holdDuration: 0,
            readiness: readiness
        ) { style in
            completionStyle = style
            completionExpectation.fulfill()
        }
        window.rootViewController = UIHostingController(rootView: rootView)
        window.isHidden = false
        defer {
            UIView.setAnimationsEnabled(animationsWereEnabled)
            window.isHidden = true
            window.rootViewController = nil
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(completionStyle)

        readiness.isReady = true
        await fulfillment(of: [completionExpectation], timeout: 2)

        XCTAssertEqual(completionStyle, .crossfade)
    }

    func testFakeLaunchUsesCrossfadeCompletionWhenAnimationsAreDisabled() async throws {
        let windowScene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: windowScene)
        let completionExpectation = expectation(description: "Fake launch completes without zoom")
        var completionStyle: FakeLaunchCompletionStyle?
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        let appearance = makeLaunchAppearance(designStyle: .classic)
        let rootView = FakeLaunchScreenView(
            appearance: appearance,
            holdDuration: 0,
            motion: FakeLaunchMotion(logoZoomScale: 42, logoZoomDuration: 0.01)
        ) { style in
            completionStyle = style
            completionExpectation.fulfill()
        }
        let viewController = UIHostingController(rootView: rootView)
        window.rootViewController = viewController
        window.isHidden = false
        defer {
            UIView.setAnimationsEnabled(animationsWereEnabled)
            window.isHidden = true
            window.rootViewController = nil
        }

        await fulfillment(of: [completionExpectation], timeout: 3)

        XCTAssertEqual(completionStyle, .crossfade)
    }

    func testStaleLaunchFadeDoesNotRemoveAReplacementOverlay() async throws {
        let windowScene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: windowScene)
        let rootViewController = UIViewController()
        window.rootViewController = rootViewController
        let presenter = LaunchOverlayPresenter()
        let appearance = makeLaunchAppearance(designStyle: .classic)
        defer {
            presenter.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
        }

        presenter.present(in: window, appearance: appearance, holdDuration: 60)
        let firstOverlay = try XCTUnwrap(
            windowScene.windows.first {
                $0.accessibilityIdentifier == LaunchOverlayPresenter.accessibilityIdentifier
            }
        )

        presenter.dismiss()
        presenter.dismiss(animated: false)
        presenter.present(in: window, appearance: appearance, holdDuration: 60)

        let replacementOverlay = try XCTUnwrap(
            windowScene.windows.first {
                $0 !== firstOverlay
                    && $0.accessibilityIdentifier == LaunchOverlayPresenter.accessibilityIdentifier
                    && !$0.isHidden
            }
        )
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertFalse(replacementOverlay.isHidden)
        XCTAssertNotNil(replacementOverlay.rootViewController)
        XCTAssertTrue(rootViewController.view.accessibilityElementsHidden)
    }

    func testFakeLaunchVisualStyleMatchesSelectedDesignAndColorScheme() throws {
        let classicAppearance = makeLaunchAppearance(designStyle: .classic)
        let classicStyle = FakeLaunchVisualStyle(appearance: classicAppearance)
        XCTAssertEqual(classicStyle.markStyle, .classicImage)
        XCTAssertTrue(classicStyle.revealsAppBackground)
        XCTAssertNil(classicStyle.foregroundColor)
        assertColor(classicStyle.backgroundColor, equals: UIColor(hex: 0x111620))

        let radarAppearance = makeLaunchAppearance(designStyle: .radar)
        let radarStyle = FakeLaunchVisualStyle(appearance: radarAppearance)
        XCTAssertEqual(radarStyle.markStyle, .radarText)
        XCTAssertFalse(radarStyle.revealsAppBackground)
        assertColor(radarStyle.backgroundColor, equals: .black)
        assertColor(
            try XCTUnwrap(radarStyle.foregroundColor),
            equals: radarAppearance.accentColor
        )

        let cleanLightAppearance = makeLaunchAppearance(
            designStyle: .clean,
            cleanColorSchemePreference: .light
        )
        let cleanLightStyle = FakeLaunchVisualStyle(appearance: cleanLightAppearance)
        XCTAssertEqual(cleanLightStyle.markStyle, .cleanText)
        XCTAssertFalse(cleanLightStyle.revealsAppBackground)
        assertColor(cleanLightStyle.backgroundColor, equals: .white)
        assertColor(try XCTUnwrap(cleanLightStyle.foregroundColor), equals: .black)

        let cleanDarkAppearance = makeLaunchAppearance(
            designStyle: .clean,
            cleanColorSchemePreference: .dark
        )
        let cleanDarkStyle = FakeLaunchVisualStyle(appearance: cleanDarkAppearance)
        XCTAssertEqual(cleanDarkStyle.markStyle, .cleanText)
        XCTAssertFalse(cleanDarkStyle.revealsAppBackground)
        assertColor(cleanDarkStyle.backgroundColor, equals: .black)
        assertColor(try XCTUnwrap(cleanDarkStyle.foregroundColor), equals: .white)
    }

    func testLaunchStoryboardMatchesFakeLaunchBaseGeometryAndColor() throws {
        let viewController = try XCTUnwrap(
            UIStoryboard(name: "LaunchScreen", bundle: nil).instantiateInitialViewController()
        )
        let logoImageView = try XCTUnwrap(
            viewController.view.subviews.compactMap { $0 as? UIImageView }.first
        )
        let backgroundColor = try XCTUnwrap(viewController.view.backgroundColor)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        XCTAssertTrue(backgroundColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual(red, 17.0 / 255.0, accuracy: 0.000_001)
        XCTAssertEqual(green, 22.0 / 255.0, accuracy: 0.000_001)
        XCTAssertEqual(blue, 32.0 / 255.0, accuracy: 0.000_001)
        XCTAssertEqual(alpha, 1, accuracy: 0.000_001)

        let pixelTolerance = 1 / UIScreen.main.scale
        for size in [
            CGSize(width: 320, height: 568),
            CGSize(width: 393, height: 852),
            CGSize(width: 600, height: 1_000)
        ] {
            viewController.view.frame = CGRect(origin: .zero, size: size)
            viewController.view.setNeedsLayout()
            viewController.view.layoutIfNeeded()

            XCTAssertEqual(logoImageView.frame.midX, size.width / 2, accuracy: 0.01)
            XCTAssertEqual(logoImageView.frame.midY, size.height / 2, accuracy: 0.01)
            let expectedWidth = min(size.width * 0.7, 360)
            let expectedHeight = expectedWidth * 399 / 742
            XCTAssertEqual(logoImageView.frame.width, expectedWidth, accuracy: pixelTolerance)
            XCTAssertEqual(logoImageView.frame.height, expectedHeight, accuracy: pixelTolerance)
        }
    }
}
