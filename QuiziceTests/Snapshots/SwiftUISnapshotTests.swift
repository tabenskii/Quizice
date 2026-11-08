import SwiftUI
import UIKit
import XCTest
import SnapshotTesting
@testable import Quizice

@MainActor
final class SwiftUISnapshotTests: XCTestCase {
    private var onboardingThemes: [OnboardingTheme] {
        [
            OnboardingTheme(
                id: "music",
                title: L10n.Onboarding.topicMusic,
                sfSymbolName: "music.note.list",
                emoji: "🎵",
                colorHex: "#FF8252"
            ),
            OnboardingTheme(
                id: "technology",
                title: L10n.Onboarding.topicTechnology,
                sfSymbolName: "cpu.fill",
                emoji: "💻",
                colorHex: "#62A2E6"
            ),
            OnboardingTheme(
                id: "history_culture",
                title: L10n.Onboarding.topicHistoryCulture,
                sfSymbolName: "theatermask.and.paintbrush.fill",
                emoji: "🏛️",
                colorHex: "#8B5CF6"
            ),
            OnboardingTheme(
                id: "politics_business",
                title: L10n.Onboarding.topicPoliticsBusiness,
                sfSymbolName: "briefcase.fill",
                emoji: "💼",
                colorHex: "#F2C94C"
            )
        ]
    }

    override func setUp() {
        super.setUp()
        SnapshotSupport.setUp(designStyle: .clean, cleanColorScheme: .light)
    }

    override func tearDown() {
        SnapshotSupport.tearDown()
        super.tearDown()
    }

    func testIPadSettingsSnapshot() {
        SnapshotSupport.assertScreen(makeHostingController(rootView: QuizSettingsView()),
            named: "clean-ipad-settings", device: SnapshotSupport.iPadPortrait, afterPrepare: prepareSettingsSnapshot)
    }

    func testIPadOnboardingSnapshots() {
        for device in [SnapshotSupport.iPadPortrait, SnapshotSupport.iPadShortWindow] {
            let controller = makeHostingController(rootView: QuizOnboardingView(
                appearance: SnapshotSupport.appearance(designStyle: .clean, cleanColorScheme: .light),
                themes: onboardingThemes, onComplete: { _ in }
            ))
            SnapshotSupport.assertScreen(controller, named: "clean-ipad-onboarding-\(Int(device.size!.width))", device: device)
        }
    }

    func testSettingsViewSnapshot() {
        let viewController = makeHostingController(rootView: QuizSettingsView())

        SnapshotSupport.assertScreen(
            viewController,
            named: "clean-settings",
            afterPrepare: prepareSettingsSnapshot
        )
    }

    func testClassicSettingsCompactPortraitSnapshot() {
        SnapshotSupport.setUp(designStyle: .classic)
        let viewController = makeHostingController(rootView: QuizSettingsView())

        SnapshotSupport.assertScreen(
            viewController,
            named: "classic-settings-iphone-se",
            device: .iPhone8,
            afterPrepare: prepareSettingsSnapshot
        )
    }

    func testSignedInSettingsAccountSnapshot() {
        let viewController = SettingsBottomSnapshotHostingController(rootView: QuizSettingsView(
            accountManager: SettingsSnapshotAccountManager(),
            personalizedRepeatsAvailable: { true }
        ))
        viewController.view.overrideUserInterfaceStyle = .light

        SnapshotSupport.assertScreen(
            viewController,
            named: "clean-settings-delete-account"
        )
    }

    func testSettingsPrivacyPolicyCompactSnapshot() {
        let viewController = SettingsBottomSnapshotHostingController(rootView: QuizSettingsView(
            personalizedRepeatsAvailable: { false }
        ))
        viewController.view.overrideUserInterfaceStyle = .light

        SnapshotSupport.assertScreen(
            viewController,
            named: "clean-settings-privacy-iphone-se",
            device: .iPhone8
        )
    }

    func testAccountDeletedStartScreenSnapshot() {
        SnapshotSupport.setUp(designStyle: .classic)
        let viewController = makeHostingController(rootView: AccountStartView(
            model: AccountStartModel(state: .deleted),
            appearance: SnapshotSupport.appearance(designStyle: .classic),
            onPrimaryAction: {}
        ))

        SnapshotSupport.assertScreen(viewController, named: "classic-account-deleted")
    }

