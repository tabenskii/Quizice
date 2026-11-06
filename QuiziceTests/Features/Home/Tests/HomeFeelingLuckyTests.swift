import SwiftUI
import XCTest
@testable import Quizice

@MainActor
final class HomeFeelingLuckyTests: HomeScreenVisualStateTestCase {
    func testFeelingLuckyStartsFiveQuestionsWithoutDescription() async throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка", questionCount: 15)]
        QuizFactory.shared.questionsCount = 15

        let viewController = QuizViewController(
            randomQuestionsProvider: { $0 },
            feelingLuckyMinimumFeedbackDelay: {}
        )
        let router = HomeRouterSpy()
        viewController.router = router
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        testWindows.append(window)
        let luckyButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeFeelingLuckyButton") as? UIButton
        )

        luckyButton.sendActions(for: .touchUpInside)
        luckyButton.sendActions(for: .touchUpInside)
        let launchTask = try XCTUnwrap(viewController.feelingLuckyTask)
        await launchTask.value

        XCTAssertEqual(QuizFactory.shared.questionsCount, 5)
        XCTAssertEqual(router.showQuestionCallCount, 1)
    }

    func testFeelingLuckyAnalyticsTracksRandomFiveQuestionStart() async throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка", questionCount: 15)]
        let analytics = HomeAnalyticsTrackingSpy()
        let viewController = QuizViewController(
            analytics: analytics,
            randomQuestionsProvider: { $0 },
            feelingLuckyMinimumFeedbackDelay: {}
        )
        let router = HomeRouterSpy()
        viewController.router = router
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        testWindows.append(window)
        drainAnimations(0.01)
        analytics.reset()

        let luckyButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeFeelingLuckyButton") as? UIButton
        )
        luckyButton.sendActions(for: .touchUpInside)
        let launchTask = try XCTUnwrap(viewController.feelingLuckyTask)
        await launchTask.value

        let luckyEvents = analytics.events.filter { event in
            !(event.name == "screen_view" && event.parameters["screen"] as? String == "home")
        }
        XCTAssertEqual(luckyEvents.map(\.name), ["theme_selected"])
        guard luckyEvents.count == 1 else { return }
        XCTAssertEqual(luckyEvents[0].parameters["selection_method"] as? String, "random")
        XCTAssertEqual(luckyEvents[0].parameters["theme_id"] as? String, "random-selection")
        XCTAssertEqual(router.showQuestionCallCount, 1)
    }

    func testFeelingLuckyForwardsSelectedBackendMode() async throws {
        let repository = FeelingLuckyThemeRepositorySpy(
            themes: [makeTheme(name: "Музыка", questionCount: 15)]
        )
        let viewController = QuizViewController(
            themeRepository: repository,
            randomQuestionsProvider: { $0 },
            randomQuestionSelectionModeProvider: { .randomBalanced },
            feelingLuckyMinimumFeedbackDelay: {}
        )
        let router = HomeRouterSpy()
        viewController.router = router
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        testWindows.append(window)
        let luckyButton = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeFeelingLuckyButton"
            ) as? UIButton
        )

        luckyButton.sendActions(for: .touchUpInside)
        let launchTask = try XCTUnwrap(viewController.feelingLuckyTask)
        await launchTask.value

        XCTAssertEqual(repository.requestedSelectionModes, [.randomBalanced])
        XCTAssertEqual(router.showQuestionCallCount, 1)
    }

    func testBackendFeelingLuckyDoesNotRequireBundledQuestions() async throws {
        let remoteTheme = QuizTheme(
            id: "music",
            theme: "Музыка",
            themeDescription: "Описание",
            questions: [],
            questionOrigin: .backend
        )
        let preparedRound = QuizTheme(
            id: RandomQuizSelection.themeID,
            theme: L10n.Home.randomSelection,
            themeDescription: L10n.Home.feelingLucky,
            questions: (0..<5).map { index in
                QuizQuestion(question: "Remote question \(index)?", answers: ["A", "B", "C", "D"],
                             correctAnswer: "A")
            },
            questionOrigin: .backend
        )
        let repository = FeelingLuckyThemeRepositorySpy(
            themes: [remoteTheme],
            catalogOrigin: .backend,
            preparedRandomQuiz: preparedRound
        )
        let session = QuizSessionStore(themes: { repository.themes })
        let viewController = QuizViewController(
            themeRepository: repository,
            session: session,
            feelingLuckyMinimumFeedbackDelay: {}
        )
        let router = HomeRouterSpy()
        viewController.router = router
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        testWindows.append(window)
        let luckyButton = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeFeelingLuckyButton"
            ) as? UIButton
        )

        luckyButton.sendActions(for: .touchUpInside)
        let launchTask = try XCTUnwrap(viewController.feelingLuckyTask)
        await launchTask.value

        XCTAssertEqual(repository.requestedSelectionModes.count, 1)
        XCTAssertEqual(repository.receivedFallbackQuestionCounts, [0])
        XCTAssertTrue(remoteTheme.questions.isEmpty)
        XCTAssertEqual(session.chosenTheme?.quizTheme.questions.map(\.question), preparedRound.questions.map(\.question))
        XCTAssertEqual(session.chosenTheme?.questionOrigin, .backend)
        XCTAssertEqual(router.showQuestionCallCount, 1)
    }

    func testBackendThemeOffersEverySupportedQuestionCountWithoutBundledQuestions() {
        let remoteTheme = QuizTheme(
            id: "music",
            theme: "Музыка",
            themeDescription: "Описание",
            questions: [],
            questionOrigin: .backend
        )
        let repository = FeelingLuckyThemeRepositorySpy(
            themes: [remoteTheme],
            catalogOrigin: .backend
        )
        let session = QuizSessionStore(themes: { repository.themes })
        let viewController = QuizViewController(
            themeRepository: repository,
            session: session
        )
        let sourceButton = UIButton()

        viewController.themeButtonTouchedUpInside(sourceButton, themeID: remoteTheme.stableID)

        XCTAssertEqual(
            viewController.homeCardState.availableQuestionCounts,
            QuizQuestionCountPolicy.supportedCounts
        )
    }

    func testFeelingLuckySelectsFiveQuestionsFromTheCombinedPoolAndUsesRandomSelectionTitle() async throws {
        let music = makeTheme(name: "Музыка", questionCount: 3)
        let technology = makeTheme(name: "Технологии", questionCount: 4)
        QuizFactory.shared.themes = [music, technology]
        var offeredQuestions: [QuizQuestion] = []
        let viewController = QuizViewController(
            randomQuestionsProvider: { questions in
                offeredQuestions = questions
                return Array(questions.reversed())
            },
            feelingLuckyMinimumFeedbackDelay: {}
        )
        let router = HomeRouterSpy()
        viewController.router = router
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        testWindows.append(window)
        let luckyButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeFeelingLuckyButton") as? UIButton
        )

        luckyButton.sendActions(for: .touchUpInside)
        let launchTask = try XCTUnwrap(viewController.feelingLuckyTask)
        await launchTask.value

        XCTAssertEqual(offeredQuestions.count, 7)
        XCTAssertTrue(music.questions.allSatisfy { question in offeredQuestions.contains { $0 === question } })
        XCTAssertTrue(technology.questions.allSatisfy { question in offeredQuestions.contains { $0 === question } })
        let selectedTheme = try XCTUnwrap(QuizFactory.shared.chosenTheme)
        XCTAssertEqual(selectedTheme.themeID, "random-selection")
        XCTAssertEqual(selectedTheme.themeName, L10n.Home.randomSelection)
        XCTAssertEqual(selectedTheme.questionsAndAnswers.count, 5)
        XCTAssertEqual(selectedTheme.quizTheme.questions.map(\.sourceThemeName), [
            "Технологии", "Технологии", "Технологии", "Технологии", "Музыка"
        ])
        XCTAssertEqual(selectedTheme.quizTheme.questions.map(\.question), offeredQuestions.reversed().prefix(5).map(\.question))
        XCTAssertTrue((music.questions + technology.questions).allSatisfy { $0.sourceThemeName == nil })
        XCTAssertFalse(selectedTheme.quizTheme.questions.contains { selected in
            offeredQuestions.contains { $0 === selected }
        }, "Round metadata must not mutate shared catalog questions")
        XCTAssertEqual(QuizFactory.shared.questionsCount, 5)
        XCTAssertEqual(router.showQuestionCallCount, 1)
    }

    func testFeelingLuckyShowsProgressUntilMinimumFeedbackDelayCompletes() async throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка", questionCount: 15)]
        let delayStarted = expectation(description: "Minimum feedback delay started")
        let delay = FeelingLuckyFeedbackDelay(started: delayStarted)
        defer { delay.release() }
        let viewController = QuizViewController(
            randomQuestionsProvider: { $0 },
            feelingLuckyMinimumFeedbackDelay: { await delay.wait() }
        )
        let router = HomeRouterSpy()
        viewController.router = router
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        testWindows.append(window)
        drainAnimations(0.01)

        let luckyButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeFeelingLuckyButton") as? UIButton
        )
        let collectionView = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeThemesCollectionView") as? UICollectionView
        )
        let progressView = try XCTUnwrap(
            luckyButton.descendant(withAccessibilityIdentifier: "homeFeelingLuckyProgressView")
                as? UIActivityIndicatorView
        )

        luckyButton.sendActions(for: .touchUpInside)
        luckyButton.sendActions(for: .touchUpInside)
        let launchTask = try XCTUnwrap(viewController.feelingLuckyTask)
        await fulfillment(of: [delayStarted], timeout: 2)

        XCTAssertFalse(luckyButton.isEnabled)
        XCTAssertTrue(progressView.isAnimating)
        XCTAssertEqual(luckyButton.accessibilityLabel, L10n.Home.feelingLuckyLoading)
        XCTAssertFalse(collectionView.isUserInteractionEnabled)
        XCTAssertEqual(router.showQuestionCallCount, 0)
        XCTAssertTrue(viewController.cardSlideTransitionSourceView === luckyButton)

        QuizFactory.shared.questionsCount = 10
        delay.release()
        await launchTask.value

        XCTAssertEqual(router.showQuestionCallCount, 1)
        XCTAssertTrue(progressView.isAnimating)
        XCTAssertEqual(QuizFactory.shared.questionsCount, 5)
    }

    func testFeelingLuckyCancellationRestoresHomeAndIgnoresStaleDelayCompletion() async throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка", questionCount: 15)]
        let delayStarted = expectation(description: "Minimum feedback delay started")
        let delay = FeelingLuckyFeedbackDelay(started: delayStarted)
        defer { delay.release() }
        let viewController = QuizViewController(
            randomQuestionsProvider: { $0 },
            feelingLuckyMinimumFeedbackDelay: { await delay.wait() }
        )
        let router = HomeRouterSpy()
        viewController.router = router
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        testWindows.append(window)
        drainAnimations(0.01)

        let luckyButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeFeelingLuckyButton") as? UIButton
        )
        let progressView = try XCTUnwrap(
            luckyButton.descendant(withAccessibilityIdentifier: "homeFeelingLuckyProgressView")
                as? UIActivityIndicatorView
        )
        let collectionView = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeThemesCollectionView")
                as? UICollectionView
        )
        let settingsButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeSettingsButton") as? UIButton
        )

        luckyButton.sendActions(for: .touchUpInside)
        let launchTask = try XCTUnwrap(viewController.feelingLuckyTask)
        await fulfillment(of: [delayStarted], timeout: 2)
        XCTAssertTrue(progressView.isAnimating)

        viewController.quizFlowWillReturnToThemes()

        XCTAssertTrue(luckyButton.isEnabled)
        XCTAssertFalse(progressView.isAnimating)
        XCTAssertEqual(luckyButton.accessibilityLabel, L10n.Home.feelingLucky)
        XCTAssertTrue(collectionView.isUserInteractionEnabled)
        XCTAssertTrue(settingsButton.isEnabled)
        XCTAssertEqual(router.showQuestionCallCount, 0)

        delay.release()
        await launchTask.value

        XCTAssertEqual(router.showQuestionCallCount, 0)
        XCTAssertTrue(luckyButton.isEnabled)
        XCTAssertFalse(progressView.isAnimating)
        XCTAssertNil(viewController.presentedViewController)
        XCTAssertNil(viewController.activeQuizPreparationAlert)
    }

    func testFeelingLuckyOfflineFailurePreservesMotivationAndOffersBackAndRetry() async throws {
        try await assertFeelingLuckyFailureRecovery(
            error: BackendContentError.transport(.notConnectedToInternet),
            expectedMessage: L10n.Question.networkFailureMessage
        )
    }

    func testFeelingLuckyServerFailurePreservesMotivationAndOffersBackAndRetry() async throws {
        try await assertFeelingLuckyFailureRecovery(
            error: BackendContentError.httpStatus(503, nil),
            expectedMessage: L10n.Question.loadingFailedMessage
        )
    }

    func testReturningToThemesDuringErrorDismissalCancelsPendingFeelingLuckyRetry() async throws {
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(true)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }
        let (controller, repository, router, luckyButton) = try makeBackendFailureHarness(reduceMotion: false)
        repository.preparationError = BackendContentError.httpStatus(503, nil)

        luckyButton.sendActions(for: .touchUpInside)
        let launchTask = try XCTUnwrap(controller.feelingLuckyTask)
        await launchTask.value
        try await waitUntil { controller.presentedViewController != nil }
        let presentedController = try XCTUnwrap(controller.presentedViewController)
        try await waitUntil {
            !presentedController.isBeingPresented && presentedController.transitionCoordinator == nil
        }
        let alert = try XCTUnwrap(controller.activeQuizPreparationAlert)
        repository.preparationError = nil

        alert.primaryAction.action()
        XCTAssertTrue(controller.quizPreparationAlertPresenter.isDismissing)
        controller.quizFlowWillReturnToThemes()
        XCTAssertNil(controller.activeQuizPreparationAlert)
        try await waitUntil {
            !controller.quizPreparationAlertPresenter.isDismissing && controller.presentedViewController == nil
        }
        // Drain a retry started by a stale dismissal completion, if one escaped cancellation.
        let pendingRetryTask = controller.feelingLuckyTask
        await pendingRetryTask?.value

        XCTAssertEqual(repository.requestedSelectionModes.count, 1)
        XCTAssertEqual(router.showQuestionCallCount, 0)
        XCTAssertEqual(controller.homeCardState.phase, .grid)
        XCTAssertFalse(controller.isQuizLaunchPending)
        XCTAssertNil(controller.feelingLuckyTask)
        XCTAssertTrue(luckyButton.isEnabled)
    }

    func testFeelingLuckyCancelledRequestDoesNotPresentAnError() async throws {
        let cancellationErrors: [Error] = [
            CancellationError(), URLError(.cancelled),
            BackendContentError.transport(.cancelled), BackendAPIError.transport(.cancelled)
        ]
        for error in cancellationErrors {
            let (controller, repository, router, luckyButton) = try makeBackendFailureHarness()
            repository.preparationError = error
            let originalMotivation = controller.motivationLabel.text

            luckyButton.sendActions(for: .touchUpInside)
            let launchTask = try XCTUnwrap(controller.feelingLuckyTask)
            await launchTask.value

            XCTAssertNil(controller.presentedViewController)
            XCTAssertNil(controller.activeQuizPreparationAlert)
            XCTAssertEqual(controller.motivationLabel.text, originalMotivation)
            XCTAssertTrue(luckyButton.isEnabled)
            XCTAssertTrue(controller.themesCollectionView.isUserInteractionEnabled)
            XCTAssertTrue(controller.settingsButton.isEnabled)
            XCTAssertTrue(controller.helpButton.isEnabled)
            XCTAssertEqual(router.showQuestionCallCount, 0)
        }
    }

    func testFeelingLuckyShowsCustomErrorAndPreservesMotivationWhenLocalPoolIsTooSmall() async throws {
        QuizFactory.shared.themes = [
            makeTheme(name: "Музыка", questionCount: 2),
            makeTheme(name: "Технологии", questionCount: 2)
        ]
        let viewController = QuizViewController(randomQuestionsProvider: { $0 })
        let router = HomeRouterSpy()
        viewController.router = router
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        testWindows.append(window)
        let luckyButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeFeelingLuckyButton") as? UIButton
        )
        let motivationLabel = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeMotivationLabel") as? UILabel
        )
        let originalMotivation = motivationLabel.text

        luckyButton.sendActions(for: .touchUpInside)
        try await waitUntil { viewController.presentedViewController != nil }

        XCTAssertNil(QuizFactory.shared.chosenTheme)
        XCTAssertEqual(router.showQuestionCallCount, 0)
        XCTAssertEqual(motivationLabel.text, originalMotivation)
        XCTAssertFalse(viewController.presentedViewController is UIAlertController)
        let alert = try XCTUnwrap(viewController.activeQuizPreparationAlert)
        XCTAssertEqual(alert.message, L10n.Question.unavailableMessage)
        XCTAssertTrue(luckyButton.isEnabled)

        alert.onEscape()
        try await waitUntil { viewController.presentedViewController == nil }

        XCTAssertNil(viewController.activeQuizPreparationAlert)
        XCTAssertEqual(router.showQuestionCallCount, 0)
        XCTAssertEqual(motivationLabel.text, originalMotivation)
    }

    private func assertFeelingLuckyFailureRecovery(error: Error, expectedMessage: String) async throws {
        let (controller, repository, router, luckyButton) = try makeBackendFailureHarness()
        repository.preparationError = error
        let originalMotivation = controller.motivationLabel.text
        let progressView = try XCTUnwrap(
            luckyButton.descendant(withAccessibilityIdentifier: "homeFeelingLuckyProgressView")
                as? UIActivityIndicatorView
        )

        luckyButton.sendActions(for: .touchUpInside)
        let launchTask = try XCTUnwrap(controller.feelingLuckyTask)
        await launchTask.value
        try await waitUntil { controller.presentedViewController != nil }

        let presentedController = try XCTUnwrap(controller.presentedViewController)
        let alert = try XCTUnwrap(controller.activeQuizPreparationAlert)
        XCTAssertFalse(presentedController is UIAlertController)
        XCTAssertEqual(presentedController.view.accessibilityIdentifier, "quizPreparationErrorAlert")
        XCTAssertEqual(presentedController.modalPresentationStyle, .overFullScreen)
        XCTAssertEqual(presentedController.modalTransitionStyle, .crossDissolve)
        XCTAssertEqual(alert.title, L10n.Question.loadingFailedTitle)
        XCTAssertEqual(alert.message, expectedMessage)
        XCTAssertEqual(controller.motivationLabel.text, originalMotivation)
        XCTAssertTrue(luckyButton.isEnabled)
        XCTAssertFalse(progressView.isAnimating)
        XCTAssertEqual(luckyButton.accessibilityLabel, L10n.Home.feelingLucky)
        XCTAssertTrue(controller.themesCollectionView.isUserInteractionEnabled)
        XCTAssertTrue(controller.settingsButton.isEnabled)
        XCTAssertTrue(controller.helpButton.isEnabled)
        XCTAssertFalse(controller.isQuizLaunchPending)
        XCTAssertEqual(router.showQuestionCallCount, 0)

        let backAction = try XCTUnwrap(alert.secondaryAction)
        XCTAssertEqual(backAction.title, L10n.Common.back)
        backAction.action()
        try await waitUntil { controller.presentedViewController == nil }
        XCTAssertNil(controller.activeQuizPreparationAlert)
        XCTAssertEqual(repository.requestedSelectionModes.count, 1)
        XCTAssertEqual(router.showQuestionCallCount, 0)
        XCTAssertEqual(controller.motivationLabel.text, originalMotivation)

        luckyButton.sendActions(for: .touchUpInside)
        let secondLaunchTask = try XCTUnwrap(controller.feelingLuckyTask)
        await secondLaunchTask.value
        try await waitUntil { controller.presentedViewController != nil }
        let retryAlert = try XCTUnwrap(controller.activeQuizPreparationAlert)
        XCTAssertEqual(retryAlert.primaryAction.title, L10n.AITheme.retry)
        repository.preparationError = nil
        router.onShowQuestion = { [weak controller] in
            XCTAssertNil(controller?.presentedViewController)
            XCTAssertNil(controller?.activeQuizPreparationAlert)
        }

        retryAlert.primaryAction.action()
        try await waitUntil { router.showQuestionCallCount == 1 }

        XCTAssertEqual(repository.requestedSelectionModes.count, 3)
        XCTAssertEqual(controller.session.chosenTheme?.questionsAndAnswers.count, 5)
        XCTAssertEqual(controller.motivationLabel.text, originalMotivation)
    }

    private func makeBackendFailureHarness(reduceMotion: Bool = true) throws ->
        (QuizViewController, FeelingLuckyThemeRepositorySpy, HomeRouterSpy, UIButton) {
        let remoteTheme = QuizTheme(
            id: "music", theme: "Музыка", themeDescription: "Описание",
            questions: [], questionOrigin: .backend
        )
        let preparedRound = QuizTheme(
            id: RandomQuizSelection.themeID,
            theme: L10n.Home.randomSelection,
            themeDescription: L10n.Home.feelingLucky,
            questions: makeTheme(name: "Музыка", questionCount: 5).questions,
            questionOrigin: .backend
        )
        let repository = FeelingLuckyThemeRepositorySpy(
            themes: [remoteTheme], catalogOrigin: .backend, preparedRandomQuiz: preparedRound
        )
        let controller = QuizViewController(
            themeRepository: repository,
            session: QuizSessionStore(themes: { repository.themes }),
            motivationPromptProvider: { _ in "Время проверить себя!" },
            cardReduceMotionProvider: { reduceMotion },
            feelingLuckyMinimumFeedbackDelay: {}
        )
        let router = HomeRouterSpy()
        controller.router = router
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        testWindows.append(window)
        let luckyButton = try XCTUnwrap(
            controller.view.descendant(withAccessibilityIdentifier: "homeFeelingLuckyButton") as? UIButton
        )
        return (controller, repository, router, luckyButton)
    }

}

