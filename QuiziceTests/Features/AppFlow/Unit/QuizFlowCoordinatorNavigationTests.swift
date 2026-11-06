import SwiftUI
import UIKit
import XCTest
@testable import Quizice

@MainActor
final class QuizFlowCoordinatorNavigationTests: QuizFlowCoordinatorTestCase {
    func testCloseQuestionReturnsToHome() {
        let harness = makeHarness()
        harness.coordinator.start()

        harness.coordinator.closeQuestion()

        XCTAssertEqual(harness.navigationController.popToRootCallCount, 1)
        XCTAssertEqual(harness.navigationController.popToRootAnimationFlags, [false])
        XCTAssertEqual(harness.navigationController.dismissCallCount, 0)
        XCTAssertTrue(harness.navigationController.dismissAnimationFlags.isEmpty)
    }

    func testAccountNavigationResetCompletesWhenHomeHasNoPresentedController() async throws {
        let harness = try makeRealNavigationResetHarness()
        defer { harness.dispose() }
        let home = try XCTUnwrap(harness.navigationController.topViewController as? QuizViewController)
        let resetCompleted = expectation(description: "Reset completes without a UIKit dismissal")
        resetCompleted.assertForOverFulfill = true
        XCTAssertNil(harness.navigationController.presentedViewController)

        harness.coordinator.resetAccountNavigation {
            XCTAssertTrue(harness.window.rootViewController === harness.navigationController)
            XCTAssertTrue(harness.navigationController.topViewController === home)
            XCTAssertTrue(home.view.window === harness.window)
            XCTAssertNil(harness.navigationController.presentedViewController)
            resetCompleted.fulfill()
        }

        await fulfillment(of: [resetCompleted], timeout: 5)
        XCTAssertEqual(harness.navigationController.viewControllers.count, 1)
    }

    func testAccountNavigationResetWaitsForRealSettingsAndOnboardingDismissal() async throws {
        UIView.setAnimationsEnabled(false)
        for presentsOnboarding in [false, true] {
            let harness = try makeRealNavigationResetHarness()
            defer { harness.dispose() }
            let home = try XCTUnwrap(harness.navigationController.topViewController as? QuizViewController)
            if presentsOnboarding {
                let presented = expectation(description: "Onboarding presented before reset")
                harness.coordinator.presentInitialOnboardingIfNeeded { presented.fulfill() }
                await fulfillment(of: [presented], timeout: 5)
                XCTAssertTrue(harness.navigationController.presentedViewController is UIHostingController<QuizOnboardingView>)
            } else {
                harness.coordinator.showSettings()
                try await waitUntil(timeout: 5) {
                    let presented = harness.navigationController.presentedViewController
                    return presented?.viewIfLoaded?.window === harness.window && presented?.isBeingPresented == false
                }
                XCTAssertTrue(harness.navigationController.presentedViewController is UIHostingController<QuizSettingsView>)
            }
            let presentedController = try XCTUnwrap(harness.navigationController.presentedViewController)
            let resetCompleted = expectation(description: "Reset completes after the old account modal disappears")
            resetCompleted.assertForOverFulfill = true

            harness.coordinator.resetAccountNavigation {
                XCTAssertNil(harness.navigationController.presentedViewController)
                XCTAssertNil(presentedController.presentingViewController)
                XCTAssertTrue(harness.window.rootViewController === harness.navigationController)
                XCTAssertTrue(harness.navigationController.topViewController === home)
                XCTAssertTrue(home.view.window === harness.window)
                resetCompleted.fulfill()
            }

            await fulfillment(of: [resetCompleted], timeout: 5)
            XCTAssertEqual(harness.navigationController.viewControllers.count, 1)
        }
    }

