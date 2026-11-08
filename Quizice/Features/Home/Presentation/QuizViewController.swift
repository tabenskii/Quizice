import UIKit

final class QuizViewController: BaseQuizViewController, ThemeCollectionDelegate, QuizCardSlideTransitionSource, QuizHomeReturnHandling {
#if DEBUG
    enum DebugCatalogSourceState: Equatable {
        case loading
        case backend
        case backendStale
        case local

        var title: String {
            switch self {
            case .loading: "CATALOG: LOADING"
            case .backend: "CATALOG: BACKEND"
            case .backendStale: "CATALOG: BACKEND STALE"
            case .local: "CATALOG: LOCAL"
            }
        }
    }
#endif

    enum Content {
        static let settingsIconName = "gear"
        static let helpIconName = "questionmark"
        static let themeCellReuseIdentifier = "themeCell"
    }

    enum AccessibilityID {
        static let rootView = "homeRootView"
        static let motivationLabel = "homeMotivationLabel"
        static let headerStackView = "homeHeaderStackView"
        static let themesCollectionView = "homeThemesCollectionView"
        static let screenStackView = "homeScreenStackView"
        static let settingsButton = "homeSettingsButton"
        static let settingsVisualSurface = "homeSettingsVisualSurface"
        static let helpButton = "homeOnboardingHelpButton"
        static let helpVisualSurface = "homeOnboardingHelpVisualSurface"
#if DEBUG
        static let backendCatalogSource = "homeBackendCatalogSource"
#endif
        static let expandedCard = "homeExpandedThemeCard"
        static let expandedStatisticsCard = "homeExpandedStatisticsCard"
        static let expandedAIThemeCard = "homeExpandedAIThemeCard"
        static let expandedCardBackdrop = "homeExpandedThemeCardBackdrop"
        static let expandedCardBackdropDismissButton = "homeExpandedThemeCardBackdropDismissButton"
        static let expandedCardTransition = "homeExpandedThemeCardTransition"
        static let expandedStatisticsCardTransition = "homeExpandedStatisticsCardTransition"
        static let expandedAIThemeCardTransition = "homeExpandedAIThemeCardTransition"
        static let expandedCardSourceSnapshot = "homeExpandedThemeCardSourceSnapshot"
        static let expandedStatisticsCardSourceSnapshot = "homeExpandedStatisticsCardSourceSnapshot"
        static let expandedAIThemeCardSourceSnapshot = "homeExpandedAIThemeCardSourceSnapshot"
        static let aiThemeAlertRetryButton = "aiThemeAlertRetryButton"
        static let aiThemeAlertDismissButton = "aiThemeAlertDismissButton"
    }

    enum Layout {
        static let headerStackSpacing: CGFloat = 0
        static let headerHorizontalInset: CGFloat = 24
        static let headerControlsTrailingReserve: CGFloat = 72
        static let screenTopInset: CGFloat = 28
        static let screenBottomInset: CGFloat = 0
        static let screenStackSpacing: CGFloat = 0
        static let headerToCollectionSpacing: CGFloat = 22
        static let collectionItemSpacing: CGFloat = 16
        static let collectionHorizontalInset: CGFloat = 24
        static let collectionTopInset: CGFloat = 0
        static let collectionBottomInset: CGFloat = 0
        static let motivationFadeDistance: CGFloat = 72
        static let settingsButtonTopInset: CGFloat = 8
        static let settingsButtonTrailingInset: CGFloat = 14
        static let settingsButtonSize: CGFloat = 44
        static let settingsButtonVisualSize: CGFloat = 36
        static let helpButtonSpacing: CGFloat = 4
        static let visibleCellRowSortingTolerance: CGFloat = 1
        static let scrollActivationTolerance: CGFloat = 1

        static var headerMargins: NSDirectionalEdgeInsets {
            NSDirectionalEdgeInsets(
                top: .zero,
                leading: headerHorizontalInset,
                bottom: .zero,
                trailing: headerControlsTrailingReserve
            )
        }

