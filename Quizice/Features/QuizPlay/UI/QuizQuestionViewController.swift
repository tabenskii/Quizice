import UIKit
import AVKit
import SwiftUI

final class QuizQuestionViewController: BaseQuizViewController, QuizQuestionViewControllerProtocol, QuizCardSlideTransitionSource, QuizCardSlideTransitionDestination {
    enum Content {
        static let disabledAnswerPlaceholder = "—"
    }
    
    enum AccessibilityID {
        static let rootView = "questionRootView"
        static let themeLabel = "questionThemeLabel"
        static let questionNumberLabel = "questionNumberLabel"
        static let questionCardView = "questionCardView"
        static let questionCardContentView = "questionCardContentView"
        static let questionInfoButton = "questionInfoButton"
        static let questionExplanationBackButton = "questionExplanationBackButton"
        static let questionExplanationScrollView = "questionExplanationScrollView"
        static let questionExplanationLabel = "questionExplanationLabel"
        static let questionTextLabel = "questionTextLabel"
        static let timerContainerView = "questionTimerContainerView"
        static let timerProgressView = "questionTimerProgressView"
        static let answersStackView = "questionAnswersStackView"
        static let answerButtonPrefix = "questionAnswerButton"
        static let nextButton = "questionNextButton"
        static let closeButton = "questionCloseButton"
#if DEBUG
        static let backendQuestionSource = "questionBackendSource"
#endif
        static let exitAlertConfirmButton = "questionExitAlertConfirmButton"
        static let exitAlertCancelButton = "questionExitAlertCancelButton"
        static let cardContainerView = "questionCardContainerView"
    }
    
    enum Layout {
        static let topInset: CGFloat = 24
        static let rootHorizontalInset: CGFloat = 24
        static let questionNumberTopSpacing: CGFloat = 10
        static let cardTopSpacing: CGFloat = 18
        static let cardHorizontalInset: CGFloat = 20
        static let timerTopInset: CGFloat = 22
        static let timerContainerHeight: CGFloat = 14
        static let timerBarHorizontalInset: CGFloat = 4
        static let timerBarHeight: CGFloat = 8
        static let questionSurroundingMinimumSpacing: CGFloat = 24
        static let questionSurroundingCompactSpacing: CGFloat = 8
        static let questionHorizontalInset: CGFloat = 22
        static let answersHorizontalInset: CGFloat = 18
        static let answerMinimumHeight: CGFloat = 52
        static let answerContentHorizontalInset: CGFloat = 12
        static let answerContentVerticalInset: CGFloat = 6
        static let answersBottomInset: CGFloat = 20
        static let actionTopSpacing: CGFloat = 22
        static let cardBottomInset: CGFloat = 18
        static let actionButtonWidth: CGFloat = 238
        static let primaryActionButtonHeight: CGFloat = 54
        static let bottomMaximumInset: CGFloat = 22
        static let answersStackSpacing: CGFloat = 14
        static let closeButtonSize: CGFloat = 44
        static let cardIconButtonSize: CGFloat = 36
        static let cardIconButtonInset: CGFloat = 12
        static let timerToInfoSpacing: CGFloat = 12
        static let timerHorizontalInset = cardIconButtonInset + cardIconButtonSize + timerToInfoSpacing
        static let cardIconSymbolPointSize: CGFloat = 12
        static let explanationContentVerticalInset: CGFloat = 4
        static let closeButtonTrailingInset: CGFloat = 20
        static let maximumContentWidth: CGFloat = 430
    }
    
    enum Typography {
        static let themeFontSize: CGFloat = 24
        static let questionNumberFontSize: CGFloat = 18
        static let questionFontSize: CGFloat = 26
        static let answerButtonFontSize: CGFloat = 18
        static let actionButtonFontSize: CGFloat = 20
        static let explanationFontSize: CGFloat = 20
        static let themeMinimumScaleFactor: CGFloat = 0.70
        static let questionMinimumScaleFactor: CGFloat = 0.72
        static let answerMinimumScaleFactor: CGFloat = 0.72
        static let fontSearchIterations = 10
        static let maximumFontLayoutPasses = 3
        static let fontSizeComparisonTolerance: CGFloat = 0.1
#if DEBUG
        static let backendSourceFontSize: CGFloat = 9
#endif
        static let unlimitedNumberOfLines = 0
        static let answerButtonNumberOfLines = 0
    }
    