    func testImmediateQuestionReturnExplicitlyRestoresLuckyHomeInteraction() async throws {
        let theme = SnapshotSupport.makeTheme(
            id: "music",
            name: "Music",
            questions: (0..<5).map { index in
                QuizQuestion(
                    question: "Question \(index)?",
                    answers: ["A", "B", "C", "D"],
                    correctAnswer: "A"
                )
            }
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let navigationController = RoutingNavigationControllerSpy()
        let repository = RoutingThemeRepository(themes: [theme])
        let session = RoutingSession()
        session.themes = [theme]
        let coordinator = QuizFlowCoordinator(
            window: window,
            navigationController: navigationController,
            themeRepository: repository,
            session: session,
            aiQuizThemeService: MockAIQuizThemeService()
        )
        coordinator.start()
        navigationController.topViewControllerOverride = navigationController

        let home = try XCTUnwrap(navigationController.viewControllers.first as? QuizViewController)
        home.loadViewIfNeeded()
        home.view.frame = window.bounds
        home.view.layoutIfNeeded()
        let collectionView = try XCTUnwrap(
            descendant(in: home.view, accessibilityIdentifier: "homeThemesCollectionView") as? UICollectionView
        )
        let luckyButton = try XCTUnwrap(
            descendant(in: home.view, accessibilityIdentifier: "homeFeelingLuckyButton") as? UIButton
        )

        luckyButton.sendActions(for: .touchUpInside)
        try await waitUntil(timeout: 1.5) {
            navigationController.presentedControllers.count == 1
        }
        XCTAssertEqual(navigationController.presentedControllers.count, 1)

        luckyButton.isHidden = true
        coordinator.returnToThemes()

        XCTAssertTrue(collectionView.isUserInteractionEnabled)
        XCTAssertFalse(luckyButton.isHidden)

        let themeButton = try XCTUnwrap(
            descendant(in: home.view, accessibilityIdentifier: "music") as? UIButton
        )
        themeButton.sendActions(for: .touchUpInside)
        XCTAssertNotNil(
            descendant(in: home.view, accessibilityIdentifier: "homeExpandedThemeCard")
        )
    }

    func testReplayPreservesSelectionAndReusesQuestionControllerWithoutShowingHome() throws {
        let harness = makeHarness()
        harness.coordinator.start()
        harness.navigationController.topViewControllerOverride = harness.navigationController
        let session = harness.session
        let selectedThemeID = session.chosenTheme?.themeID
        session.questionsCount = 10

        harness.coordinator.showQuestion()
        let firstQuestion = try XCTUnwrap(harness.navigationController.presentedControllers.last as? QuizQuestionViewController)

        harness.coordinator.replayQuiz()

        let replayedQuestion = try XCTUnwrap(harness.navigationController.presentedControllers.last as? QuizQuestionViewController)
        XCTAssertTrue(firstQuestion === replayedQuestion)
        XCTAssertEqual(harness.navigationController.presentedControllers.count, 1)
        XCTAssertEqual(session.chosenTheme?.themeID, selectedThemeID)
        XCTAssertEqual(session.questionsCount, 10)
        XCTAssertTrue(harness.navigationController.dismissAnimationFlags.isEmpty)
    }

    func testCatalogReplacementPreservesResultThemeAndReplayRequestSize() async throws {
        let questions = (0..<3).map {
            QuizQuestion(question: "Original \($0)?", answers: ["A", "B", "C", "D"], correctAnswer: "A")
        }
        let theme = SnapshotSupport.makeTheme(id: "music", name: "Original", questions: questions)
        let repository = PartialReplayThemeRepository(theme: theme)
        let session = RoutingSession()
        session.chosenTheme = ThemeModel(quizTheme: theme)
        session.questionsCount = 15
        let analytics = InlineAIAnalyticsSpy()
        let navigation = RoutingNavigationControllerSpy()
        let coordinator = QuizFlowCoordinator(
            window: UIWindow(), navigationController: navigation, themeRepository: repository,
            session: session, aiQuizThemeService: MockAIQuizThemeService(), analytics: analytics
        )
        coordinator.start()
        navigation.topViewControllerOverride = navigation
        coordinator.showQuestion()
        let question = try XCTUnwrap(navigation.presentedControllers.last as? QuizQuestionViewController)
        question.loadViewIfNeeded()
        defer { question.presenter?.stopTimer() }
        let firstPresenter = try XCTUnwrap(question.presenter as? QuizQuestionPresenter)
        theme.id = "changed"
        theme.theme = "Changed"
        session.chosenTheme = nil
        session.questionsCount = 5
        coordinator.showResult(QuizResultState(correctAnswers: 2, totalQuestions: 3))
        let result = try XCTUnwrap(navigation.presentedControllers.last as? QuizResultViewController)
        XCTAssertEqual(result.presenter?.themeID, "music")
        coordinator.replayQuiz()
        try await waitUntil { (question.presenter as? QuizQuestionPresenter) !== firstPresenter }
        XCTAssertEqual(repository.requestedThemeIDs, ["music"])
        XCTAssertEqual(repository.requestedCounts, [15])
        XCTAssertEqual(question.presenter?.questionsTotalCount, 3)
        XCTAssertEqual(session.questionsCount, 15)
        XCTAssertEqual(analytics.quizStartedCount, 2)
        XCTAssertEqual(navigation.presentedControllers.filter { $0 is QuizQuestionViewController }.count, 1)
    }

    func testSlowCatalogReplayShowsDelayedProgressAndClearsItWhenCancelled() async throws {
        let theme = SnapshotSupport.makeTheme(
            id: "music",
            name: "Music",
            questions: (0..<5).map { index in
                QuizQuestion(
                    question: "Question \(index)?",
                    answers: ["A", "B", "C", "D"],
                    correctAnswer: "A"
                )
            }
        )
        let repository = HangingRoutingThemeRepository(themes: [theme])
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let navigationController = RoutingNavigationControllerSpy()
        let session = RoutingSession()
        session.chosenTheme = ThemeModel(quizTheme: theme)
        session.questionsCount = 5
        let coordinator = QuizFlowCoordinator(
            window: window,
            navigationController: navigationController,
            themeRepository: repository,
            session: session,
            aiQuizThemeService: MockAIQuizThemeService(),
            catalogReplayProgressDelay: {}
        )
        coordinator.start()
        navigationController.topViewControllerOverride = navigationController
        coordinator.showQuestion()
        coordinator.showResult(QuizResultState(correctAnswers: 3, totalQuestions: 5))

        let resultViewController = try XCTUnwrap(
            navigationController.presentedControllers.last as? QuizResultViewController
        )
        resultViewController.loadViewIfNeeded()
        let replayButton = try XCTUnwrap(
            descendant(
                in: resultViewController.view,
                accessibilityIdentifier: "resultReplayButton"
            ) as? UIButton
        )
        let activityIndicator = try XCTUnwrap(
            descendant(
                in: resultViewController.view,
                accessibilityIdentifier: "resultReplayActivityIndicator"
            ) as? UIActivityIndicatorView
        )

        coordinator.replayQuiz()
        try await waitUntil {
            repository.prepareQuizCallCount == 1 && activityIndicator.isAnimating
        }

        XCTAssertFalse(replayButton.isEnabled)
        XCTAssertNil(replayButton.title(for: .normal))

        coordinator.returnToThemes()

        XCTAssertFalse(activityIndicator.isAnimating)
    }

    func testRandomSelectionReplayChoosesAChangedFiveQuestionSetFromTheFullCatalog() async throws {
        let catalogQuestions = (0..<8).map { index in
            QuizQuestion(
                question: "Catalog question \(index)?",
                answers: ["A", "B", "C", "D"],
                correctAnswer: "A"
            )
        }
        let catalogTheme = SnapshotSupport.makeTheme(
            id: "catalog",
            name: "Catalog",
            questions: catalogQuestions
        )
        let initialRandomTheme = try XCTUnwrap(
            RandomQuizSelection.makeTheme(
                from: [catalogTheme],
                title: L10n.Home.randomSelection,
                description: L10n.Home.feelingLucky,
                randomizing: { $0 }
            )
        )
        let initialQuestionTexts = initialRandomTheme.questions.map(\.question)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let navigationController = RoutingNavigationControllerSpy()
        let repository = RoutingThemeRepository(themes: [catalogTheme])
        let session = RoutingSession()
        session.chosenTheme = ThemeModel(quizTheme: initialRandomTheme)
        session.questionsCount = RandomQuizSelection.questionCount
        let coordinator = QuizFlowCoordinator(
            window: window,
            navigationController: navigationController,
            themeRepository: repository,
            session: session,
            aiQuizThemeService: MockAIQuizThemeService(),
            randomQuestionsProvider: { $0 },
            randomQuestionSelectionModeProvider: { .random }
        )
        coordinator.start()
        navigationController.topViewControllerOverride = navigationController
        coordinator.showQuestion()
        let questionViewController = try XCTUnwrap(
            navigationController.presentedControllers.last as? QuizQuestionViewController
        )

        coordinator.replayQuiz()
        try await waitUntil {
            session.chosenTheme?.quizTheme.questions.map(\.question) != initialQuestionTexts
        }

        let replayedTheme = try XCTUnwrap(session.chosenTheme)
        let replayedQuestionTexts = replayedTheme.quizTheme.questions.map(\.question)
        XCTAssertEqual(replayedTheme.themeID, RandomQuizSelection.themeID)
        XCTAssertEqual(replayedTheme.themeName, L10n.Home.randomSelection)
        XCTAssertTrue(replayedTheme.quizTheme.questions.allSatisfy { $0.sourceThemeName == "Catalog" })
        XCTAssertEqual(replayedQuestionTexts.count, RandomQuizSelection.questionCount)
        XCTAssertNotEqual(replayedQuestionTexts, initialQuestionTexts)
        XCTAssertTrue(replayedQuestionTexts.contains("Catalog question 5?"))
        XCTAssertTrue(replayedQuestionTexts.contains("Catalog question 6?"))
        XCTAssertTrue(replayedQuestionTexts.contains("Catalog question 7?"))
        XCTAssertEqual(session.questionsCount, RandomQuizSelection.questionCount)
        XCTAssertTrue(navigationController.presentedControllers.last === questionViewController)
        XCTAssertEqual(navigationController.presentedControllers.count, 1)
    }

    func testReturnToThemesReachesNavigationRoot() {
        let harness = makeHarness()
        harness.coordinator.start()

        harness.coordinator.returnToThemes()

        XCTAssertEqual(harness.navigationController.popToRootAnimationFlags, [false])
        XCTAssertTrue(harness.navigationController.dismissAnimationFlags.isEmpty)
    }

    func testModalRoutesPresentQuestionResultAndSettings() {
        let harness = makeHarness()
        harness.coordinator.start()
        harness.navigationController.topViewControllerOverride = harness.navigationController

        harness.coordinator.showQuestion()
        XCTAssertEqual(harness.navigationController.presentedControllers.count, 1)
        XCTAssertEqual(harness.navigationController.presentedControllers.last?.modalPresentationStyle, .custom)
        XCTAssertEqual(harness.navigationController.presentedAnimationFlags.last, true)
        let questionViewController = harness.navigationController.presentedControllers.last as? QuizQuestionViewController
        XCTAssertNotNil(questionViewController?.transitioningDelegate)

        harness.coordinator.showResult(QuizResultState(correctAnswers: 2, totalQuestions: 3))
        XCTAssertEqual(harness.navigationController.presentedControllers.count, 2)
        XCTAssertEqual(harness.navigationController.presentedControllers.last?.modalPresentationStyle, .custom)
        XCTAssertEqual(harness.navigationController.presentedAnimationFlags.last, true)
        let resultViewController = harness.navigationController.presentedControllers.last as? QuizResultViewController
        XCTAssertNotNil(resultViewController?.transitioningDelegate)

        harness.coordinator.showSettings()
        XCTAssertEqual(harness.navigationController.presentedControllers.count, 3)
        XCTAssertEqual(harness.navigationController.presentedControllers.last?.modalPresentationStyle, .pageSheet)
        XCTAssertEqual(harness.navigationController.presentedAnimationFlags.last, true)
    }

    func testSubscriptionPreviewDisablesPurchaseAndRestore() throws {
        let harness = makeHarness()
        harness.coordinator.start()
        harness.navigationController.topViewControllerOverride = harness.navigationController
        harness.coordinator.showSubscription()
        let preview = try XCTUnwrap(harness.navigationController.presentedControllers.last
            as? UIHostingController<SubscriptionPaywallView>)
        XCTAssertEqual(preview.modalPresentationStyle, .pageSheet)
        XCTAssertEqual(preview.sheetPresentationController?.detents, [.large()])
        XCTAssertEqual(harness.navigationController.presentedAnimationFlags.last, true)
        XCTAssertFalse(preview.rootView.purchasesAvailable)
        preview.rootView.subscribe()
        preview.rootView.restore()
        XCTAssertEqual(harness.navigationController.presentedControllers.count, 1)
    }

    func testUnavailableSubscriptionOnlyForwardsCloseAction() {
        var receivedActions: [String] = []
        let paywall = SubscriptionPaywallView(
            appearance: makeLaunchAppearance(designStyle: .clean),
            analytics: HomeAnalyticsTrackingSpy(),
            onSubscribe: { receivedActions.append("subscribe") },
            onRestore: { receivedActions.append("restore") },
            onClose: { receivedActions.append("close") }
        )

        paywall.subscribe()
        XCTAssertEqual(receivedActions, [])

        paywall.restore()
        XCTAssertEqual(receivedActions, [])

        paywall.close()
        XCTAssertEqual(receivedActions, ["close"])
    }

    private func makeRealNavigationResetHarness() throws -> RealNavigationResetHarness {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let navigationController = UINavigationController()
        let suiteName = "QuizFlowCoordinatorNavigationResetTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let coordinator = QuizFlowCoordinator(
            window: window,
            navigationController: navigationController,
            themeRepository: RoutingThemeRepository(themes: []),
            session: RoutingSession(),
            aiQuizThemeService: MockAIQuizThemeService(),
            onboardingProgressStore: OnboardingProgressStore(userDefaults: defaults),
            analytics: InlineAIAnalyticsSpy()
        )
        coordinator.start()
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        navigationController.view.layoutIfNeeded()
        return RealNavigationResetHarness(
            window: window,
            previousKeyWindow: previousKeyWindow,
            navigationController: navigationController,
            coordinator: coordinator,
            defaults: defaults,
            suiteName: suiteName
        )
    }

