import SwiftData
import SwiftUI
import XCTest
@testable import Quizice

@MainActor
final class HomeThemeCardStateTests: HomeScreenVisualStateTestCase {
    func testAppearanceRefreshDuringFlipCompletesReducerAndAllowsClose() throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка", questionCount: 15)]

        let viewController = makeHomeViewController(in: CGRect(x: 0, y: 0, width: 390, height: 844))
        let sourceButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "music") as? UIButton
        )
        sourceButton.sendActions(for: .touchUpInside)
        drainAnimations()
        let infoButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardInfoButton") as? UIButton
        )

        infoButton.sendActions(for: .touchUpInside)
        viewController.applyLocalizedStrings()
        drainAnimations(0.34)

        let backButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "descriptionBackButton") as? UIButton
        )
        backButton.sendActions(for: .touchUpInside)
        drainAnimations(0.34)
        let closeButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardCloseButton") as? UIButton
        )
        closeButton.sendActions(for: .touchUpInside)
        drainAnimations()

        XCTAssertNil(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedThemeCardBackdrop")
        )
    }

    func testExpandedThemeBackDisablesStartWhenNoSupportedCountIsAvailable() throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка", questionCount: 4)]

        let viewController = makeHomeViewController(in: CGRect(x: 0, y: 0, width: 390, height: 844))
        let sourceButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "music") as? UIButton
        )
        sourceButton.sendActions(for: .touchUpInside)
        drainAnimations()
        let infoButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardInfoButton") as? UIButton
        )
        infoButton.sendActions(for: .touchUpInside)
        drainAnimations(0.34)

        let unavailableLabel = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardUnavailableLabel") as? UILabel
        )
        let startButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "descriptionStartButton") as? UIButton
        )
        XCTAssertFalse(unavailableLabel.isHidden)
        XCTAssertEqual(unavailableLabel.text, L10n.Question.unavailableMessage)
        XCTAssertFalse(startButton.isEnabled)
    }

    func testThemeCardPrepareForReuseRestoresVisibleInteractiveState() {
        let cell = ThemeCardCollectionViewCell(frame: CGRect(x: 0, y: 0, width: 160, height: 160))
        let theme = makeTheme(name: "Музыка", questionCount: 5)
        let appearance = AppAppearanceStore.shared.appearance(compatibleWith: .current)
        cell.configure(theme: theme, appearance: appearance, isSourceHidden: true)

        XCTAssertTrue(cell.actionButton.isHidden)
        XCTAssertFalse(cell.actionButton.isUserInteractionEnabled)
        XCTAssertEqual(cell.layer.shadowOpacity, 0)

        cell.prepareForReuse()

        XCTAssertFalse(cell.actionButton.isHidden)
        XCTAssertTrue(cell.actionButton.isUserInteractionEnabled)
        XCTAssertNil(cell.actionButton.accessibilityIdentifier)
        XCTAssertEqual(cell.actionButton.transform, .identity)
        XCTAssertEqual(cell.actionButton.alpha, 1)
    }

    func testExpandedThemeStartButtonShowsAndClearsLoadingIndicator() throws {
        let card = makeHostedExpandedThemeCard(
            motionProvider: HomeThemeCardMotionProviderFake(isAvailable: false)
        )
        let startButton = try XCTUnwrap(
            card.descendant(withAccessibilityIdentifier: "descriptionStartButton") as? UIButton
        )
        let activityIndicator = try XCTUnwrap(
            card.descendant(withAccessibilityIdentifier: "descriptionStartActivityIndicator")
                as? UIActivityIndicatorView
        )

        card.setStartLoading(true)

        XCTAssertFalse(startButton.isEnabled)
        XCTAssertNil(startButton.title(for: .normal))
        XCTAssertTrue(activityIndicator.isAnimating)

        card.setStartLoading(false)

        XCTAssertTrue(startButton.isEnabled)
        XCTAssertEqual(startButton.title(for: .normal), L10n.Common.start)
        XCTAssertFalse(activityIndicator.isAnimating)
    }

    func testBackendOnlyThemeStartsEvenWhenSessionCatalogIsStale() async throws {
        let metadata = QuizTheme(
            id: "space",
            theme: "Космос",
            themeDescription: "Backend-only theme",
            questions: [],
            sfSymbolName: "moon.stars.fill",
            emoji: "🚀",
            colorHex: "#BF5AF2",
            questionOrigin: .backend
        )
        let repository = BackendOnlyHomeThemeRepository(metadata: metadata)
        let session = RoutingSession()
        session.themes = []
        let viewController = QuizViewController(
            themeRepository: repository,
            session: session,
            cardReduceMotionProvider: { true }
        )
        let router = HomeRouterSpy()
        viewController.router = router
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        testWindows.append(window)

        let sourceButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "space") as? UIButton
        )
        sourceButton.sendActions(for: .touchUpInside)
        try await waitUntil { viewController.homeCardState.phase == .expandedFront }
        XCTAssertEqual(session.chosenTheme?.themeID, "space")

        let infoButton = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "expandedThemeCardInfoButton"
            ) as? UIButton
        )
        infoButton.sendActions(for: .touchUpInside)
        try await waitUntil { viewController.homeCardState.phase == .expandedBack }

        let startButton = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "descriptionStartButton"
            ) as? UIButton
        )
        XCTAssertTrue(startButton.isEnabled)
        session.chosenTheme = nil // Catalog invalidation between opening the card and pressing Start.
        startButton.sendActions(for: .touchUpInside)
        try await waitUntil { router.showQuestionCallCount == 1 }

        XCTAssertEqual(repository.preparedThemeIDs, ["space"])
        XCTAssertEqual(session.chosenTheme?.questionsAndAnswers.count, 5)
    }

    func testPreparationFailureUsesCustomAlertAboveExpandedCardAndRetryStartsQuiz() async throws {
        let (controller, repository, router, startButton) = try await makeBackendLaunchHarness()
        repository.preparationError = URLError(.notConnectedToInternet)
        startButton.sendActions(for: .touchUpInside)
        try await waitUntil { controller.presentedViewController != nil }
        let presentedController = try XCTUnwrap(controller.presentedViewController)
        let alert = try XCTUnwrap(controller.activeQuizPreparationAlert)
        XCTAssertFalse(presentedController is UIAlertController)
        XCTAssertEqual(presentedController.view.accessibilityIdentifier, "quizPreparationErrorAlert")
        XCTAssertEqual(presentedController.modalPresentationStyle, .overFullScreen)
        XCTAssertEqual(presentedController.modalTransitionStyle, .crossDissolve)
        XCTAssertEqual(alert.title, L10n.Question.loadingFailedTitle)
        XCTAssertEqual(alert.message, L10n.Question.networkFailureMessage)
        XCTAssertEqual(alert.primaryAction.title, L10n.AITheme.retry)
        XCTAssertEqual(alert.secondaryAction?.title, L10n.Common.back)
        XCTAssertEqual(controller.homeCardState.phase, .expandedBack)
        XCTAssertTrue(startButton.isEnabled)
        XCTAssertEqual(router.showQuestionCallCount, 0)

        repository.preparationError = nil
        router.onShowQuestion = { [weak controller] in
            XCTAssertNil(controller?.presentedViewController)
            XCTAssertNil(controller?.activeQuizPreparationAlert)
        }
        alert.primaryAction.action()
        try await waitUntil { router.showQuestionCallCount == 1 }
        XCTAssertEqual(repository.preparedThemeIDs.count, 2)
    }

    func testPartialPreparedRoundStartsButEmptyPreparedRoundShowsError() async throws {
        let (controller, repository, router, startButton) = try await makeBackendLaunchHarness()
        repository.returnedQuestionCount = 0
        startButton.sendActions(for: .touchUpInside)
        try await waitUntil { controller.presentedViewController != nil }
        let alert = try XCTUnwrap(controller.activeQuizPreparationAlert)
        XCTAssertEqual(alert.message, L10n.Question.unavailableMessage)
        XCTAssertEqual(alert.title, L10n.Question.loadingFailedTitle)
        XCTAssertEqual(alert.primaryAction.title, L10n.AITheme.retry)
        XCTAssertTrue(repository.resetIDs.isEmpty)
        XCTAssertEqual(router.showQuestionCallCount, 0)
        XCTAssertEqual(controller.homeCardState.phase, .expandedBack)
        let backAction = try XCTUnwrap(alert.secondaryAction)
        backAction.action()
        try await waitUntil { controller.presentedViewController == nil }
        XCTAssertNil(controller.activeQuizPreparationAlert)
        XCTAssertEqual(repository.preparedThemeIDs.count, 1)
        XCTAssertEqual(controller.homeCardState.phase, .expandedBack)
        repository.returnedQuestionCount = 3
        startButton.sendActions(for: .touchUpInside)
        try await waitUntil { router.showQuestionCallCount == 1 }
        XCTAssertEqual(controller.session.chosenTheme?.questionsAndAnswers.count, 3)
        XCTAssertEqual(controller.session.questionsCount, 5)
    }

    func testCompletedTopicUsesCustomAlertAndCancelDoesNotResetProgress() async throws {
        let (controller, repository, router, startButton) = try await makeBackendLaunchHarness()
        repository.preparationError = QuizPreparationError.progressComplete(userID: "account-a")
        startButton.sendActions(for: .touchUpInside)
        try await waitUntil { controller.activeQuizPreparationAlert != nil }
        let alert = try XCTUnwrap(controller.activeQuizPreparationAlert)
        XCTAssertFalse(controller.presentedViewController is UIAlertController)
        XCTAssertEqual(controller.presentedViewController?.view.accessibilityIdentifier, "quizProgressCompleteAlert")
        XCTAssertEqual(alert.title, L10n.Question.progressCompleteTitle)
        XCTAssertEqual(alert.message, L10n.Question.progressCompleteMessage)
        XCTAssertEqual(alert.primaryAction.title, L10n.Question.resetProgressAndStart)
        XCTAssertTrue(repository.resetIDs.isEmpty)
        XCTAssertEqual(router.showQuestionCallCount, 0)

        alert.onEscape()
        try await waitUntil { controller.activeQuizPreparationAlert == nil }
        XCTAssertTrue(repository.resetIDs.isEmpty)
        XCTAssertEqual(repository.preparedThemeIDs, ["space"])
        XCTAssertEqual(controller.homeCardState.phase, .expandedBack)
        // Retained actions from an old overlay must not reset a later round.
        alert.primaryAction.action()
        XCTAssertTrue(repository.resetIDs.isEmpty)
    }

    func testCompletedTopicResetStartsFreshRoundWithSameConfigurationExactlyOnce() async throws {
        let (controller, repository, router, startButton) = try await makeBackendLaunchHarness()
        controller.homeStore.send(.questionCountSelected(10))
        controller.homeStore.send(.difficultySelected(.hard))
        repository.preparationError = QuizPreparationError.progressComplete(userID: "account-a")
        startButton.sendActions(for: .touchUpInside)
        try await waitUntil { controller.activeQuizPreparationAlert != nil }
        let alert = try XCTUnwrap(controller.activeQuizPreparationAlert)
        alert.primaryAction.action()
        alert.primaryAction.action()
        try await waitUntil { router.showQuestionCallCount == 1 }

        XCTAssertEqual(repository.resetIDs.count, 1)
        XCTAssertEqual(repository.resetThemeIDs, ["space"])
        XCTAssertEqual(repository.resetUserIDs, ["account-a"])
        XCTAssertEqual(repository.preparedThemeIDs, ["space", "space"])
        XCTAssertEqual(repository.preparedQuestionCounts, [10, 10])
        XCTAssertEqual(repository.preparedDifficulties, [.hard, .hard])
        XCTAssertEqual(repository.preparedLocales, ["ru", "ru"])
        XCTAssertEqual(controller.session.chosenTheme?.questionsAndAnswers.count, 10)
        XCTAssertNil(controller.activeQuizPreparationAlert)
    }

    func testFailedResetRetriesSameIdentifierBeforeFetchingQuestions() async throws {
        let (controller, repository, router, startButton) = try await makeBackendLaunchHarness()
        repository.preparationError = QuizPreparationError.progressComplete(userID: "account-a")
        repository.resetError = URLError(.networkConnectionLost)
        startButton.sendActions(for: .touchUpInside)
        try await waitUntil { controller.activeQuizPreparationAlert != nil }
        try XCTUnwrap(controller.activeQuizPreparationAlert).primaryAction.action()
        try await waitUntil { repository.resetIDs.count == 1 && controller.activeQuizPreparationAlert != nil }
        let failureAlert = try XCTUnwrap(controller.activeQuizPreparationAlert)
        XCTAssertEqual(failureAlert.title, L10n.Question.loadingFailedTitle)
        XCTAssertEqual(failureAlert.message, L10n.Question.networkFailureMessage)
        XCTAssertEqual(repository.preparedThemeIDs.count, 1)
        XCTAssertEqual(router.showQuestionCallCount, 0)
        repository.resetError = nil
        failureAlert.primaryAction.action()
        try await waitUntil { router.showQuestionCallCount == 1 }
        XCTAssertEqual(repository.resetIDs.count, 2)
        XCTAssertEqual(repository.resetIDs[0], repository.resetIDs[1])
        XCTAssertEqual(repository.preparedThemeIDs.count, 2)
    }

    func testFetchFailureAfterSuccessfulResetRetriesFetchWithoutResettingAgain() async throws {
        let (controller, repository, router, startButton) = try await makeBackendLaunchHarness()
        repository.preparationError = QuizPreparationError.progressComplete(userID: "account-a")
        repository.postResetPreparationError = URLError(.notConnectedToInternet)
        startButton.sendActions(for: .touchUpInside)
        try await waitUntil { controller.activeQuizPreparationAlert != nil }
        try XCTUnwrap(controller.activeQuizPreparationAlert).primaryAction.action()
        try await waitUntil { repository.preparedThemeIDs.count == 2 && controller.activeQuizPreparationAlert != nil }
        XCTAssertEqual(repository.resetIDs.count, 1)
        repository.preparationError = nil
        try XCTUnwrap(controller.activeQuizPreparationAlert).primaryAction.action()
        try await waitUntil { router.showQuestionCallCount == 1 }
        XCTAssertEqual(repository.resetIDs.count, 1)
        XCTAssertEqual(repository.preparedThemeIDs.count, 3)
    }

    func testAccountChangeAfterResetAndFetchFailureDoesNotFetchOrLaunchAnotherAccount() async throws {
        let (controller, repository, router, startButton) = try await makeBackendLaunchHarness()
        repository.preparationError = QuizPreparationError.progressComplete(userID: "account-a")
        repository.postResetPreparationError = URLError(.notConnectedToInternet)
        startButton.sendActions(for: .touchUpInside)
        try await waitUntil { controller.activeQuizPreparationAlert != nil }
        try XCTUnwrap(controller.activeQuizPreparationAlert).primaryAction.action()
        try await waitUntil { repository.preparedThemeIDs.count == 2 && controller.activeQuizPreparationAlert != nil }
        let oldAlertID = controller.activeQuizPreparationAlertID
        repository.currentUserID = "account-b"
        repository.preparationError = nil
        try XCTUnwrap(controller.activeQuizPreparationAlert).primaryAction.action()
        try await waitUntil { controller.activeQuizPreparationAlertID != oldAlertID && !controller.isQuizLaunchPending }
        XCTAssertEqual(repository.resetIDs.count, 1)
        XCTAssertEqual(repository.preparedThemeIDs.count, 2)
        XCTAssertEqual(router.showQuestionCallCount, 0)
    }

    func testRemovingCardDuringResetCancelsLaunchAndClearsLoading() async throws {
        let (controller, repository, router, startButton) = try await makeBackendLaunchHarness()
        repository.preparationError = QuizPreparationError.progressComplete(userID: "account-a")
        var resumeReset: CheckedContinuation<Void, Never>?
        repository.resetDelay = { await withCheckedContinuation { resumeReset = $0 } }
        startButton.sendActions(for: .touchUpInside)
        try await waitUntil { controller.activeQuizPreparationAlert != nil }
        let alert = try XCTUnwrap(controller.activeQuizPreparationAlert)
        alert.primaryAction.action()
        try await waitUntil { resumeReset != nil }
        let indicator = try XCTUnwrap(controller.view.descendant(
            withAccessibilityIdentifier: "descriptionStartActivityIndicator") as? UIActivityIndicatorView)
        XCTAssertTrue(indicator.isAnimating)
        XCTAssertFalse(startButton.isEnabled)
        alert.primaryAction.action()
        XCTAssertEqual(repository.resetIDs.count, 1)
        controller.resetExpandedThemeCard()
        XCTAssertFalse(controller.isQuizLaunchPending)
        XCTAssertFalse(indicator.isAnimating)
        resumeReset?.resume()
        await Task.yield()
        XCTAssertEqual(repository.preparedThemeIDs.count, 1)
        XCTAssertEqual(router.showQuestionCallCount, 0)
        XCTAssertNil(controller.activeQuizPreparationAlert)
    }

    func testChangedLocalePreventsResetFromStaleCompletedAlert() async throws {
        let (controller, repository, router, startButton) = try await makeBackendLaunchHarness()
        repository.preparationError = QuizPreparationError.progressComplete(userID: "account-a")
        startButton.sendActions(for: .touchUpInside)
        try await waitUntil { controller.activeQuizPreparationAlert != nil }
        let alert = try XCTUnwrap(controller.activeQuizPreparationAlert)
        AppLocalizationStore.shared.languagePreference = .english
        alert.primaryAction.action()
        try await waitUntil { controller.activeQuizPreparationAlert == nil }
        XCTAssertTrue(repository.resetIDs.isEmpty)
        XCTAssertEqual(router.showQuestionCallCount, 0)
    }

    private func makeBackendLaunchHarness() async throws ->
        (QuizViewController, BackendOnlyHomeThemeRepository, HomeRouterSpy, UIButton) {
        let metadata = QuizTheme(id: "space", theme: "Космос", themeDescription: "Backend", questions: [],
                                 questionOrigin: .backend)
        let repository = BackendOnlyHomeThemeRepository(metadata: metadata)
        let controller = QuizViewController(themeRepository: repository, session: RoutingSession(),
                                            cardReduceMotionProvider: { true })
        let router = HomeRouterSpy()
        controller.router = router
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        testWindows.append(window)
        let source = try XCTUnwrap(controller.view.descendant(withAccessibilityIdentifier: "space") as? UIButton)
        source.sendActions(for: .touchUpInside)
        try await waitUntil { controller.homeCardState.phase == .expandedFront }
        let info = try XCTUnwrap(controller.view.descendant(
            withAccessibilityIdentifier: "expandedThemeCardInfoButton") as? UIButton)
        info.sendActions(for: .touchUpInside)
        try await waitUntil { controller.homeCardState.phase == .expandedBack }
        let start = try XCTUnwrap(controller.view.descendant(
            withAccessibilityIdentifier: "descriptionStartButton") as? UIButton)
        return (controller, repository, router, start)
    }

    func testSlowQuizPreparationShowsStartIndicatorImmediately() async throws {
        let theme = makeTheme(name: "Музыка", questionCount: 15)
        let repository = HangingRoutingThemeRepository(themes: [theme])
        let session = RoutingSession()
        session.themes = [theme]
        let viewController = QuizViewController(
            themeRepository: repository,
            session: session,
            cardReduceMotionProvider: { true }
        )
        let router = HomeRouterSpy()
        viewController.router = router
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        testWindows.append(window)

        let sourceButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "music") as? UIButton
        )
        sourceButton.sendActions(for: .touchUpInside)
        try await waitUntil { viewController.homeCardState.phase == .expandedFront }
        let infoButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardInfoButton") as? UIButton
        )
        infoButton.sendActions(for: .touchUpInside)
        try await waitUntil { viewController.homeCardState.phase == .expandedBack }
        let startButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "descriptionStartButton") as? UIButton
        )
        let activityIndicator = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "descriptionStartActivityIndicator")
                as? UIActivityIndicatorView
        )

        startButton.sendActions(for: .touchUpInside)
        XCTAssertFalse(startButton.isEnabled)
        XCTAssertTrue(activityIndicator.isAnimating)
        try await waitUntil { repository.prepareQuizCallCount == 1 }
        XCTAssertEqual(router.showQuestionCallCount, 0)
        viewController.removeExpandedThemeCardViews()
        XCTAssertFalse(activityIndicator.isAnimating)
    }

    // These two exercise the real production `ThemeCatalogRepository` end to
    // end (real JSON load / real backend-refresh bookkeeping) instead of a
    // hand-populated theme list, to catch regressions in the actual
    // availability pipeline behind the reported "Start always announces
    // unavailable" bug that a fully-mocked repository can't see.
    func testRealBundledCatalogEnablesStartButtonForDefaultThemes() async throws {
        let repository = ThemeCatalogRepository(backendContentAPI: nil)
        repository.loadData(forceReload: true)
        XCTAssertEqual(repository.catalogOrigin, .bundled)

        let session = RoutingSession()
        let viewController = QuizViewController(
            themeRepository: repository,
            session: session,
            cardReduceMotionProvider: { true }
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        testWindows.append(window)

        let sourceButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "music") as? UIButton
        )
        sourceButton.sendActions(for: .touchUpInside)
        try await waitUntil { viewController.homeCardState.phase == .expandedFront }

        let infoButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardInfoButton") as? UIButton
        )
        infoButton.sendActions(for: .touchUpInside)
        try await waitUntil { viewController.homeCardState.phase == .expandedBack }

        let startButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "descriptionStartButton") as? UIButton
        )
        let unavailableLabel = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardUnavailableLabel") as? UILabel
        )
        XCTAssertTrue(startButton.isEnabled, "Start should be enabled: the real bundled catalog has plenty of usable questions")
        XCTAssertTrue(unavailableLabel.isHidden)
    }

    func testRealBackendCatalogEnablesStartButtonEvenBeforeQuestionsAreFetched() async throws {
        let repository = ThemeCatalogRepository(
            backendContentAPI: RecordingBackendContentAPI()
        )
        repository.loadData(forceReload: true)
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        let didRefresh = await repository.refreshBackendCatalog(locale: locale)
        XCTAssertTrue(didRefresh)
        XCTAssertEqual(repository.catalogOrigin, .backend)
        XCTAssertTrue(repository.themes?.first?.questions.isEmpty == true)

        let session = RoutingSession()
        let viewController = QuizViewController(
            themeRepository: repository,
            session: session,
            cardReduceMotionProvider: { true }
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        testWindows.append(window)

        let sourceButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "music") as? UIButton
        )
        sourceButton.sendActions(for: .touchUpInside)
        try await waitUntil { viewController.homeCardState.phase == .expandedFront }

        let infoButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardInfoButton") as? UIButton
        )
        infoButton.sendActions(for: .touchUpInside)
        try await waitUntil { viewController.homeCardState.phase == .expandedBack }

        let startButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "descriptionStartButton") as? UIButton
        )
        XCTAssertTrue(
            startButton.isEnabled,
            "Start should be enabled for backend-origin themes even though their questions aren't fetched yet"
        )
    }
}