    enum Appearance {
        static let cardBackgroundAlpha: CGFloat = 0.26
        static let cardCornerRadius: CGFloat = 28
        static let cardBorderWidth: CGFloat = 1
        static let cardBorderAlpha: CGFloat = 0.18
        static let cardShadowOpacity: Float = 0.22
        static let cardShadowRadius: CGFloat = 16
        static let cardShadowOffset = CGSize(width: 0, height: 10)
        
        static let timerContainerBackgroundAlpha: CGFloat = 0.14
        static let timerContainerCornerRadius: CGFloat = 8
        static let timerTrackAlpha: CGFloat = 0.25
        static let timerBarCornerRadius: CGFloat = 4
        static let timerActiveColor = UIColor.defaultButton
        static let timerCorrectColor = UIColor.correctAnswerBar
        static let timerWrongColor = UIColor.wrongAnswerBar
        
        static let answerDisabledTitleColor = AppAssetColor.gray.uiColor
        static let answerCornerRadius: CGFloat = 18
        static let answerBorderWidth: CGFloat = 1
        static let answerBorderAlpha: CGFloat = 0.2
        static let answerFeedbackBorderWidth: CGFloat = 4
        static let radarDimmedAnswerAlpha: CGFloat = 0.34
        
        static let disabledButtonTitleAlpha: CGFloat = 0.45
        static let primaryButtonBackgroundAlpha: CGFloat = 0.22
        static let secondaryButtonBackgroundAlpha: CGFloat = 0.12
        static let primaryButtonCornerRadius: CGFloat = 22
        static let secondaryButtonCornerRadius: CGFloat = 20
        static let actionButtonBorderWidth: CGFloat = 1
        static let primaryButtonBorderAlpha: CGFloat = 0.5
        static let secondaryButtonBorderAlpha: CGFloat = 0.34
        static let primaryButtonShadowOpacity: Float = 0.2
        static let secondaryButtonShadowOpacity: Float = 0
        static let actionButtonShadowRadius: CGFloat = 10
        static let actionButtonShadowOffset = CGSize(width: 0, height: 6)
    }
    
    enum AnimationTiming {
        static let answerFeedbackDuration: Double = 0.15
        static let answerFeedbackOptions: UIView.AnimationOptions = [.curveEaseInOut, .allowUserInteraction]
        static let questionNumberTransitionDuration: TimeInterval = 0.18
        static let explanationTransitionDuration: TimeInterval = 0.18
    }
    
    enum ActionButtonStyle {
        case primary
        case secondary
        
        var backgroundAlpha: CGFloat {
            switch self {
            case .primary:
                return Appearance.primaryButtonBackgroundAlpha
            case .secondary:
                return Appearance.secondaryButtonBackgroundAlpha
            }
        }
        
        var cornerRadius: CGFloat {
            switch self {
            case .primary:
                return Appearance.primaryButtonCornerRadius
            case .secondary:
                return Appearance.secondaryButtonCornerRadius
            }
        }
        
        var borderAlpha: CGFloat {
            switch self {
            case .primary:
                return Appearance.primaryButtonBorderAlpha
            case .secondary:
                return Appearance.secondaryButtonBorderAlpha
            }
        }
        
        var shadowOpacity: Float {
            switch self {
            case .primary:
                return Appearance.primaryButtonShadowOpacity
            case .secondary:
                return Appearance.secondaryButtonShadowOpacity
            }
        }
    }

    enum AnswerFeedbackState {
        case normal
        case correct
        case wrong
    }
    