    func testAccountSignInCompactSnapshot() {
        let viewController = makeHostingController(rootView: AccountStartView(
            model: AccountStartModel(state: .signInRequired),
            appearance: SnapshotSupport.appearance(designStyle: .clean),
            onPrimaryAction: {}
        ))

        SnapshotSupport.assertScreen(viewController, named: "clean-account-sign-in-iphone-se", device: .iPhone8)
    }

    func testAccountDeletionPendingCompactSnapshot() {
        SnapshotSupport.setUp(designStyle: .classic)
        let viewController = makeHostingController(rootView: AccountStartView(
            model: AccountStartModel(
                state: .deletionPending,
                errorMessage: L10n.Settings.Account.deletionFailedMessage
            ),
            appearance: SnapshotSupport.appearance(designStyle: .classic),
            onPrimaryAction: {}
        ))

        SnapshotSupport.assertScreen(viewController, named: "classic-account-deletion-pending-iphone-se", device: .iPhone8)
    }

    func testSubscriptionPaywallSnapshot() throws {
        let appearance = SnapshotSupport.appearance(designStyle: .clean)
        let analytics = HomeAnalyticsTrackingSpy()
        let viewController = makeHostingController(
            rootView: SubscriptionPaywallView(
                appearance: appearance,
                analytics: analytics,
                onSubscribe: {},
                onRestore: {}
            )
        )

        SnapshotSupport.assertScreen(
            viewController,
            named: "clean-subscription-paywall",
            device: SnapshotSupport.iPhone17Pro
        )

        XCTAssertEqual(analytics.events.count, 1)
        let event = try XCTUnwrap(analytics.events.first)
        guard case let .screenView(screen, theme) = event else {
            XCTFail("Expected subscription screen view analytics event")
            return
        }
        XCTAssertEqual(screen.rawValue, AnalyticsScreen.subscription.rawValue)
        XCTAssertEqual(theme, .unknown)
    }

    func testCompactSubscriptionPaywallSnapshot() {
        let appearance = SnapshotSupport.appearance(designStyle: .clean)
        let viewController = makeHostingController(
            rootView: SubscriptionPaywallView(
                appearance: appearance,
                analytics: HomeAnalyticsTrackingSpy(),
                onSubscribe: {},
                onRestore: {}
            )
        )

        SnapshotSupport.assertScreen(
            viewController,
            named: "clean-subscription-paywall-iphone-se",
            device: .iPhone8
        )
    }

    func testAccessibilityXXXLSubscriptionPaywallSnapshot() {
        let appearance = SnapshotSupport.appearance(designStyle: .clean)
        let viewController = makeHostingController(
            rootView: SubscriptionPaywallView(
                appearance: appearance,
                analytics: HomeAnalyticsTrackingSpy(),
                onSubscribe: {},
                onRestore: {}
            )
        )

        SnapshotSupport.assertScreen(
            viewController,
            named: "clean-subscription-paywall-accessibility-xxxl",
            device: SnapshotSupport.iPhone17Pro,
            contentSizeCategory: .accessibilityExtraExtraExtraLarge
        )
    }

    func testClassicSubscriptionPaywallSnapshot() {
        SnapshotSupport.setUp(designStyle: .classic, cleanColorScheme: .dark)
        let appearance = SnapshotSupport.appearance(
            designStyle: .classic,
            cleanColorScheme: .dark
        )
        let viewController = makeHostingController(
            rootView: SubscriptionPaywallView(
                appearance: appearance,
                analytics: HomeAnalyticsTrackingSpy(),
                onSubscribe: {},
                onRestore: {}
            )
        )

        SnapshotSupport.assertScreen(
            viewController,
            named: "classic-subscription-paywall",
            device: SnapshotSupport.iPhone17Pro
        )
    }

    func testRadarSubscriptionPaywallSnapshot() {
        SnapshotSupport.setUp(designStyle: .radar, cleanColorScheme: .dark)
        let appearance = SnapshotSupport.appearance(
            designStyle: .radar,
            cleanColorScheme: .dark
        )
        let viewController = makeHostingController(
            rootView: SubscriptionPaywallView(
                appearance: appearance,
                analytics: HomeAnalyticsTrackingSpy(),
                onSubscribe: {},
                onRestore: {}
            )
        )

        SnapshotSupport.assertScreen(
            viewController,
            named: "radar-subscription-paywall",
            device: SnapshotSupport.iPhone17Pro
        )
    }