private final class BackendOnlyHomeThemeRepository: ThemeRepository {
    var themes: [QuizTheme]?
    let catalogOrigin: QuizCatalogOrigin = .backend
    private(set) var preparedThemeIDs: [String] = []
    var preparationError: Error?
    var returnedQuestionCount: Int?
    private(set) var preparedQuestionCounts: [Int] = []
    private(set) var preparedDifficulties: [AIQuizDifficulty] = []
    private(set) var preparedLocales: [String] = []
    private(set) var resetIDs: [UUID] = []
    private(set) var resetThemeIDs: [String] = []
    private(set) var resetUserIDs: [String] = []
    var currentUserID = "account-a"
    var resetError: Error?
    var postResetPreparationError: Error?
    var resetDelay: (() async -> Void)?

    init(metadata: QuizTheme) {
        themes = [metadata]
    }

    func loadData(forceReload: Bool) {}

    func fetchQuizThemes() -> [QuizTheme] {
        themes ?? []
    }

    func validateQuestionProgressUser(expectedUserID: String) throws {
        guard currentUserID == expectedUserID else { throw QuestionAnswerSyncError.accountChanged }
    }

    func resetQuestionProgress(themeID: String, resetID: UUID, expectedUserID: String) async throws {
        resetIDs.append(resetID)
        resetThemeIDs.append(themeID)
        resetUserIDs.append(expectedUserID)
        await resetDelay?()
        if let resetError { throw resetError }
        preparationError = postResetPreparationError
    }