        static var collectionSectionInsets: UIEdgeInsets {
            UIEdgeInsets(
                top: collectionTopInset,
                left: collectionHorizontalInset,
                bottom: collectionBottomInset,
                right: collectionHorizontalInset
            )
        }

        static var screenMargins: NSDirectionalEdgeInsets {
            NSDirectionalEdgeInsets(
                top: screenTopInset,
                leading: .zero,
                bottom: screenBottomInset,
                trailing: .zero
            )
        }
    }

    enum Typography {
        static let motivationFontSize: CGFloat = 26
        static let actionButtonFontSize: CGFloat = 19
        static let settingsIconPointSize: CGFloat = 14
#if DEBUG
        static let backendSourceFontSize: CGFloat = 10
#endif
        static let unlimitedNumberOfLines = 0
    }

    enum Appearance {
        static let hiddenAlpha: CGFloat = 0
        static let visibleAlpha: CGFloat = 1
        static let headerLayerZPosition: CGFloat = 0
        static let collectionLayerZPosition: CGFloat = 10
        static let controlsLayerZPosition: CGFloat = 20
        static let expandedCardBackdropLayerZPosition: CGFloat = 100
        static let expandedCardLayerZPosition: CGFloat = 110
        static let reducedTransparencyBackdropAlpha: CGFloat = 0.96

        static let primaryButtonBackgroundAlpha: CGFloat = 0.88
        static let primaryButtonCornerRadius: CGFloat = 22
        static let primaryButtonShadowOpacity: Float = 0.24
        static let primaryButtonShadowRadius: CGFloat = 14
        static let primaryButtonShadowOffset = CGSize(width: 0, height: 8)
        static let settingsButtonBackgroundAlpha: CGFloat = 0.14
        static let settingsButtonBorderAlpha: CGFloat = 0.22
        static let settingsButtonShadowOpacity: Float = 0.18
        static let settingsButtonShadowRadius: CGFloat = 12
        static let settingsButtonShadowOffset = CGSize(width: 0, height: 6)

    }

    enum AnimationTiming {
        static let revealDuration: TimeInterval = 0.22
        static let cellFadeInStagger: TimeInterval = 0.04
        static let initialVisibleAlpha: CGFloat = 0.92
        static let cardExpansionDuration: TimeInterval = 0.32
        static let reducedMotionDuration: TimeInterval = 0.18
        static let cardExpansionDampingRatio: CGFloat = 1
    }

    enum ExpandedCardLayout {
        static let horizontalInset: CGFloat = 20
        static let topInset: CGFloat = 72
        static let bottomInset: CGFloat = 20
        static let maximumWidth: CGFloat = 430
        static let minimumHeight: CGFloat = 430
        static let heightToWidthRatio: CGFloat = 1.48
        static let keyboardSpacing: CGFloat = 12
        static let keyboardMinimumTopInset: CGFloat = 8
    }

    var motivationContainerView: UIView!
    var motivationLabel: UILabel!
    var headerStackView: UIStackView!
    var screenStackView: UIStackView!
    var settingsButton: UIButton!
    var settingsButtonVisualSurface: UIView!
    var helpButton: UIButton!
    var helpButtonVisualSurface: UIView!
#if DEBUG
    var isDebugInterfaceHidden = false
    var debugCatalogSourceLabel: InsetLabel!
    var debugCatalogSourceState: DebugCatalogSourceState = .loading {
        didSet { updateDebugCatalogSourceIndicator() }
    }
#endif

    var themesCollectionView: UICollectionView!

