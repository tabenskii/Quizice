import SwiftUI
import UIKit

final class QuizFlowCoordinator: NSObject, QuizRouting, UIViewControllerTransitioningDelegate {
    private let window: UIWindow
    private let navigationController: UINavigationController
    private let themeRepository: ThemeRepository
    private let session: QuizSessionManaging
    private let aiQuizThemeService: AIQuizThemeServiceProtocol
    private let aiQuizAccessProvider: AIQuizAccessProviding
    private let accountManager: AccountManaging?
    private let answerOutbox: QuestionAnswerOutboxing
    @MainActor private var dataSynchronizer: AccountDataSynchronizer?
    private let onboardingProgressStore: OnboardingProgressStoring
    private let analytics: AnalyticsTracking
    private let notificationCenter: NotificationCenter
    private let randomQuestionsProvider: ([QuizQuestion]) -> [QuizQuestion]
    private let randomQuestionSelectionModeProvider: () -> CrossThemeQuestionSelectionMode
    private let cardSlideTransitionAnimator = QuizCardSlidePresentationAnimator()
    private let aiReplayAlertPresenter = QuizAlertPresenter()
    private weak var activeQuestionViewController: QuizQuestionViewController?
    private weak var resultViewController: QuizResultViewController?
    private var roundSession: QuizSessionStore?
    private weak var activeOnboardingViewController: UIViewController?
    private var onboardingVisibleThemeIDs: Set<String>?
    private var onboardingSelection: (userID: String?, model: OnboardingThemeSelection)?
    private var pendingSystemViewController: UIViewController?
    private var catalogReplayTask: Task<Void, Never>?
    private var catalogReplayProgressTask: Task<Void, Never>?
    private var aiReplayTask: Task<Void, Never>?
    private var aiReplayProgressTask: Task<Void, Never>?
    private var authenticationEstablishedObserver: NSObjectProtocol?
    private var accountDeletionObserver: NSObjectProtocol?
    private let catalogReplayProgressDelay: () async -> Void