    func testFakeLaunchScreenSnapshot() {
        SnapshotSupport.setUp(designStyle: .classic)
        let viewController = makeHostingController(
            rootView: FakeLaunchScreenView(
                appearance: SnapshotSupport.appearance(designStyle: .classic),
                holdDuration: 60
            )
        )

        SnapshotSupport.assertScreen(
            viewController,
            named: "fake-launch-screen",
            device: SnapshotSupport.iPhone17Pro
        )
    }

    func testRadarFakeLaunchScreenSnapshot() {
        SnapshotSupport.setUp(designStyle: .radar, cleanColorScheme: .dark)
        let viewController = makeHostingController(
            rootView: FakeLaunchScreenView(
                appearance: SnapshotSupport.appearance(
                    designStyle: .radar,
                    cleanColorScheme: .dark
                ),
                holdDuration: 60
            )
        )

        SnapshotSupport.assertScreen(
            viewController,
            named: "radar-fake-launch-screen",
            device: SnapshotSupport.iPhone17Pro
        )
    }

    func testCleanLightFakeLaunchScreenSnapshot() {
        SnapshotSupport.setUp(designStyle: .clean, cleanColorScheme: .light)
        let viewController = makeHostingController(
            rootView: FakeLaunchScreenView(
                appearance: SnapshotSupport.appearance(
                    designStyle: .clean,
                    cleanColorScheme: .light
                ),
                holdDuration: 60
            )
        )

        SnapshotSupport.assertScreen(
            viewController,
            named: "clean-light-fake-launch-screen",
            device: SnapshotSupport.iPhone17Pro
        )
    }

    func testCleanDarkFakeLaunchScreenSnapshot() {
        SnapshotSupport.setUp(designStyle: .clean, cleanColorScheme: .dark)
        let viewController = makeHostingController(
            rootView: FakeLaunchScreenView(
                appearance: SnapshotSupport.appearance(
                    designStyle: .clean,
                    cleanColorScheme: .dark
                ),
                holdDuration: 60
            )
        )

        SnapshotSupport.assertScreen(
            viewController,
            named: "clean-dark-fake-launch-screen",
            device: SnapshotSupport.iPhone17Pro
        )
    }

    func testClassicOnboardingWelcomeSnapshot() {
        SnapshotSupport.setUp(designStyle: .classic, cleanColorScheme: .dark)
        let appearance = SnapshotSupport.appearance(
            designStyle: .classic,
            cleanColorScheme: .dark
        )
        let viewController = makeHostingController(
            rootView: QuizOnboardingView(
                appearance: appearance,
                themes: onboardingThemes,
                onComplete: { _ in }
            )
        )

        SnapshotSupport.assertScreen(
            viewController,
            named: "classic-onboarding-welcome",
            device: SnapshotSupport.iPhone17Pro
        )
    }

    func testClassicOnboardingWelcomeCompactSnapshot() {
        SnapshotSupport.setUp(designStyle: .classic, cleanColorScheme: .dark)
        let appearance = SnapshotSupport.appearance(
            designStyle: .classic,
            cleanColorScheme: .dark
        )
        let viewController = makeHostingController(
            rootView: QuizOnboardingView(
                appearance: appearance,
                themes: denseOnboardingThemes,
                onComplete: { _ in }
            )
        )

        SnapshotSupport.assertScreen(
            viewController,
            named: "classic-onboarding-welcome-iphone-se",
            device: .iPhone8
        )
    }

    func testClassicOnboardingTopicsSnapshot() {
        SnapshotSupport.setUp(designStyle: .classic, cleanColorScheme: .dark)
        let appearance = SnapshotSupport.appearance(
            designStyle: .classic,
            cleanColorScheme: .dark
        )
        let viewController = makeHostingController(
            rootView: QuizOnboardingView(
                appearance: appearance,
                themes: onboardingThemes,
                initialPage: .topics,
                preferredThemeIDs: ["music", "history_culture"],
                onComplete: { _ in }
            )
        )

        SnapshotSupport.assertScreen(
            viewController,
            named: "classic-onboarding-topics",
            device: SnapshotSupport.iPhone17Pro
        )
    }

    func testClassicOnboardingTopicsCompactSnapshot() {
        SnapshotSupport.setUp(designStyle: .classic, cleanColorScheme: .dark)
        let appearance = SnapshotSupport.appearance(
            designStyle: .classic,
            cleanColorScheme: .dark
        )
        let viewController = makeHostingController(
            rootView: QuizOnboardingView(
                appearance: appearance,
                themes: denseOnboardingThemes,
                catalogOrigin: .backend,
                initialPage: .topics,
                onComplete: { _ in }
            )
        )

        SnapshotSupport.assertScreen(
            viewController,
            named: "classic-onboarding-topics-iphone-se",
            device: .iPhone8
        )
    }