    var themeNameLabel: UILabel!
    var questionNumberLabel: UILabel!
    var questionLabel: UILabel!
    var questionCardView: UIView!
    var questionCardShadowView: UIView!
    var questionCardContentView: UIView!
    var questionBodyScrollView: UIScrollView!
    var questionBodyView: UIView!
    var questionMaximumWidthConstraint: NSLayoutConstraint!
    var previousLayoutSize: CGSize = .zero
    var questionInfoButton: UIButton!
    var questionExplanationBackButton: UIButton!
    var questionExplanationScrollView: UIScrollView!
    var questionExplanationLabel: UILabel!
    var cardContainerView: UIView!
    var timerContainerView: UIView!
    var timerBar: UIProgressView!
    var questionTopSpacingGuide: UILayoutGuide!
    var questionBottomSpacingGuide: UILayoutGuide!
    var answersStackView: UIStackView!
    var answer1Button: UIButton!
    var answer2Button: UIButton!
    var answer3Button: UIButton!
    var answer4Button: UIButton!
    var answerHeightConstraints: [NSLayoutConstraint] = []
    var adaptiveSpacingConstraints: [(constraint: NSLayoutConstraint, regular: CGFloat, compact: CGFloat)] = []
    var nextButton: UIButton!
    var closeButton: UIButton!
#if DEBUG
    var debugQuestionSourceLabel: UILabel!
    var debugQuestionOrigin: QuizQuestionOrigin = .bundled
    var debugThemeSource: QuizThemeSource = .catalog
#endif
    
    let feedbackPlayer = QuizQuestionFeedbackPlayer()
    let fontFitter = QuestionFontFitter(searchIterations: Typography.fontSearchIterations)
    let animationsEngine = Animations()
    let exitAlertPresenter = QuizAlertPresenter()
    var activeExitAlertID: UUID?
    weak var router: QuizPlayRouting?
    var currentAnswerOptions: [QuizAnswerOption] = []
    var answerFeedbackStates: [ObjectIdentifier: AnswerFeedbackState] = [:]
    var isApplicationInterrupted = false
    var currentAnswerWasCorrect: Bool?
    var analytics: AnalyticsTracking = AppMetricaAnalyticsTracker.shared
    var hasLoadedQuestion = false
    var isQuestionTransitionInProgress = false
    var isFittingContentFonts = false
    var isQuestionInfoAvailable = false
    var isQuestionExplanationVisible = false
    weak var outgoingQuestionCardSnapshot: UIView?
    
    var presenter: QuizQuestionPresenterProtocol?

    var cardSlideTransitionSourceView: UIView { questionCardView }
    var cardSlideTransitionDestinationView: UIView { questionCardView }
    var cardSlideTransitionHorizontalInset: CGFloat { Layout.cardHorizontalInset }
    var cardSlideTransitionDestinationCompanionViews: [UIView] {
        var views: [UIView?] = [themeNameLabel, questionNumberLabel]
#if DEBUG
        views.append(debugQuestionSourceLabel)
#endif
        return views.compactMap { $0 }
    }
    
    var answerButtons: [UIButton] {
        [answer1Button, answer2Button, answer3Button, answer4Button]
    }

    var questionChromeViews: [UIView] {
        var views: [UIView?] = [themeNameLabel, questionNumberLabel, nextButton, closeButton]
#if DEBUG
        views.append(debugQuestionSourceLabel)
#endif
        return views.compactMap { $0 }
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
        if presenter == nil {
            configurePresenter(QuizQuestionPresenter(analytics: analytics))
        }
        applyAppearance()
        presenter?.viewDidLoad()
        installQuestionLifecycleObservers()
        installLocalizationObserver()

        feedbackPlayer.prepare()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let availableWidth = view.safeAreaLayoutGuide.layoutFrame.width
        questionMaximumWidthConstraint.constant = AppAdaptiveLayout(width: availableWidth).questionMaximumWidth
        if previousLayoutSize != .zero, previousLayoutSize != view.bounds.size {
            finishQuestionAnimationForResize()
        }
        previousLayoutSize = view.bounds.size
        fitContentFonts()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        analytics.track(.screenView(screen: .quizQuestion, theme: presenter?.analyticsProgress.theme ?? .unknown))
    }

    // MARK: - Timer methods

    func updateProgress(_ progress: Float) {
        timerBar.progress = progress
        timerBar.accessibilityValue = NumberFormatter.localizedString(
            from: NSNumber(value: max(0, min(progress, 1))),
            number: .percent
        )
    }