    let themeRepository: ThemeRepository
    let session: QuizSessionManaging
    let statisticsStore: StatisticsStore
    let aiQuizThemeService: AIQuizThemeServiceProtocol
    let aiQuizAccessProvider: AIQuizAccessProviding
    let analytics: AnalyticsTracking
    let themesCollectionService: ThemesCollectionService
    let motivationPromptProvider: (String?) -> String
    let randomQuestionsProvider: ([QuizQuestion]) -> [QuizQuestion]
    let randomQuestionSelectionModeProvider: () -> CrossThemeQuestionSelectionMode
    let cardReduceMotionProvider: () -> Bool
    let cardReduceTransparencyProvider: () -> Bool
    let cardDeviceParallaxEnabledProvider: () -> Bool
    let cardMotionProvider: HomeThemeCardMotionProviding
    let aiNow: () -> Date
    let aiRequestIDProvider: () -> UUID
    let feelingLuckyMinimumFeedbackDelay: () async -> Void
    let animationsEngine = Animations()
    let sourceSnapshotFactory = HomeCardSourceSnapshotFactory()
    let homeStore = HomeFeatureStore()
    var homeCardState: HomeThemeCardState { homeStore.cardState }
    var homeAIThemeCardState: HomeAIThemeCardState { homeStore.aiThemeCardState }
    var expandedThemeCardView: ExpandedThemeCardView?
    var expandedStatisticsCardView: ExpandedStatisticsCardView?
    var expandedAIThemeCardView: ExpandedAIThemeCardView?
    var expandedCardBackdropView: UIView?
    var expandedCardBackdropDismissButton: UIButton?
    var expandedCardBlurView: UIVisualEffectView?
    var expandedCardSnapshotView: UIView?
    var expandedCardSourceContentView: UIView?
    var expandedCardSourceContentGeometry: HomeThemeCardContentGeometry?
    var expandedCardTransitionView: ThemeCardExpansionTransitionView?
    var expandedCardInteractionButton: ThemeCardTransitionInteractionButton?
    var expandedCardAnimator: UIViewPropertyAnimator?
    var expandedAIKeyboardAnimator: UIViewPropertyAnimator?
    var expandedTheme: QuizTheme?
    var expandedStatisticsSummary: StatisticsSummary?
    var aiSubmissionTask: Task<Void, Never>?
    var aiProgressTask: Task<Void, Never>?
    var aiAlertPresentationTask: Task<Void, Never>?
    let aiAlertPresenter = QuizAlertPresenter()
    let quizPreparationAlertPresenter = QuizAlertPresenter()
    var activeQuizPreparationAlert: QuizAlertOverlay?
    var feelingLuckyTask: Task<Void, Never>?
    var feelingLuckyRequestID: UUID?
    var backendCatalogRefreshTask: Task<Void, Never>?
    var backendCatalogRefreshRequestID: UUID?
    var showRoundConfigurationAfterExpansion = false
    var quizPreparationTask: Task<Void, Never>?
    weak var quizTransitionSourceView: UIView?
    var isQuizLaunchPending = false
    var hasQuizLaunchStarted = false
    var closeAfterFlipToFront = false
    var focusAIThemePromptAfterFlip = false
    var expandedCardNeedsRefresh = false
    var expandedCardScreenViewTracked = false
    var expandedCardLastTrackedFace: HomeThemeCardFace?
    var expandedAIKeyboardLift: CGFloat = 0
    var expandedAIKeyboardFrame: CGRect?
    var lastLayoutSize: CGSize = .zero
    weak var router: HomeRouting?

    var cardSlideTransitionSourceView: UIView {
        quizTransitionSourceView
            ?? expandedThemeCardView?.transitionSourceView
            ?? expandedAIThemeCardView
            ?? themesCollectionView
    }

    var cardSlideTransitionHorizontalInset: CGFloat { ExpandedCardLayout.horizontalInset }

    var expandedCardContentView: UIView? {
        if let expandedThemeCardView { return expandedThemeCardView }
        if let expandedStatisticsCardView { return expandedStatisticsCardView }
        return expandedAIThemeCardView
    }

    var startupAnimatedViews: [UIView] {
        [motivationLabel, themesCollectionView, settingsButton, helpButton]
    }

