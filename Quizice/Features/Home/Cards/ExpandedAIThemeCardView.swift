import UIKit

final class AIThemeGradientBorderView: UIView {
    private let gradientLayer = CAGradientLayer()
    private let borderMaskLayer = CAShapeLayer()

    var colors: [UIColor] = [] {
        didSet {
            gradientLayer.colors = colors.map(\.cgColor)
        }
    }

    var lineWidth: CGFloat = 1.6 {
        didSet { setNeedsLayout() }
    }

    var cornerRadius: CGFloat = 0 {
        didSet { setNeedsLayout() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.mask = borderMaskLayer
        layer.addSublayer(gradientLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds

        let innerBounds = bounds.insetBy(dx: lineWidth, dy: lineWidth)
        let path = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius)
        path.append(
            UIBezierPath(
                roundedRect: innerBounds,
                cornerRadius: max(cornerRadius - lineWidth, 0)
            )
        )
        borderMaskLayer.frame = bounds
        borderMaskLayer.fillColor = AppAssetColor.black.uiColor.cgColor
        borderMaskLayer.fillRule = .evenOdd
        borderMaskLayer.path = path.cgPath
    }
}

final class ExpandedAIThemeCardView: UIView, UITextViewDelegate {
    enum AccessibilityID {
        static let root = "expandedAIThemeCardView"
        static let front = "expandedAIThemeCardFrontView"
        static let back = "expandedAIThemeCardBackView"
        static let closeButton = "expandedAIThemeCardCloseButton"
        static let playButton = "expandedAIThemeCardPlayButton"
        static let backButton = "expandedAIThemeCardBackButton"
        static let promptEditor = "aiThemePromptEditor"
        static let promptValidation = "aiThemePromptValidation"
        static let questionCountSelector = "aiThemeQuestionCountSelector"
        static let difficultySelector = "aiThemeDifficultySelector"
        static let submitButton = "aiThemeSubmitButton"
        static let keyboardDoneButton = "aiThemeKeyboardDoneButton"
        static let progressStatus = "aiThemeProgressStatus"
    }

    enum Layout {
        static let edgeInset: CGFloat = 20
        static let controlInset: CGFloat = 16
        static let iconButtonSize: CGFloat = 44
        static let controlReservation: CGFloat = 56
        static let titleSpacing: CGFloat = 8
        static let sectionSpacing: CGFloat = 18
        static let selectorSpacing: CGFloat = 8
        static let selectorButtonHeight: CGFloat = 44
        static let promptMinimumHeight: CGFloat = 210
        static let promptTextInset: CGFloat = 12
        static let submitMinimumHeight: CGFloat = 54
        static let submitContentSpacing: CGFloat = 10
        static let scrollBottomInset: CGFloat = 76
    }

    enum Typography {
        static let titleSize: CGFloat = 30
        static let subtitleSize: CGFloat = 16
        static let promptSize: CGFloat = 17
        static let sectionTitleSize: CGFloat = 16
        static let optionSize: CGFloat = 15
        static let submitSize: CGFloat = 19
        static let progressSize: CGFloat = 15
    }

    enum Animation {
        static let flipDuration: TimeInterval = 0.28
        static let reducedMotionDuration: TimeInterval = 0.18
        static let perspectiveDistance: CGFloat = 760
    }

    enum Outline {
        static let gradientLineWidth: CGFloat = 1.6
        static let radarGlowOpacity: Float = 0.22
        static let radarGlowRadius: CGFloat = 10
    }

    static let supportedQuestionCounts = AIQuizGenerationConfiguration.supportedQuestionCounts
    static let supportedDifficulties = AIQuizDifficulty.allCases

    static var gradientOutlineColors: [UIColor] {
        AIThemeVisualStyle.gradientColors
    }

    static var gradientOutlineLineWidth: CGFloat {
        Outline.gradientLineWidth
    }