    func prepareQuiz(
        themeID: String,
        questionCount: Int,
        difficulty: AIQuizDifficulty,
        locale: String
    ) async throws -> QuizTheme {
        preparedQuestionCounts.append(questionCount)
        preparedDifficulties.append(difficulty)
        preparedLocales.append(locale)
        return try await prepareQuiz(themeID: themeID, questionCount: questionCount, locale: locale)
    }

    func prepareQuiz(
        themeID: String,
        questionCount: Int,
        locale: String
    ) async throws -> QuizTheme {
        guard let metadata = themes?.first(where: { $0.stableID == themeID }) else {
            throw QuizPreparationError.unavailable
        }
        preparedThemeIDs.append(themeID)
        if let preparationError { throw preparationError }
        let questions = (0..<(returnedQuestionCount ?? questionCount)).map { index in
            QuizQuestion(
                question: "Remote question \(index)?",
                answers: ["A", "B", "C", "D"],
                correctAnswer: "A"
            )
        }
        return QuizTheme(
            id: metadata.id,
            theme: metadata.theme,
            themeDescription: metadata.themeDescription,
            questions: questions,
            sfSymbolName: metadata.sfSymbolName,
            emoji: metadata.emoji,
            colorHex: metadata.colorHex,
            questionOrigin: .backend
        )
    }
}