    init(
        themeRepository: ThemeRepository = QuizFactory.shared,
        session: QuizSessionManaging = QuizSessionStore.shared,
        statisticsStore: StatisticsStore = StatisticsStore(),
        aiQuizThemeService: AIQuizThemeServiceProtocol = MockAIQuizThemeService(),
        aiQuizAccessProvider: AIQuizAccessProviding = AIQuizAccessStore.shared,
        analytics: AnalyticsTracking = AppMetricaAnalyticsTracker.shared,
        motivationPromptProvider: @escaping (String?) -> String = QuizViewController.randomMotivationPrompt,
        randomQuestionsProvider: @escaping ([QuizQuestion]) -> [QuizQuestion] = { $0.shuffled() },
        randomQuestionSelectionModeProvider: @escaping () -> CrossThemeQuestionSelectionMode = {
            CrossThemeQuestionSelectionMode.allCases.randomElement() ?? .random
        },
        cardReduceMotionProvider: @escaping () -> Bool = { UIAccessibility.isReduceMotionEnabled },
        cardReduceTransparencyProvider: @escaping () -> Bool = { UIAccessibility.isReduceTransparencyEnabled },
        cardDeviceParallaxEnabledProvider: @escaping () -> Bool = { true },
        cardMotionProvider: HomeThemeCardMotionProviding = CoreMotionHomeThemeCardMotionProvider(),
        aiNow: @escaping () -> Date = Date.init,
        aiRequestIDProvider: @escaping () -> UUID = UUID.init,
        feelingLuckyMinimumFeedbackDelay: @escaping () async -> Void = {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    ) {
        self.themeRepository = themeRepository
        self.session = session
        self.statisticsStore = statisticsStore
        self.aiQuizThemeService = aiQuizThemeService
        self.aiQuizAccessProvider = aiQuizAccessProvider
        self.analytics = analytics
        self.motivationPromptProvider = motivationPromptProvider
        self.randomQuestionsProvider = randomQuestionsProvider
        self.randomQuestionSelectionModeProvider = randomQuestionSelectionModeProvider
        self.themesCollectionService = ThemesCollectionService(
            themeRepository: themeRepository,
            statisticsStore: statisticsStore
        )
        self.cardReduceMotionProvider = cardReduceMotionProvider
        self.cardReduceTransparencyProvider = cardReduceTransparencyProvider
        self.cardDeviceParallaxEnabledProvider = cardDeviceParallaxEnabledProvider
        self.cardMotionProvider = cardMotionProvider
        self.aiNow = aiNow
        self.aiRequestIDProvider = aiRequestIDProvider
        self.feelingLuckyMinimumFeedbackDelay = feelingLuckyMinimumFeedbackDelay
        super.init(nibName: nil, bundle: nil)
    }

    deinit {
        aiSubmissionTask?.cancel()
        aiProgressTask?.cancel()
        aiAlertPresentationTask?.cancel()
        feelingLuckyTask?.cancel()
        backendCatalogRefreshTask?.cancel()
        quizPreparationTask?.cancel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    override func loadView() {
        let rootView = UIView()
        rootView.backgroundColor = currentAppearance().backgroundColor
        rootView.accessibilityIdentifier = AccessibilityID.rootView
        view = rootView
        configureProgrammaticSubviews(in: rootView)
        applyAppearance()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installAppearanceObserver()
        installAppearanceTraitObserver()

        configureThemesCollectionService()
        installLocalizationObserver()
        updateThemeAvailabilityMessage()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let layoutSize = view.safeAreaLayoutGuide.layoutFrame.size
        if lastLayoutSize != layoutSize {
            let wasLaidOut = lastLayoutSize != .zero
            lastLayoutSize = layoutSize
            if wasLaidOut {
                themesCollectionService.captureScrollAnchor()
                settleCardForWindowResize()
            }
        }
        if let settingsButtonVisualSurface {
            settingsButton.sendSubviewToBack(settingsButtonVisualSurface)
        }
        if let helpButtonVisualSurface {
            helpButton.sendSubviewToBack(helpButtonVisualSurface)
        }
        updateCollectionTopInset()
        themesCollectionView.layoutIfNeeded()
        themesCollectionService.restoreScrollAnchor()
        updateCollectionScrollAvailability()
        expandedCardBackdropView?.frame = view.bounds
        expandedCardBackdropDismissButton?.frame = view.bounds
        if expandedCardAnimator == nil,
           homeCardState.phase == .expandedFront || homeCardState.phase == .expandedBack
            || homeCardState.phase == .launching {
            expandedThemeCardView?.frame = expandedThemeCardFrame()
            expandedStatisticsCardView?.frame = expandedThemeCardFrame()
            expandedAIThemeCardView?.frame = expandedAIThemeCardFrame()
        }
        if !session.startup1st {
            updateMotivationHeaderVisibility(for: themesCollectionView)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        themesCollectionService.captureScrollAnchor()
        super.viewWillTransition(to: size, with: coordinator)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        restoreHomeAfterQuizIfNeeded()
        themesCollectionView.reloadData()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        restoreHomeAfterQuizIfNeeded()
        analytics.track(.screenView(screen: .home))

        if session.startup1st {
            animateStartupViews()
            session.startup1st = false
        }
    }

    func restoreAccessibilityFocusAfterLaunch() {
        guard isViewLoaded else { return }
        UIAccessibility.post(notification: .screenChanged, argument: motivationLabel)
    }

    override func applyAppearance() {
        guard isViewLoaded else { return }
        let appearance = currentAppearance()
        appearance.applyBackground(to: view)
        overrideUserInterfaceStyle = appearance.resolvedInterfaceStyle

        motivationLabel?.textColor = appearance.screenTextColor
        motivationLabel?.font = appearance.typography.font(size: Typography.motivationFontSize, weight: .bold)
        motivationLabel?.textAlignment = .left
        headerStackView?.alignment = .leading
        headerStackView?.directionalLayoutMargins = Layout.headerMargins

        settingsButton?.backgroundColor = .clear
        settingsButton?.layer.borderWidth = 0
        settingsButton?.layer.shadowOpacity = 0
        settingsButton?.tintColor = appearance.screenTextColor

        helpButton?.backgroundColor = .clear
        helpButton?.layer.borderWidth = 0
        helpButton?.layer.shadowOpacity = 0
        helpButton?.tintColor = appearance.screenTextColor
        helpButtonVisualSurface?.applySurfaceStyle(appearance.iconButton)
        if appearance.designStyle == .classic || appearance.designStyle == .clean {
            helpButtonVisualSurface?.layer.cornerRadius = Layout.settingsButtonVisualSize / 2
            helpButtonVisualSurface?.layer.cornerCurve = .circular
        }
        settingsButtonVisualSurface?.applySurfaceStyle(appearance.iconButton)
        if appearance.designStyle == .classic || appearance.designStyle == .clean {
            settingsButtonVisualSurface?.layer.cornerRadius = Layout.settingsButtonVisualSize / 2
            settingsButtonVisualSurface?.layer.cornerCurve = .circular
        }
        settingsButton?.tintColor = appearance.screenTextColor

#if DEBUG
        updateDebugCatalogSourceIndicator()
#endif

        themesCollectionView?.backgroundColor = .clear
        themesCollectionView?.reloadData()
        refreshExpandedThemeCardAppearance()
    }

    override func applyLocalizedStrings() {
        guard isViewLoaded else { return }
        refreshMotivationPrompt()
        settingsButton.accessibilityLabel = L10n.Settings.title
        helpButton.accessibilityLabel = L10n.Onboarding.helpAccessibilityLabel
        helpButton.accessibilityHint = L10n.Onboarding.helpAccessibilityHint
        themesCollectionView.accessibilityLabel = L10n.Home.themesCollectionAccessibilityLabel
        updateThemeAvailabilityMessage()
        themesCollectionView.reloadData()
        refreshExpandedThemeCardAppearance()
        refreshBackendCatalog()
    }
}