    init(
        window: UIWindow,
        navigationController: UINavigationController = UINavigationController(),
        themeRepository: ThemeRepository = QuizFactory.shared,
        session: QuizSessionManaging = QuizSessionStore.shared,
        aiQuizThemeService: AIQuizThemeServiceProtocol? = nil,
        aiQuizAccessProvider: AIQuizAccessProviding? = nil,
        accountManager: AccountManaging? = nil,
        answerOutbox: QuestionAnswerOutboxing = PersistentQuestionAnswerOutbox.shared,
        onboardingProgressStore: OnboardingProgressStoring = OnboardingProgressStore.shared,
        analytics: AnalyticsTracking = AppMetricaAnalyticsTracker.shared,
        notificationCenter: NotificationCenter = .default,
        randomQuestionsProvider: @escaping ([QuizQuestion]) -> [QuizQuestion] = { $0.shuffled() },
        randomQuestionSelectionModeProvider: @escaping () -> CrossThemeQuestionSelectionMode = {
            CrossThemeQuestionSelectionMode.allCases.randomElement() ?? .random
        },
        catalogReplayProgressDelay: @escaping () async -> Void = {
            try? await Task.sleep(nanoseconds: 750_000_000)
        }
    ) {
        let resolvedAIQuizAccessProvider = aiQuizAccessProvider ?? AIQuizAccessStore.shared
        self.window = window
        self.navigationController = navigationController
        self.themeRepository = themeRepository
        self.session = session
        self.aiQuizThemeService = aiQuizThemeService
            ?? BackendServiceFactory.aiQuizThemeService(accessProvider: resolvedAIQuizAccessProvider)
        self.aiQuizAccessProvider = resolvedAIQuizAccessProvider
        self.accountManager = accountManager
        self.answerOutbox = answerOutbox
        self.onboardingProgressStore = onboardingProgressStore
        self.analytics = analytics
        self.notificationCenter = notificationCenter
        self.randomQuestionsProvider = randomQuestionsProvider
        self.randomQuestionSelectionModeProvider = randomQuestionSelectionModeProvider
        self.catalogReplayProgressDelay = catalogReplayProgressDelay
        super.init()
        authenticationEstablishedObserver = notificationCenter.addObserver(
            forName: .backendAuthenticationEstablished, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refreshAccountData(requiringNewPass: true) }
        }
        accountDeletionObserver = notificationCenter.addObserver(
            forName: .backendAccountDeleted, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.catalogReplayTask?.cancel()
                self.aiReplayTask?.cancel()
                self.dataSynchronizer?.cancel()
                self.roundSession = nil
                self.session.chosenTheme = nil
                (self.navigationController.viewControllers.first as? QuizViewController)?
                    .applyBackendCatalogRefresh(didRefresh: true, locale: AppLocalizationStore.shared.resolvedLanguageCode)
            }
        }
    }

    deinit {
        catalogReplayTask?.cancel()
        catalogReplayProgressTask?.cancel()
        aiReplayTask?.cancel()
        aiReplayProgressTask?.cancel()
        if let authenticationEstablishedObserver { notificationCenter.removeObserver(authenticationEstablishedObserver) }
        if let accountDeletionObserver { notificationCenter.removeObserver(accountDeletionObserver) }
    }

    func start() {
        themeRepository.loadData(forceReload: false)
        let viewController = QuizViewController(
            themeRepository: themeRepository,
            session: session,
            aiQuizThemeService: aiQuizThemeService,
            aiQuizAccessProvider: aiQuizAccessProvider,
            analytics: analytics,
            randomQuestionsProvider: randomQuestionsProvider,
            randomQuestionSelectionModeProvider: randomQuestionSelectionModeProvider
        )
        viewController.router = self
        navigationController.setNavigationBarHidden(true, animated: false)
        navigationController.setViewControllers([viewController], animated: false)
        window.rootViewController = navigationController
    }

    @MainActor
    func prepareInitialCatalog() async {
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        let didRefresh = await themeRepository.refreshBackendCatalog(locale: locale)
        guard !Task.isCancelled else { return }
        let didSynchronizePreferences = await themeRepository.synchronizeThemePreferences(
            locale: locale
        )
        guard !Task.isCancelled else { return }
        refreshOnboardingSelection()
        (navigationController.viewControllers.first as? QuizViewController)?
            .applyBackendCatalogRefresh(
                didRefresh: didRefresh || didSynchronizePreferences,
                locale: locale
            )
    }

    func showQuestion() {
        ResultMessagesRepository.shared.refreshInBackground()
        let viewController = QuizQuestionViewController()
        viewController.analytics = analytics
        viewController.router = self
        viewController.configurePresenter(makeRoundPresenter())
        activeQuestionViewController = viewController
        guard let presentingViewController = navigationController.topViewController else { return }
        presentWithCardSlide(viewController, from: presentingViewController)
    }

    func showResult(_ result: QuizResultState) {
        let viewController = QuizResultViewController()
        resultViewController = viewController
        viewController.analytics = analytics
        viewController.router = self
        viewController.configurePresenter(QuizResultPresenter(result: result, session: roundSession ?? session))
        presentWithCardSlide(viewController, from: presentedViewController)
    }

    func showSettings() {
        let viewController = UIHostingController(rootView: QuizSettingsView(analytics: analytics, accountManager: accountManager))
        viewController.modalPresentationStyle = .pageSheet
        if let sheetPresentationController = viewController.sheetPresentationController {
            sheetPresentationController.detents = [.large()]
            sheetPresentationController.prefersGrabberVisible = true
        }
        presentedViewController.present(viewController, animated: true)
    }

    func presentInitialOnboardingIfNeeded(completion: @escaping () -> Void = {}) {
        guard onboardingProgressStore.needsOnboarding else { completion(); return }
        presentOnboarding(animated: false, completion: completion)
    }

    func restoreInitialAccessibilityFocusAfterLaunch() {
        guard activeOnboardingViewController == nil else { return }
        (navigationController.viewControllers.first as? QuizViewController)?
            .restoreAccessibilityFocusAfterLaunch()
    }

    func showOnboarding() {
        presentOnboarding(animated: true)
    }

    func showSubscription() {
        let presenter = presentedViewController
        let appearance = AppAppearanceStore.shared.appearance(
            compatibleWith: presenter.traitCollection
        )
        let view = SubscriptionPaywallView(
            appearance: appearance,
            analytics: analytics
        )
        let viewController = UIHostingController(rootView: view)
        viewController.modalPresentationStyle = .pageSheet
        if let sheetPresentationController = viewController.sheetPresentationController {
            sheetPresentationController.detents = [.large()]
            sheetPresentationController.prefersGrabberVisible = false
            sheetPresentationController.prefersScrollingExpandsWhenScrolledToEdge = false
        }
        presenter.present(viewController, animated: true)
    }

    func presentSystemViewController(_ viewController: UIViewController) {
        guard activeOnboardingViewController == nil else {
            pendingSystemViewController = viewController
            return
        }
        guard presentedViewController !== viewController else { return }
        presentedViewController.present(viewController, animated: true)
    }

    private func presentOnboarding(animated: Bool, completion: @escaping () -> Void = {}) {
        guard activeOnboardingViewController == nil else { completion(); return }

        let appearance = AppAppearanceStore.shared.appearance(
            compatibleWith: window.traitCollection
        )
        let themes = onboardingThemes
        let visibleIDs = Set(themes.map(\.id))
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        let selection = OnboardingThemeSelection(savedIDs: Set(onboardingProgressStore.orderedPreferredThemeIDs(locale: locale)).intersection(visibleIDs))
        let editingUserID = onboardingProgressStore.preferenceUserID
        onboardingVisibleThemeIDs = visibleIDs
        onboardingSelection = (editingUserID, selection)
        let onboardingView = QuizOnboardingView(
            appearance: appearance, themes: themes, catalogOrigin: themeRepository.catalogOrigin,
            selection: selection,
            onComplete: { [weak self] preferredThemeIDs in
                guard let self, self.onboardingProgressStore.preferenceUserID == editingUserID else { return }
                self.completeOnboarding(preferredThemeIDs: preferredThemeIDs)
            }
        )
        let viewController = UIHostingController(rootView: onboardingView)
        viewController.modalPresentationStyle = .fullScreen
        viewController.overrideUserInterfaceStyle = appearance.resolvedInterfaceStyle
        viewController.view.backgroundColor = .clear
        activeOnboardingViewController = viewController
        analytics.track(.screenView(screen: .onboarding))
        presentedViewController.present(viewController, animated: animated, completion: completion)
    }

    private var onboardingThemes: [OnboardingTheme] {
        (themeRepository.themes ?? themeRepository.fetchQuizThemes()).map {
            OnboardingTheme(
                id: $0.stableID,
                title: $0.theme,
                sfSymbolName: $0.sfSymbolName,
                emoji: $0.emoji,
                colorHex: $0.colorHex
            )
        }
    }

    func completeOnboarding(preferredThemeIDs: Set<String>) {
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        let orderedPreferredThemeIDs = onboardingThemes
            .map(\.id)
            .filter(preferredThemeIDs.contains)
        onboardingProgressStore.complete(
            preferredThemeIDs: orderedPreferredThemeIDs,
            visibleThemeIDs: onboardingVisibleThemeIDs ?? Set(onboardingThemes.map(\.id)),
            initiallySelected: onboardingSelection?.model.savedIDs ?? Set(onboardingProgressStore.orderedPreferredThemeIDs(locale: locale)),
            locale: locale
        )
        (navigationController.viewControllers.first as? QuizViewController)?
            .applyThemePreferencesRefresh(locale: locale)
        Task { @MainActor [weak self] in await self?.refreshAccountData(requiringNewPass: true) }
        let viewController = activeOnboardingViewController
        activeOnboardingViewController = nil
        onboardingVisibleThemeIDs = nil
        onboardingSelection = nil
        guard let viewController else {
            presentPendingSystemViewControllerIfNeeded()
            return
        }
        viewController.dismiss(animated: true) { [weak self] in
            self?.presentPendingSystemViewControllerIfNeeded()
        }
    }

    private func presentPendingSystemViewControllerIfNeeded() {
        guard let viewController = pendingSystemViewController else { return }
        pendingSystemViewController = nil
        presentSystemViewController(viewController)
    }

    @MainActor
    func refreshAccountData() async {
        await refreshAccountData(requiringNewPass: false)
    }

    @MainActor
    private func refreshAccountData(requiringNewPass: Bool) async {
        if dataSynchronizer == nil {
            dataSynchronizer = AccountDataSynchronizer(
                accountManager: accountManager, answerOutbox: answerOutbox, themeRepository: themeRepository
            ) { [weak self] in
                self?.refreshOnboardingSelection()
                (self?.navigationController.viewControllers.first as? QuizViewController)?.refreshVisibleAccountData()
            }
        }
        await dataSynchronizer?.refresh(requiringNewPass: requiringNewPass)
    }

    private func refreshOnboardingSelection() {
        guard let onboardingSelection, let onboardingVisibleThemeIDs,
              onboardingSelection.userID == onboardingProgressStore.preferenceUserID else { return }
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        let savedIDs = Set(onboardingProgressStore.orderedPreferredThemeIDs(locale: locale))
        onboardingSelection.model.applySavedIDs(savedIDs.intersection(onboardingVisibleThemeIDs))
    }

    func closeQuestion() {
        returnToThemes()
    }

    func replayQuiz() {
        guard aiReplayTask == nil, catalogReplayTask == nil else { return }
        if let roundSession {
            session.chosenTheme = roundSession.chosenTheme
            session.questionsCount = roundSession.questionsCount
        }
        if let theme = session.chosenTheme?.quizTheme,
           theme.stableID == "politics_business", !theme.countries.isEmpty {
            returnToThemes { [weak self] in
                (self?.navigationController.viewControllers.first as? QuizViewController)?
                    .configureNextRound(themeID: theme.stableID)
            }
            return
        }
        if session.chosenTheme?.themeID == RandomQuizSelection.themeID {
            replayRandomSelectionQuiz()
            return
        }
        guard let configuration = session.chosenTheme?.aiGenerationConfiguration else {
            replayCatalogQuiz()
            return
        }
        guard aiQuizAccessProvider.isAIQuizAvailable else {
            presentAIReplayFailure(YandexAIQuizThemeServiceError.authenticationRequired)
            return
        }

        let service = aiQuizThemeService
        let startedAt = Date()
        analytics.track(
            .aiGenerationStarted(
                locale: configuration.locale.identifier,
                promptLength: configuration.theme.count,
                questionCount: configuration.questionCount,
                difficulty: configuration.difficulty
            )
        )
        resultViewController?.setReplayGenerationPhase(.analyzing)
        startAIReplayProgressUpdates()
        aiReplayTask = Task { @MainActor [weak self] in
            do {
                let theme = try await service.generateQuizTheme(configuration: configuration)
                try Task.checkCancellation()
                guard let self else { return }
                // If the user switched languages while generation was in
                // flight, the freshly generated questions are for the old
                // locale. Drop the response rather than starting a quiz whose
                // UI language and question language disagree.
                let requestedLanguage = configuration.locale.language.languageCode?.identifier.lowercased()
                if let requestedLanguage,
                   AppLocalizationStore.shared.resolvedLanguageCode != requestedLanguage {
                    self.stopAIReplayLoading()
                    return
                }

                theme.aiGenerationConfiguration = configuration
                self.session.chosenTheme = ThemeModel(quizTheme: theme)
                self.session.questionsCount = configuration.questionCount
                self.analytics.track(
                    .aiGenerationSucceeded(
                        locale: configuration.locale.identifier,
                        questionCount: theme.questions.count,
                        difficulty: configuration.difficulty,
                        durationMilliseconds: Self.durationMilliseconds(since: startedAt)
                    )
                )
                self.stopAIReplayLoading()
                self.presentFreshQuestionController()
            } catch is CancellationError {
                self?.stopAIReplayLoading()
            } catch {
                guard let self else { return }
                self.stopAIReplayLoading()
                let errorCode = (error as? YandexAIQuizThemeServiceError)?.analyticsCode ?? "unexpected"
                self.analytics.track(
                    .aiGenerationFailed(
                        locale: configuration.locale.identifier,
                        errorCode: errorCode,
                        durationMilliseconds: Self.durationMilliseconds(since: startedAt)
                    )
                )
                self.analytics.reportOperationalError(error, context: .aiGeneration(code: errorCode))
                self.presentAIReplayFailure(error)
            }
        }
    }

    private func replayCatalogQuiz() {
        guard let previousTheme = session.chosenTheme else {
            presentCatalogReplayFailure(QuizPreparationError.unavailable)
            return
        }
        let themeID = previousTheme.themeID
        let questionCount = session.questionsCount
        let difficulty = previousTheme.difficulty ?? .medium
        let locale = AppLocalizationStore.shared.resolvedLanguageCode

        catalogReplayTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let preparedTheme = try await self.themeRepository.prepareQuiz(
                    themeID: themeID,
                    questionCount: questionCount,
                    difficulty: difficulty,
                    locale: locale
                )
                try Task.checkCancellation()
                guard
                    self.session.chosenTheme?.themeID == themeID,
                    AppLocalizationStore.shared.resolvedLanguageCode == locale
                else {
                    throw CancellationError()
                }
                guard QuizQuestionCountPolicy.usableQuestionCount(
                    in: preparedTheme.questions.map(QuestionModel.init(quizQuestion:))
                ) > 0 else { throw QuizPreparationError.unavailable }
                self.stopCatalogReplayLoading()
                self.session.chosenTheme = ThemeModel(quizTheme: preparedTheme)
                self.session.questionsCount = questionCount
                self.presentFreshQuestionController()
            } catch is CancellationError {
                self.stopCatalogReplayLoading()
            } catch {
                self.stopCatalogReplayLoading()
                self.analytics.reportOperationalError(error, context: .contentLoad)
                self.presentCatalogReplayFailure(error)
            }
        }
        startCatalogReplayProgress()
    }

    private func startCatalogReplayProgress() {
        catalogReplayProgressTask?.cancel()
        let delay = catalogReplayProgressDelay
        catalogReplayProgressTask = Task { @MainActor [weak self] in
            await delay()
            guard
                !Task.isCancelled,
                let self,
                self.catalogReplayTask != nil
            else { return }
            self.resultViewController?.setReplayLoading(true)
        }
    }

    private func stopCatalogReplayLoading() {
        catalogReplayTask = nil
        catalogReplayProgressTask?.cancel()
        catalogReplayProgressTask = nil
        resultViewController?.setReplayLoading(false)
    }

    private func replayRandomSelectionQuiz() {
        guard let previousTheme = session.chosenTheme,
              previousTheme.themeID == RandomQuizSelection.themeID else { return }
        let localFallback: QuizTheme
        if themeRepository.catalogOrigin == .backend {
            // Backend catalogs contain metadata only. Replay must still request a
            // fresh personalized batch instead of replaying questions in memory.
            localFallback = QuizTheme(
                id: RandomQuizSelection.themeID, theme: L10n.Home.randomSelection,
                themeDescription: L10n.Home.feelingLucky, questions: []
            )
        } else if let selection = RandomQuizSelection.makeTheme(
            from: themeRepository.themes ?? themeRepository.fetchQuizThemes(),
            excluding: previousTheme.quizTheme.questions,
            title: L10n.Home.randomSelection,
            description: L10n.Home.feelingLucky,
            randomizing: randomQuestionsProvider
        ) {
            localFallback = selection
        } else {
            presentCatalogReplayFailure(QuizPreparationError.unavailable)
            return
        }

        let selectionMode = randomQuestionSelectionModeProvider()
        let difficulty = previousTheme.difficulty ?? .medium
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        AppLog.content.notice(
            "🎲 FEELING LUCKY REPLAY: selected backend mode=\(selectionMode.rawValue, privacy: .public) locale=\(locale, privacy: .public)"
        )
        catalogReplayTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let preparedTheme = try await self.themeRepository.prepareRandomQuiz(
                    selectionMode: selectionMode,
                    localFallback: localFallback,
                    questionCount: RandomQuizSelection.questionCount,
                    difficulty: difficulty,
                    locale: locale
                )
                try Task.checkCancellation()
                guard
                    self.session.chosenTheme?.themeID == RandomQuizSelection.themeID,
                    AppLocalizationStore.shared.resolvedLanguageCode == locale
                else {
                    throw CancellationError()
                }
                guard QuizQuestionCountPolicy.usableQuestionCount(
                    in: preparedTheme.questions.map(QuestionModel.init(quizQuestion:))
                ) > 0 else { throw QuizPreparationError.unavailable }
                self.stopCatalogReplayLoading()
                self.session.chosenTheme = ThemeModel(quizTheme: preparedTheme)
                self.session.questionsCount = RandomQuizSelection.questionCount
                self.presentFreshQuestionController()
            } catch is CancellationError {
                self.stopCatalogReplayLoading()
            } catch {
                self.stopCatalogReplayLoading()
                self.analytics.reportOperationalError(error, context: .contentLoad)
                self.presentCatalogReplayFailure(error)
            }
        }
        startCatalogReplayProgress()
    }

    private func startAIReplayProgressUpdates() {
        aiReplayProgressTask?.cancel()
        aiReplayProgressTask = Task { @MainActor [weak self] in
            do {
                for update in AIQuizGenerationPhase.delayedUpdates {
                    try await Task.sleep(nanoseconds: update.delayNanoseconds)
                    try Task.checkCancellation()
                    guard let self, self.aiReplayTask != nil else { return }
                    self.resultViewController?.setReplayGenerationPhase(update.phase)
                }
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func stopAIReplayLoading() {
        aiReplayTask = nil
        aiReplayProgressTask?.cancel()
        aiReplayProgressTask = nil
        resultViewController?.setReplayGenerationPhase(nil)
    }

    private func makeRoundPresenter() -> QuizQuestionPresenter {
        let snapshot = QuizSessionStore(themes: { nil })
        snapshot.chosenTheme = session.chosenTheme.map { ThemeModel(quizTheme: $0.quizTheme.roundSnapshot()) }
        snapshot.questionsCount = session.questionsCount
        roundSession = snapshot
        return QuizQuestionPresenter(session: snapshot, analytics: analytics)
    }

    private func presentFreshQuestionController() {
        if let activeQuestionViewController {
            activeQuestionViewController.prepareForReplay(makeRoundPresenter())
            let replayResultViewController = resultViewController
            resultViewController = nil
            replayResultViewController?.dismiss(animated: false)
            return
        }

        navigationController.dismiss(animated: false) { [weak self] in
            self?.showQuestion()
        }
    }

    func resetAccountNavigation(completion: @escaping () -> Void) {
        dataSynchronizer?.cancel()
        onboardingSelection = nil
        onboardingVisibleThemeIDs = nil
        activeOnboardingViewController = nil
        pendingSystemViewController = nil
        activeQuestionViewController = nil
        resultViewController = nil
        returnToThemes(completion: completion)
    }

    func returnToThemes() {
        returnToThemes(completion: nil)
    }

    private func returnToThemes(completion: (() -> Void)?) {
        catalogReplayTask?.cancel()
        stopCatalogReplayLoading()
        aiReplayTask?.cancel()
        stopAIReplayLoading()
        aiReplayAlertPresenter.dismiss()
        roundSession = nil
        navigationController.popToRootViewController(animated: false)
        (navigationController.viewControllers.first as? QuizHomeReturnHandling)?
            .quizFlowWillReturnToThemes()
        guard navigationController.presentedViewController != nil else {
            completion?()
            return
        }
        navigationController.dismiss(animated: true, completion: completion)
    }

    private func presentCatalogReplayFailure(_ error: Error) {
        guard let resultViewController else { return }
        let alert = UIAlertController(
            title: nil, message: QuizPreparationError.message(for: error), preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.Settings.alertAction, style: .default))
        resultViewController.present(alert, animated: true)
    }

    private func presentAIReplayFailure(_ error: Error) {
        guard let resultViewController else { return }
        let alert = AIQuizGenerationAlert(error: error)
        let dismissAction = QuizAlertAction(
            title: alert.offersEditAction ? L10n.Common.back : L10n.Settings.alertAction,
            emphasis: alert.canRetry ? .secondary : .primary,
            accessibilityIdentifier: "aiReplayAlertDismissButton",
            action: { [weak self] in self?.aiReplayAlertPresenter.dismiss() }
        )
        let retryAction = QuizAlertAction(
            title: L10n.AITheme.retry,
            emphasis: .primary,
            accessibilityIdentifier: "aiReplayAlertRetryButton",
            action: { [weak self] in
                self?.aiReplayAlertPresenter.dismiss { [weak self] in
                    self?.replayQuiz()
                }
            }
        )
        let overlay = QuizAlertOverlay(
            title: alert.title,
            message: alert.message,
            systemImage: alert.kind.systemImage,
            iconColor: alert.kind.iconColor(in: resultViewController.currentAppearance()),
            primaryAction: alert.canRetry ? retryAction : dismissAction,
            secondaryAction: alert.canRetry ? dismissAction : nil,
            onEscape: { [weak self] in self?.aiReplayAlertPresenter.dismiss() }
        )
        aiReplayAlertPresenter.presentingViewController = resultViewController
        _ = aiReplayAlertPresenter.present(
            overlay,
            appearance: resultViewController.currentAppearance(),
            reduceMotion: UIAccessibility.isReduceMotionEnabled
        )
    }

    private static func durationMilliseconds(since startDate: Date) -> Int {
        max(Int(Date().timeIntervalSince(startDate) * 1_000), 0)
    }

    private var presentedViewController: UIViewController {
        var viewController: UIViewController = navigationController
        while let presented = viewController.presentedViewController {
            viewController = presented
        }
        return viewController
    }

    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        presented is QuizCardSlideTransitionDestination ? cardSlideTransitionAnimator : nil
    }

    private func presentWithCardSlide(
        _ viewController: UIViewController & QuizCardSlideTransitionDestination,
        from presentingViewController: UIViewController
    ) {
        viewController.modalPresentationStyle = .custom
        viewController.transitioningDelegate = self
        cardSlideTransitionAnimator.sourceViewController = presentingViewController as? QuizCardSlideTransitionSource
        presentingViewController.present(viewController, animated: true)
    }
}