    func testClassicOnboardingTutorialCompactSnapshot() {
        SnapshotSupport.setUp(designStyle: .classic, cleanColorScheme: .dark)
        let appearance = SnapshotSupport.appearance(
            designStyle: .classic,
            cleanColorScheme: .dark
        )
        let viewController = makeHostingController(
            rootView: QuizOnboardingView(
                appearance: appearance,
                themes: onboardingThemes,
                initialPage: .tutorial,
                onComplete: { _ in }
            )
        )

        SnapshotSupport.assertScreen(
            viewController,
            named: "classic-onboarding-tutorial-iphone-se",
            device: .iPhone8
        )
    }

    func testClassicAIThemeServiceAlertSnapshot() async {
        SnapshotSupport.setUp(designStyle: .classic)
        let presenter = QuizAlertPresenter()
        let appearance = SnapshotSupport.appearance(designStyle: .classic)
        let presenterViewController = presenter.makeAlertViewController(
            Color.clear,
            appearance: appearance
        )
        XCTAssertEqual(presenterViewController.modalPresentationStyle, .overFullScreen)
        XCTAssertEqual(presenterViewController.modalTransitionStyle, .crossDissolve)
        XCTAssertTrue(presenterViewController.isModalInPresentation)
        XCTAssertEqual(presenterViewController.view.backgroundColor, .clear)
        XCTAssertFalse(presenterViewController.view.isOpaque)
        XCTAssertTrue(presenterViewController.view.accessibilityViewIsModal)

        await assertAlertIsCenteredInFullWindow(appearance: appearance)

        let viewController = makeAlertSnapshotViewController(
            alert: AIQuizGenerationAlert(error: YandexAIQuizThemeServiceError.httpStatus(503)),
            appearance: appearance
        )

        SnapshotSupport.assertScreen(
            viewController,
            named: "classic-ai-theme-service-alert-iphone-se",
            device: .iPhone8
        )
    }

    func testClassicAIThemeRefusalAlertSnapshot() {
        SnapshotSupport.setUp(designStyle: .classic)
        let viewController = makeAlertSnapshotViewController(
            alert: AIQuizGenerationAlert(error: YandexAIQuizThemeServiceError.refused),
            appearance: SnapshotSupport.appearance(designStyle: .classic)
        )

        SnapshotSupport.assertScreen(
            viewController,
            named: "classic-ai-theme-refusal-alert-iphone-se",
            device: .iPhone8
        )
    }

    func testRadarAIThemeRefusalAlertSnapshot() {
        SnapshotSupport.setUp(designStyle: .radar)
        let viewController = makeAlertSnapshotViewController(
            alert: AIQuizGenerationAlert(error: YandexAIQuizThemeServiceError.refused),
            appearance: SnapshotSupport.appearance(designStyle: .radar)
        )

        SnapshotSupport.assertScreen(
            viewController,
            named: "radar-ai-theme-refusal-alert-iphone-se",
            device: .iPhone8
        )
    }

    func testCleanQuestionExitAlertSnapshot() {
        let appearance = SnapshotSupport.appearance(designStyle: .clean)
        let viewController = makeQuestionExitAlertSnapshotViewController(appearance: appearance)

        SnapshotSupport.assertScreen(
            viewController,
            named: "clean-question-exit-alert-iphone-se",
            device: .iPhone8
        )
    }

    func testClassicQuestionExitAlertSnapshot() {
        SnapshotSupport.setUp(designStyle: .classic)
        let appearance = SnapshotSupport.appearance(designStyle: .classic)
        let viewController = makeQuestionExitAlertSnapshotViewController(appearance: appearance)

        SnapshotSupport.assertScreen(
            viewController,
            named: "classic-question-exit-alert-iphone-se",
            device: .iPhone8
        )
    }

    func testRadarQuestionExitAlertSnapshot() {
        SnapshotSupport.setUp(designStyle: .radar, cleanColorScheme: .dark)
        let appearance = SnapshotSupport.appearance(
            designStyle: .radar,
            cleanColorScheme: .dark
        )
        let viewController = makeQuestionExitAlertSnapshotViewController(appearance: appearance)

        SnapshotSupport.assertScreen(
            viewController,
            named: "radar-question-exit-alert-iphone-se",
            device: .iPhone8
        )
    }