    func testResultRouteUsesTheCoordinatorSession() throws {
        let harness = makeHarness()
        harness.session.chosenTheme = ThemeModel(
            quizTheme: SnapshotSupport.makeTheme(id: "injected-session", name: "Injected")
        )
        QuizFactory.shared.chosenTheme = ThemeModel(
            quizTheme: SnapshotSupport.makeTheme(id: "global-session", name: "Global")
        )
        harness.coordinator.start()
        harness.navigationController.topViewControllerOverride = harness.navigationController

        harness.coordinator.showResult(QuizResultState(correctAnswers: 1, totalQuestions: 1))

        let resultViewController = try XCTUnwrap(
            harness.navigationController.presentedControllers.last as? QuizResultViewController
        )
        XCTAssertEqual(resultViewController.presenter?.themeID, "injected-session")
    }
}

@MainActor
private struct RealNavigationResetHarness {
    let window: UIWindow
    let previousKeyWindow: UIWindow?
    let navigationController: UINavigationController
    let coordinator: QuizFlowCoordinator
    let defaults: UserDefaults
    let suiteName: String

    func dispose() {
        navigationController.dismiss(animated: false)
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private final class PartialReplayThemeRepository: ThemeRepository {
    var themes: [QuizTheme]?
    private let preparedTheme: QuizTheme
    private(set) var requestedThemeIDs: [String] = []
    private(set) var requestedCounts: [Int] = []

    init(theme: QuizTheme) {
        themes = [theme.roundSnapshot()]
        preparedTheme = theme.roundSnapshot()
    }

    func loadData(forceReload: Bool) {}
    func fetchQuizThemes() -> [QuizTheme] { themes ?? [] }
    func prepareQuiz(themeID: String, questionCount: Int, locale: String) async throws -> QuizTheme {
        requestedThemeIDs.append(themeID)
        requestedCounts.append(questionCount)
        return preparedTheme.roundSnapshot()
    }
}