    var onClose: (() -> Void)?
    var onFlip: (() -> Void)?
    var onBack: (() -> Void)?
    var onPromptChanged: ((String) -> Void)?
    var onQuestionCountChanged: ((Int) -> Void)?
    var onDifficultyChanged: ((AIQuizDifficulty) -> Void)?
    var onSubmit: (() -> Void)?
    var onAccessibilityEscape: (() -> Void)?
    var onKeyboardFrameChange: ((CGRect?, TimeInterval, UIView.AnimationOptions) -> Void)?
    var reduceMotionProvider: () -> Bool = { UIAccessibility.isReduceMotionEnabled }

    var frontFocusView: UIView { promptTextView }
    var backFocusView: UIView { backTitleLabel }
    var transitionSourceView: UIView { self }

    var promptContainerMaxYAtRest: CGFloat {
        layoutIfNeeded()
        return frontContentStack.frame.minY + promptContainerView.frame.maxY
    }

    let perspectiveStageView = UIView()
    let shadowProxyView = UIView()
    let rotatingCardView = TwoSidedCardTransformCarrierView()
    let frontPlaneView = UIView()
    let backPlaneView = UIView()
    let frontSurfaceView = UIView()
    let backSurfaceView = UIView()
    let frontFaceView = UIView()
    let backFaceView = UIView()
    let frontOutlineView = AIThemeGradientBorderView()
    let backOutlineView = AIThemeGradientBorderView()
    let flipInteractionButton = UIButton(type: .custom)

    let frontScrollView = UIScrollView()
    let frontContentStack = UIStackView()
    let frontHeaderStack = UIStackView()
    let frontHeaderTextStack = UIStackView()
    let frontHeaderControlSpacer = UIView()
    let frontTitleLabel = UILabel()
    let frontSubtitleLabel = UILabel()
    let promptContainerView = UIView()
    let promptTextView = UITextView()
    let promptPlaceholderLabel = UILabel()
    let promptValidationLabel = UILabel()
    let closeButton = UIButton(type: .system)
    let playButton = UIButton(type: .system)

    let backScrollView = UIScrollView()
    let backContentStack = UIStackView()
    let backHeaderStack = UIStackView()
    let backHeaderControlSpacer = UIView()
    let backTitleLabel = UILabel()
    let backButton = UIButton(type: .system)
    let questionCountLabel = UILabel()
    let questionCountStack = UIStackView()
    let difficultyLabel = UILabel()
    let difficultyStack = UIStackView()
    let submitButton = UIButton(type: .system)
    let submitContentStack = UIStackView()
    let submitActivityIndicator = UIActivityIndicatorView(style: .medium)
    let submitTitleLabel = UILabel()
    let progressLabel = UILabel()
    var questionCountButtons: [UIButton] = []
    var difficultyButtons: [UIButton] = []
    var lastRenderedGenerationPhase: AIQuizGenerationPhase?

    var configuredAppearance: AppAppearance?
    var configuredSurfaceStyle: AppSurfaceStyle?
    var configuredShadowStyle = AppShadowStyle.none
    var cardCornerRadius: CGFloat = 0
    var isTransitionShadowHidden = false
    var isTransitionSurfaceHidden = false
    var selectedQuestionCount = ExpandedAIThemeCardView.supportedQuestionCounts[0]
    var selectedDifficulty = AIQuizDifficulty.medium
    var canRevealConfiguration = false
    var canSubmit = false
    var isSubmitting = false

    private lazy var faceTransitionDriver = TwoSidedCardTransitionDriver(
        surfaces: TwoSidedCardTransitionDriver.Surfaces(
            perspectiveStageView: perspectiveStageView,
            shadowProxyView: shadowProxyView,
            rotatingCardView: rotatingCardView,
            frontPlaneView: frontPlaneView,
            backPlaneView: backPlaneView,
            frontFaceView: frontFaceView,
            backFaceView: backFaceView,
            interactionOverlayView: flipInteractionButton,
            containerLayerToReset: nil,
            normalizesFacePresentation: false
        ),
        perspectiveDistance: Animation.perspectiveDistance,
        configuration: { [weak self] in
            let reducesMotion = self?.reduceMotionProvider() ?? true
            return TwoSidedCardTransitionConfiguration(
                duration: reducesMotion
                    ? Animation.reducedMotionDuration
                    : Animation.flipDuration,
                curve: reducesMotion ? .easeInOut : .linear,
                reducesMotion: reducesMotion
            )
        }
    )