    func testAlertPresenterIgnoresReentrantDismissal() throws {
        let appearance = SnapshotSupport.appearance(designStyle: .clean)
        var pendingDismissal: (() -> Void)?
        var requestedAnimation: Bool?
        let presenter = QuizAlertPresenter { controller, animated, completion in
            XCTAssertFalse(controller.view.isUserInteractionEnabled)
            requestedAnimation = animated
            pendingDismissal = completion
        }
        let previousKeyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let rootViewController = UIViewController()
        window.rootViewController = rootViewController
        window.makeKeyAndVisible()
        presenter.presentingViewController = rootViewController
        defer {
            rootViewController.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }

        XCTAssertTrue(presenter.present(Color.clear, appearance: appearance, reduceMotion: true))

        var firstCompletionCount = 0
        var reentrantCompletionCount = 0
        presenter.dismiss { firstCompletionCount += 1 }
        presenter.dismiss { reentrantCompletionCount += 1 }

        XCTAssertTrue(presenter.isDismissing)
        XCTAssertEqual(requestedAnimation, false)
        XCTAssertEqual(firstCompletionCount, 0)
        XCTAssertEqual(reentrantCompletionCount, 0)

        try XCTUnwrap(pendingDismissal)()

        XCTAssertFalse(presenter.isDismissing)
        XCTAssertNil(presenter.alertViewController)
        XCTAssertEqual(firstCompletionCount, 1)
        XCTAssertEqual(reentrantCompletionCount, 0)
    }

    private func makeHostingController<Content: View>(rootView: Content) -> UIHostingController<Content> {
        let viewController = UIHostingController(rootView: rootView)
        viewController.loadViewIfNeeded()
        viewController.view.overrideUserInterfaceStyle = AppAppearanceStore.shared
            .appearance(compatibleWith: viewController.traitCollection)
            .resolvedInterfaceStyle
        return viewController
    }

    private func prepareSettingsSnapshot(_ viewController: UIViewController) {
        resetScrollViewsToTop(in: viewController.view)
    }

    private func resetScrollViewsToTop(in view: UIView) {
        if let scrollView = view as? UIScrollView {
            scrollView.setContentOffset(
                CGPoint(
                    x: -scrollView.adjustedContentInset.left,
                    y: -scrollView.adjustedContentInset.top
                ),
                animated: false
            )
        }
        view.subviews.forEach(resetScrollViewsToTop)
    }

    private func makeAlertSnapshotViewController(
        alert: AIQuizGenerationAlert,
        appearance: AppAppearance
    ) -> UIViewController {
        let dismissAction = QuizAlertAction(
            title: alert.offersEditAction
                ? L10n.AITheme.editTheme
                : L10n.Settings.alertAction,
            emphasis: alert.canRetry ? .secondary : .primary,
            accessibilityIdentifier: "snapshotDismissAction",
            action: {}
        )
        let primaryAction = alert.canRetry
            ? QuizAlertAction(
                title: L10n.AITheme.retry,
                emphasis: .primary,
                accessibilityIdentifier: "snapshotRetryAction",
                action: {}
            )
            : dismissAction
        let secondaryAction = alert.canRetry ? dismissAction : nil
        return makeAlertSnapshotViewController(
            overlay: QuizAlertOverlay(
                title: alert.title,
                message: alert.message,
                systemImage: alert.kind.systemImage,
                iconColor: alert.kind.iconColor(in: appearance),
                primaryAction: primaryAction,
                secondaryAction: secondaryAction,
                onEscape: {}
            ),
            appearance: appearance
        )
    }

    private func makeQuestionExitAlertSnapshotViewController(
        appearance: AppAppearance
    ) -> UIViewController {
        let questionViewController = QuizQuestionViewController()
        return makeAlertSnapshotViewController(
            overlay: questionViewController.makeExitConfirmationAlertOverlay(),
            appearance: appearance
        )
    }

    private func makeAlertSnapshotViewController(
        overlay: QuizAlertOverlay,
        appearance: AppAppearance
    ) -> UIViewController {
        let rootView = ZStack {
            Color(uiColor: appearance.backgroundColor)
                .ignoresSafeArea()
            overlay
        }
        .environment(\.appAppearance, appearance)
        .preferredColorScheme(appearance.swiftUIColorScheme)

        return makeHostingController(rootView: rootView)
    }