extension HomeThemeCardStateTests {
    func testCountryPickerAppearsOnlyOnPoliticsCardBackAndCanChangeEveryRound() throws {
        let card = ExpandedThemeCardView(frame: CGRect(x: 0, y: 0, width: 342, height: 550))
        let appearance = AppAppearance(
            designStyle: .clean, cleanColorSchemePreference: .dark,
            traitCollection: UITraitCollection(userInterfaceStyle: .dark)
        )
        let politics = makeTheme(name: "Политика и бизнес", questionCount: 15)
        politics.id = "politics_business"
        politics.countries = ["DE", "US", "ES", "FR", "IT", "RU"]
        card.configure(theme: politics, appearance: appearance, availableQuestionCounts: [5, 10, 15],
                       selectedQuestionCount: 5, selectedCountry: nil)
        card.setFace(.back, animated: false)
        card.layoutIfNeeded()
        XCTAssertFalse(card.countryButton.isHidden)
        XCTAssertTrue(card.countryButton.isDescendant(of: card.backFaceView))
        XCTAssertTrue(card.backControlsStack.arrangedSubviews.contains(card.countryButton))
        XCTAssertEqual(card.countryButton.menu?.children.count, 7)
        XCTAssertEqual(card.countryButton.accessibilityValue, L10n.ThemeCard.internationalQuestions)
        var choices: [String?] = []
        card.onCountryChanged = { choices.append($0) }
        card.selectCountry("US")
        XCTAssertEqual(card.selectedCountry, "US")
        card.selectCountry("DE")
        card.selectCountry(nil)
        XCTAssertEqual(choices, ["US", "DE", nil])
        card.selectCountry("GB")
        XCTAssertEqual(choices.count, 3)
        card.setStartLoading(true)
        card.selectCountry("US")
        XCTAssertNil(card.selectedCountry)
        XCTAssertFalse(card.countryButton.isEnabled)

        let music = makeTheme(name: "Music", questionCount: 15)
        music.countries = ["US"] // Even unexpected metadata must not expose the picker on other themes.
        card.configure(theme: music, appearance: appearance, availableQuestionCounts: [5], selectedQuestionCount: 5)
        XCTAssertTrue(card.countryButton.isHidden)
        politics.countries = []
        card.configure(theme: politics, appearance: appearance, availableQuestionCounts: [5], selectedQuestionCount: 5)
        XCTAssertTrue(card.countryButton.isHidden)
    }