    /// Removes the countdown bar from the layout AND the accessibility tree when
    /// the presenter is in accessibility mode. Called before the first question
    /// is rendered — since the timer never starts, its zeroed progress would
    /// otherwise look broken and get read out as a stray element.
    func hideTimerBar() {
        timerContainerView?.isHidden = true
        timerContainerView?.accessibilityElementsHidden = true
    }

    func showTimeExpired() {
        currentAnswerWasCorrect = false
        let appearance = currentAppearance()
        colorAndDisableButtons()
        animateTimerBarColor(timerFeedbackColor(isCorrect: false, appearance: appearance))
        feedbackPlayer.notifyError()
        nextButton.isEnabled = true
    }
    
    func configurePresenter(_ presenter: QuizQuestionPresenterProtocol) {
        self.presenter = presenter
        self.presenter?.view = self
#if DEBUG
        configureDebugQuestionSource(
            origin: presenter.questionOrigin,
            themeSource: presenter.themeSource
        )
#endif
    }

#if DEBUG
    func configureDebugQuestionSource(
        origin: QuizQuestionOrigin,
        themeSource: QuizThemeSource
    ) {
        debugQuestionOrigin = origin
        debugThemeSource = themeSource
        updateDebugQuestionSourceIndicator()
    }

    func updateDebugQuestionSourceIndicator() {
        guard let debugQuestionSourceLabel else { return }
        let title: String
        let color: UIColor
        switch debugQuestionOrigin {
        case .bundled:
            title = "LOCAL"
            color = AppAssetColor.fallbackOrange.uiColor
        case .backend:
            title = debugThemeSource == .ai ? "AI BACKEND" : "BACKEND"
            color = AppAssetColor.fallbackGreen.uiColor
        case .directAI:
            title = "DIRECT AI"
            color = AppAssetColor.fallbackBlue.uiColor
        case .mock:
            title = "MOCK"
            color = AppAssetColor.gray.uiColor
        }
        debugQuestionSourceLabel.text = title
        debugQuestionSourceLabel.accessibilityLabel = "Question source: \(title)"
        debugQuestionSourceLabel.backgroundColor = color
    }
#endif

    func prepareForReplay(_ presenter: QuizQuestionPresenterProtocol) {
        loadViewIfNeeded()
        self.presenter?.stopTimer()
        exitAlertPresenter.dismiss()
        activeExitAlertID = nil
        outgoingQuestionCardSnapshot?.removeFromSuperview()
        outgoingQuestionCardSnapshot = nil
        isQuestionTransitionInProgress = false
        hasLoadedQuestion = false
        currentAnswerOptions = []
        setQuestionInfoButtonVisible(false)
        setQuestionExplanationVisible(false, animated: false, movesAccessibilityFocus: false)
        questionExplanationLabel?.text = nil

        questionCardView?.layer.removeAllAnimations()
        questionCardView?.transform = .identity
        questionCardView?.isUserInteractionEnabled = true
        questionChromeViews.forEach { view in
            view.layer.removeAllAnimations()
            view.alpha = 1
            view.transform = .identity
        }

        timerContainerView?.isHidden = false
        timerContainerView?.accessibilityElementsHidden = false
        configurePresenter(presenter)
        presenter.viewDidLoad()
        if isApplicationInterrupted { presenter.pauseTimer() }
        applyAppearance()
        view.layoutIfNeeded()
    }