    var face: HomeThemeCardFace { faceTransitionDriver.face }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureHierarchy()
        configureActions()
        configureKeyboardAccessory()
        configureKeyboardObservation()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (cardView: ExpandedAIThemeCardView, _: UITraitCollection) in
            cardView.updateAdaptiveSelectorLayout()
        }
        faceTransitionDriver.normalize()
    }

    deinit {
        faceTransitionDriver.cancel(normalize: false)
        NotificationCenter.default.removeObserver(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        shadowProxyView.layer.cornerRadius = cardCornerRadius
        shadowProxyView.layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: cardCornerRadius
        ).cgPath
    }

    func configure(state: HomeAIThemeCardState, appearance: AppAppearance) {
        configuredAppearance = appearance
        overrideUserInterfaceStyle = appearance.resolvedInterfaceStyle

        if promptTextView.text != state.prompt {
            promptTextView.text = state.prompt
            promptTextView.invalidateIntrinsicContentSize()
        }
        updatePromptPlaceholderVisibility()

        selectedQuestionCount = state.selectedQuestionCount
        selectedDifficulty = state.selectedDifficulty
        isSubmitting = state.isSubmitting
        canRevealConfiguration = state.canRevealConfiguration
        canSubmit = state.canSubmit
        promptValidationLabel.text = state.isPromptTooLong
            ? L10n.AITheme.promptTooLong(maximumLength: AIQuizGenerationConfiguration.maximumThemeLength)
            : nil
        promptValidationLabel.isHidden = !state.isPromptTooLong
        promptValidationLabel.accessibilityElementsHidden = !state.isPromptTooLong

        backTitleLabel.text = state.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if backTitleLabel.text?.isEmpty != false {
            backTitleLabel.text = L10n.AITheme.title
        }
        let generationPhaseChanged = lastRenderedGenerationPhase != state.generationPhase
        lastRenderedGenerationPhase = state.generationPhase
        progressLabel.text = state.generationPhase?.title
        progressLabel.isHidden = state.generationPhase == nil
        progressLabel.accessibilityElementsHidden = state.generationPhase == nil

        if generationPhaseChanged,
           let phase = state.generationPhase,
           UIAccessibility.isVoiceOverRunning {
            DispatchQueue.main.async { [weak self] in
                guard
                    let self,
                    self.window != nil,
                    self.lastRenderedGenerationPhase == phase
                else { return }
                UIAccessibility.post(notification: .announcement, argument: phase.title)
            }
        }

        applyAppearance(appearance)
        renderControls()
    }

    func setFace(
        _ targetFace: HomeThemeCardFace,
        animated: Bool,
        completion: ((HomeThemeCardFace) -> Void)? = nil
    ) {
        if targetFace == .back {
            resignPrompt()
        }
        faceTransitionDriver.setFace(targetFace, animated: animated, completion: completion)
    }

    func finishFlipForResize() {
        faceTransitionDriver.finishAtRequestedFace()
    }

    func setTransitionShadowHidden(_ isHidden: Bool) {
        isTransitionShadowHidden = isHidden
        applyConfiguredShadow()
    }

    func setTransitionSurfaceHidden(_ isHidden: Bool) {
        isTransitionSurfaceHidden = isHidden
        applyConfiguredSurfaceAppearance()
    }

    @discardableResult
    func focusPrompt() -> Bool {
        guard !isSubmitting else { return false }
        return promptTextView.becomeFirstResponder()
    }

    @discardableResult
    func resignPrompt() -> Bool {
        promptTextView.resignFirstResponder()
    }

    override func accessibilityPerformEscape() -> Bool {
        if let onAccessibilityEscape {
            onAccessibilityEscape()
            return true
        }
        if face == .back, let onBack {
            onBack()
            return true
        }
        guard let onClose else { return false }
        onClose()
        return true
    }

}