    func testDifficultyPickerAvailabilitySurvivesBackendAndBundledCardReuse() throws {
        let card = ExpandedThemeCardView(frame: CGRect(x: 0, y: 0, width: 342, height: 550))
        let appearance = AppAppearanceStore.shared.appearance(compatibleWith: .current)
        let theme = makeTheme(name: "Музыка", questionCount: 15)
        var changes: [AIQuizDifficulty] = []
        card.onDifficultyChanged = { changes.append($0) }
        let hardIndex = try XCTUnwrap(AIQuizDifficulty.allCases.firstIndex(of: .hard))
        for origin: QuizQuestionOrigin in [.backend, .bundled, .backend] {
            theme.questionOrigin = origin
            card.configure(theme: theme, appearance: appearance, availableQuestionCounts: [5, 10, 15],
                           selectedQuestionCount: 5, selectedDifficulty: .medium)
            card.setFace(.back, animated: false)
            card.layoutIfNeeded()
            let supported = origin != .bundled
            XCTAssertEqual(card.difficultyLabel.isHidden, !supported)
            XCTAssertEqual(card.difficultyControl.isHidden, !supported)
            XCTAssertEqual(card.difficultyControl.isEnabled, supported)
            XCTAssertEqual(card.difficultyLabel.accessibilityElementsHidden, !supported)
            XCTAssertEqual(card.difficultyControl.accessibilityElementsHidden, !supported)
            let elements = card.backFaceView.accessibilityElements ?? []
            XCTAssertEqual(elements.contains { ($0 as? UIView) === card.difficultyLabel }, supported)
            XCTAssertEqual(elements.contains { ($0 as? UIView) === card.difficultyControl }, supported)
            let previousCount = changes.count
            card.difficultyControl.selectedSegmentIndex = hardIndex
            card.difficultyChanged()
            XCTAssertEqual(changes.count, previousCount + (supported ? 1 : 0))
            XCTAssertEqual(card.selectedDifficulty, supported ? .hard : .medium)
        }
        XCTAssertEqual(changes, [.hard, .hard])
    }