    private func assertAlertIsCenteredInFullWindow(appearance: AppAppearance) async {
        let windowBounds = CGRect(x: 0, y: 0, width: 402, height: 874)
        let previousKeyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        let window = UIWindow(frame: windowBounds)
        let rootViewController = UIViewController()
        window.rootViewController = rootViewController
        window.makeKeyAndVisible()
        rootViewController.view.frame = window.bounds

        let offsetPresentingViewController = UIViewController()
        rootViewController.addChild(offsetPresentingViewController)
        offsetPresentingViewController.view.frame = CGRect(x: 0, y: 86, width: 402, height: 788)
        rootViewController.view.addSubview(offsetPresentingViewController.view)
        offsetPresentingViewController.didMove(toParent: rootViewController)

        let presenter = QuizAlertPresenter()
        presenter.presentingViewController = offsetPresentingViewController
        defer {
            presenter.dismiss()
            offsetPresentingViewController.willMove(toParent: nil)
            offsetPresentingViewController.view.removeFromSuperview()
            offsetPresentingViewController.removeFromParent()
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }

        let frameExpectation = expectation(description: "Alert card geometry is reported")
        var reportedCardFrame: CGRect?
        var didFulfillFrameExpectation = false
        let overlay = QuizAlertOverlay(
            title: L10n.AITheme.Error.Service.title,
            message: L10n.AITheme.Error.Service.message,
            systemImage: "clock.fill",
            iconColor: appearance.screenTextColor,
            primaryAction: QuizAlertAction(
                title: L10n.AITheme.retry,
                emphasis: .primary,
                accessibilityIdentifier: "centerTestPrimaryAction",
                action: {}
            ),
            secondaryAction: QuizAlertAction(
                title: L10n.AITheme.editTheme,
                emphasis: .secondary,
                accessibilityIdentifier: "centerTestSecondaryAction",
                action: {}
            ),
            onEscape: {},
            onCardFrameChange: { frame in
                guard frame.width > 0, frame.height > 0 else { return }
                reportedCardFrame = frame
                if !didFulfillFrameExpectation {
                    didFulfillFrameExpectation = true
                    frameExpectation.fulfill()
                }
            }
        )

        XCTAssertEqual(
            offsetPresentingViewController.view.convert(offsetPresentingViewController.view.bounds, to: window).minY,
            86
        )
        XCTAssertTrue(presenter.present(overlay, appearance: appearance, reduceMotion: true))
        guard let alertViewController = presenter.alertViewController else {
            XCTFail("Full-screen alert was not presented")
            return
        }

        // Drive the first layout before waiting for SwiftUI's geometry callback.
        // The callback may still arrive asynchronously on a busy CI simulator.
        window.layoutIfNeeded()
        alertViewController.view.setNeedsLayout()
        alertViewController.view.layoutIfNeeded()
        await fulfillment(of: [frameExpectation], timeout: 10)
        await Task.yield()

        guard let reportedCardFrame else {
            XCTFail("Alert card geometry was not reported")
            return
        }

        let alertFrame = alertViewController.view.convert(alertViewController.view.bounds, to: window)
        XCTAssertTrue(alertViewController.view.window === window)
        XCTAssertEqual(alertFrame.minX, window.bounds.minX, accuracy: 0.5)
        XCTAssertEqual(alertFrame.minY, window.bounds.minY, accuracy: 0.5)
        XCTAssertEqual(alertFrame.width, window.bounds.width, accuracy: 0.5)
        XCTAssertEqual(alertFrame.height, window.bounds.height, accuracy: 0.5)
        XCTAssertEqual(reportedCardFrame.midX, window.bounds.midX, accuracy: 0.5)
        XCTAssertEqual(reportedCardFrame.midY, window.bounds.midY, accuracy: 0.5)
    }
}

@MainActor
private final class SettingsSnapshotAccountManager: AccountManaging {
    let accountDeletionAvailable = true
    let canCreateAccount = false

    func deleteAccount() async throws { throw AccountDeletionError.unavailable }
    func createAccount() async throws { throw AccountDeletionError.unavailable }
}

@MainActor
private final class SettingsBottomSnapshotHostingController: UIHostingController<QuizSettingsView> {
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollToBottom(in: view)
    }

    private func scrollToBottom(in view: UIView) {
        if let scrollView = view as? UIScrollView {
            let offset = CGPoint(
                x: -scrollView.adjustedContentInset.left,
                y: max(-scrollView.adjustedContentInset.top,
                       scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
            )
            if scrollView.contentOffset != offset {
                scrollView.setContentOffset(offset, animated: false)
            }
        }
        view.subviews.forEach(scrollToBottom)
    }
}