private final class FeelingLuckyThemeRepositorySpy: ThemeRepository {
    var themes: [QuizTheme]?
    let catalogOrigin: QuizCatalogOrigin
    private(set) var requestedSelectionModes: [CrossThemeQuestionSelectionMode] = []
    private(set) var receivedFallbackQuestionCounts: [Int] = []
    var preparationError: Error?
    private let preparedRandomQuiz: QuizTheme?

    init(
        themes: [QuizTheme],
        catalogOrigin: QuizCatalogOrigin = .bundled,
        preparedRandomQuiz: QuizTheme? = nil
    ) {
        self.themes = themes
        self.catalogOrigin = catalogOrigin
        self.preparedRandomQuiz = preparedRandomQuiz
    }

    func loadData(forceReload: Bool) {}

    func fetchQuizThemes() -> [QuizTheme] {
        themes ?? []
    }

    func prepareRandomQuiz(
        selectionMode: CrossThemeQuestionSelectionMode,
        localFallback: QuizTheme,
        questionCount: Int,
        locale: String
    ) async throws -> QuizTheme {
        requestedSelectionModes.append(selectionMode)
        receivedFallbackQuestionCounts.append(localFallback.questions.count)
        if let preparationError { throw preparationError }
        return preparedRandomQuiz ?? localFallback
    }
}

/// Keeps the feedback delay suspended until the test releases it. Main-actor
/// isolation also prevents the async-let child from racing with test assertions.
@MainActor
private final class FeelingLuckyFeedbackDelay {
    private let started: XCTestExpectation
    private var continuation: CheckedContinuation<Void, Never>?
    private var isReleased = false

    init(started: XCTestExpectation) { self.started = started }

    func wait() async {
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }

    func release() {
        isReleased = true
        continuation?.resume()
        continuation = nil
    }
}