    func testCountryMetadataSurvivesSwiftDataCacheRoundTrip() throws {
        let container = try ModelContainer(for: SwiftDataThemeStore.schema,
                                          configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = SwiftDataThemeStore(context: container.mainContext)
        let theme = makeTheme(name: "Politics", questionCount: 0)
        theme.id = "politics_business"
        theme.countries = ["DE", "US", "ES", "FR", "IT", "RU"]
        store.replaceThemes(with: [theme], locale: "ru", catalogOrigin: .backend)
        let restored = try XCTUnwrap(store.fetchThemes().first)
        XCTAssertEqual(restored.countries, theme.countries)
        XCTAssertEqual(restored.questionOrigin, theme.questionOrigin)
    }

    func testNextRoundOpensPoliticsCardBackForCountrySelection() throws {
        let previousCountry = QuestionCountryStore.shared.country
        defer { QuestionCountryStore.shared.country = previousCountry }
        QuestionCountryStore.shared.country = nil
        let theme = makeTheme(name: "Политика и бизнес", questionCount: 15)
        theme.id = "politics_business"
        theme.countries = ["US", "RU"]
        QuizFactory.shared.themes = [theme]
        let controller = makeHomeViewController(in: CGRect(x: 0, y: 0, width: 390, height: 844))
        controller.configureNextRound(themeID: theme.id)
        drainAnimations(0.8)
        XCTAssertEqual(controller.homeCardState.phase, .expandedBack)
        XCTAssertEqual(controller.expandedThemeCardView?.face, .back)
        XCTAssertEqual(controller.expandedThemeCardView?.countryButton.isHidden, false)
        controller.expandedThemeCardView?.selectCountry("US")
        XCTAssertEqual(QuestionCountryStore.shared.country, "US")
        controller.resetExpandedThemeCard()
        controller.configureNextRound(themeID: theme.id)
        drainAnimations(0.8)
        XCTAssertEqual(controller.expandedThemeCardView?.selectedCountry, "US")
        controller.expandedThemeCardView?.selectCountry("RU")
        XCTAssertEqual(QuestionCountryStore.shared.country, "RU")
    }
}