    override func applyAppearance() {
        guard isViewLoaded else { return }
        let appearance = currentAppearance()
        appearance.applyBackground(to: view)
        overrideUserInterfaceStyle = appearance.resolvedInterfaceStyle

        themeNameLabel?.textColor = appearance.screenTextColor
        themeNameLabel?.font = appearance.typography.font(size: Typography.themeFontSize, weight: .semibold)
        questionNumberLabel?.textColor = appearance.secondaryScreenTextColor
        questionNumberLabel?.font = appearance.typography.font(size: Typography.questionNumberFontSize, weight: .medium)
#if DEBUG
        updateDebugQuestionSourceIndicator()
#endif

        questionCardView?.backgroundColor = .clear
        questionCardShadowView?.applySurfaceStyle(appearance.card)
        questionCardContentView?.backgroundColor = appearance.card.backgroundColor
        questionCardContentView?.layer.cornerRadius = appearance.card.cornerRadius
        questionCardContentView?.layer.cornerCurve = .continuous
        questionCardContentView?.layer.borderWidth = appearance.card.borderWidth
        questionCardContentView?.layer.borderColor = appearance.card.borderColor.cgColor
        questionCardContentView?.layer.masksToBounds = true
        questionLabel?.textColor = appearance.surfaceTextColor
        questionLabel?.font = appearance.typography.font(size: Typography.questionFontSize, weight: .bold)
        questionExplanationLabel?.textColor = appearance.surfaceTextColor
        questionExplanationLabel?.font = appearance.typography.font(
            size: Typography.explanationFontSize,
            weight: .regular
        )

        timerContainerView?.backgroundColor = appearance.progressTrackColor
        timerContainerView?.layer.cornerRadius = min(appearance.card.cornerRadius, Appearance.timerContainerCornerRadius)
        timerBar?.trackTintColor = appearance.progressTrackColor
        setTimerBarColor(currentAnswerWasCorrect.map {
            timerFeedbackColor(isCorrect: $0, appearance: appearance)
        } ?? quizThemeAccentColor(for: appearance))

        answerButtons.forEach { button in
            button.titleLabel?.font = appearance.typography.font(size: Typography.answerButtonFontSize, weight: .semibold)
            button.layer.cornerRadius = min(appearance.row.cornerRadius, Appearance.answerCornerRadius)
            applyAnswerFeedback(
                answerFeedbackStates[ObjectIdentifier(button)] ?? .normal,
                to: button, appearance: appearance
            )
        }
        fitContentFonts()

        nextButton?.applyActionAppearance(
            QuizThemeAccentStyle.primaryButtonStyle(themeID: presenter?.themeID, appearance: appearance),
            appearance: appearance,
            textColor: QuizThemeAccentStyle.primaryButtonTextColor(
                themeID: presenter?.themeID,
                appearance: appearance
            )
        )
        nextButton?.titleLabel?.font = appearance.typography.font(size: Typography.actionButtonFontSize, weight: .semibold)
        closeButton?.applyActionAppearance(
            appearance.iconButton,
            appearance: appearance,
            textColor: appearance.screenTextColor
        )
        [questionInfoButton, questionExplanationBackButton].forEach { button in
            button?.applyActionAppearance(
                appearance.iconButton,
                appearance: appearance,
                textColor: appearance.surfaceTextColor
            )
            button?.layer.cornerRadius = Layout.cardIconButtonSize / 2
            button?.layer.cornerCurve = .circular
        }
    }

    override func applyLocalizedStrings() {
        guard isViewLoaded else { return }
        nextButton.setTitle(L10n.Common.next, for: .normal)
        closeButton.accessibilityLabel = L10n.Common.exit
        timerBar.accessibilityLabel = L10n.Question.timeRemaining
        questionInfoButton.accessibilityLabel = L10n.Question.showExplanation
        questionExplanationBackButton.accessibilityLabel = L10n.Question.showQuestion
    }
}

extension AnalyticsQuizProgress {
    static let empty = AnalyticsQuizProgress(
        theme: .unknown,
        answeredQuestions: 0,
        totalQuestions: 0,
        correctAnswers: 0
    )
}

#if DEBUG
#Preview("Question") {
    let viewController = QuizQuestionViewController()
    viewController.loadViewIfNeeded()
    viewController.loadQuestionToView(
        QuizQuestionViewModel(
            themeName: "История и культура",
            questionText: "Какой город был столицей Российской империи большую часть XVIII века?",
            questionNumberText: "Вопрос №3",
            answers: [
                QuizAnswerOption(id: "0", title: "Москва"),
                QuizAnswerOption(id: "1", title: "Санкт-Петербург"),
                QuizAnswerOption(id: "2", title: "Казань"),
                QuizAnswerOption(id: "3", title: "Новгород")
            ],
            explanation: "Санкт-Петербург был столицей Российской империи большую часть XVIII века."
        )
    )
    viewController.updateProgress(0.62)
    return viewController
}
#endif
