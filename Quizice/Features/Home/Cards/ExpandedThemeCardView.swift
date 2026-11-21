import UIKit

final class ExpandedThemeCardView: UIView, UIGestureRecognizerDelegate {
    enum AccessibilityID {
        static let root = "expandedThemeCardView"
        static let parallaxCarrier = "expandedThemeCardParallaxCarrier"
        static let frontPlane = "expandedThemeCardFrontPlane"
        static let backPlane = "expandedThemeCardBackPlane"
        static let rotatingCarrier = "expandedThemeCardRotatingCarrier"
        static let shadowProxy = "expandedThemeCardShadowProxy"
        static let frontArtworkDepth = "expandedThemeCardFrontArtworkDepth"
        static let frontTitleDepth = "expandedThemeCardFrontTitleDepth"
        static let flipInteractionOverlay = "expandedThemeCardFlipInteractionOverlay"
        static let front = "expandedThemeCardFrontView"
        static let frontSurfaceButton = "expandedThemeCardFrontSurfaceButton"
        static let frontImageShadow = "expandedThemeCardFrontImageShadowView"
        static let frontImage = "expandedThemeCardFrontImageView"
        static let closeButton = "expandedThemeCardCloseButton"
        static let infoButton = "expandedThemeCardInfoButton"
        static let back = "expandedThemeCardBackView"
        static let backSurfaceButton = "expandedThemeCardBackSurfaceButton"
        static let themeNameLabel = "descriptionThemeNameLabel"
        static let descriptionLabel = "descriptionTextLabel"
        static let difficultyLabel = "descriptionDifficultyLabel"
        static let difficultyControl = "descriptionDifficultyPicker"
        static let questionCountLabel = "descriptionPickerCaptionLabel"
        static let questionCountControl = "descriptionQuestionCountPicker"
        static let startButton = "descriptionStartButton"
        static let startActivityIndicator = "descriptionStartActivityIndicator"
        static let backButton = "descriptionBackButton"
        static let unavailableLabel = "expandedThemeCardUnavailableLabel"
    }

    enum Layout {
        static let edgeInset: CGFloat = 20
        static let controlInset: CGFloat = 16
        static let iconButtonSize: CGFloat = 44
        static let frontImageTopInset: CGFloat = 28
        static let frontImageHorizontalInset: CGFloat = 24
        static let frontImageToTitleSpacing: CGFloat = 12
        static let frontTitleBottomInset: CGFloat = 18
        static let frontTitleToInfoSpacing: CGFloat = 12
        static let backHeaderSpacing: CGFloat = 12
        static let backContentSpacing: CGFloat = 14
        static let controlsSpacing: CGFloat = 10
        static let segmentedControlHeight: CGFloat = 44
        static let startButtonMinimumHeight: CGFloat = 54
        static let classicFrontArtworkSize = CGSize(width: 118, height: 118)
        static let cleanFrontArtworkPointSize: CGFloat = 132
        static let radarFrontArtworkPointSize: CGFloat = 176
        static let frontArtworkCenterYOffset: CGFloat = -28
    }

    enum Typography {
        static let frontTitleSize: CGFloat = 28
        static let backTitleSize: CGFloat = 30
        static let descriptionSize: CGFloat = 18
        static let captionSize: CGFloat = 16
        static let unavailableSize: CGFloat = 15
        static let buttonSize: CGFloat = 19
        static let segmentSize: CGFloat = 16
    }

    enum Animation {
        static let flipDuration: TimeInterval = 0.28
        static let reducedMotionDuration: TimeInterval = 0.18
        static let perspectiveDistance: CGFloat = 760
        static let parallaxReturnDuration: TimeInterval = 0.32
        static let parallaxReturnDamping: CGFloat = 0.86
        static let parallaxTransitionSettleDuration: TimeInterval = 0.18
    }

    static let supportedQuestionCounts = QuizQuestionCountPolicy.supportedCounts

    var onClose: (() -> Void)?
    var onFlip: (() -> Void)?
    var onBack: (() -> Void)?
    var onCountryChanged: ((String?) -> Void)?
    var onDifficultyChanged: ((AIQuizDifficulty) -> Void)?
    var onQuestionCountChanged: ((Int) -> Void)?
    var onStart: (() -> Void)?
    var onAccessibilityEscape: (() -> Void)?
    var reduceMotionProvider: () -> Bool = { UIAccessibility.isReduceMotionEnabled }
    var deviceParallaxEnabledProvider: () -> Bool = { true }
    var deviceMotionProvider: HomeThemeCardMotionProviding = CoreMotionHomeThemeCardMotionProvider() {
        didSet {
            oldValue.stop()
            isDeviceMotionActive = false
            updateDeviceParallaxAvailability()
        }
    }

    var frontFocusView: UIView { frontTitleLabel }
    var backFocusView: UIView { backTitleLabel }
    var transitionSourceView: UIView { self }
    var isParallaxSettling: Bool { parallaxReturnAnimator != nil }

    var selectedQuestionCount: Int?
    var selectedDifficulty = AIQuizDifficulty.medium
    let perspectiveStageView = UIView()
    let parallaxPoseProbeView = UIView()
    let shadowProxyView = UIView()
    let rotatingCardView = TwoSidedCardTransformCarrierView()
    let frontPlaneView = UIView()
    let backPlaneView = UIView()
    let frontSurfaceView = UIView()
    let backSurfaceView = UIView()
    let frontFaceView = UIView()
    let backFaceView = UIView()
    let flipInteractionButton = UIButton(type: .custom)

    let frontSurfaceButton = UIButton(type: .custom)
    let frontArtworkDepthView = UIView()
    let frontIconShadowView = UIImageView()
    let frontImageView = UIImageView()
    let frontTitleDepthView = UIView()
    let frontTitleLabel = UILabel()
    let closeButton = UIButton(type: .system)
    let infoButton = UIButton(type: .system)

    let backSurfaceButton = UIButton(type: .custom)
    let backButton = UIButton(type: .system)
    let backTitleLabel = UILabel()
    let descriptionScrollView = UIScrollView()
    let backDescriptionLabel = UILabel()
    let countryButton = UIButton(type: .system)
    var availableCountries: [String] = []
    var selectedCountry: String?
    let difficultyLabel = UILabel()
    let difficultyControl = UISegmentedControl(
        items: AIQuizDifficulty.allCases.map(\.title)
    )
    let questionCountLabel = UILabel()
    let questionCountControl = UISegmentedControl(
        items: ExpandedThemeCardView.supportedQuestionCounts.map { String($0) }
    )
    let unavailableLabel = UILabel()
    let startButton = UIButton(type: .system)
    let startActivityIndicator = UIActivityIndicatorView(style: .medium)
    let backControlsStack = UIStackView()
    lazy var backTapGestureRecognizer = UITapGestureRecognizer(
        target: self,
        action: #selector(backTapped)
    )
    lazy var cardParallaxPanGestureRecognizer = UIPanGestureRecognizer(
        target: self,
        action: #selector(cardParallaxPanned(_:))
    )

    var availableQuestionCounts: Set<Int> = []
    var isStartLoading = false
    var cardCornerRadius: CGFloat = 0
    var frontImageSizeConstraint: NSLayoutConstraint!
    var configuredShadowStyle = AppShadowStyle.none
    var isTransitionShadowHidden = false
    var configuredSurfaceColor = UIColor.clear
    var configuredBorderColor = UIColor.clear
    var configuredBorderWidth: CGFloat = 0
    var isTransitionSurfaceHidden = false
    let deviceParallaxStyle = HomeThemeCardDeviceParallaxStyle.standard
    var parallaxPresentationPhase: HomeThemeCardParallaxPresentationPhase = .inactive
    var isApplicationActive = true
    var isDeviceMotionActive = false
    var isTouchParallaxActive = false
    var touchParallaxStartInput = HomeThemeCardParallaxInput.zero
    var renderedParallaxInput = HomeThemeCardParallaxInput.zero
    var parallaxReturnAnimator: UIViewPropertyAnimator?

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
            containerLayerToReset: layer,
            normalizesFacePresentation: true
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
        },
        animationStateDidChange: { [weak self] in
            self?.updateDeviceParallaxAvailability()
        },
        didSettle: { [weak self] completedFace in
            guard let self else { return }
            UIAccessibility.post(
                notification: .layoutChanged,
                argument: completedFace == .front ? self.frontFocusView : self.backFocusView
            )
        }
    )

    var face: HomeThemeCardFace { faceTransitionDriver.face }
    var isFaceTransitionActive: Bool { faceTransitionDriver.isAnimating }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViewHierarchy()
        configureActions()
        configureParallaxObservers()
        faceTransitionDriver.normalize()
    }

    deinit {
        deviceMotionProvider.stop()
        parallaxReturnAnimator?.stopAnimation(true)
        faceTransitionDriver.cancel(normalize: false)
        NotificationCenter.default.removeObserver(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: cardCornerRadius
        ).cgPath
        shadowProxyView.layer.shadowPath = shadowPath
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            cancelTouchParallaxAndReset()
        }
        updateDeviceParallaxAvailability()
    }

    func configure(
        theme: QuizTheme,
        appearance: AppAppearance,
        availableQuestionCounts: [Int],
        selectedQuestionCount: Int?,
        selectedDifficulty: AIQuizDifficulty = .medium,
        selectedCountry: String? = QuestionCountryStore.shared.country
    ) {
        faceTransitionDriver.cancel()

        let themeID = theme.stableID
        let tintColor = ThemeVisualCatalog.tintColor(for: theme)
        let borderColor = appearance.themeCardBorder(baseColor: tintColor)
        let supportedCounts = Set(Self.supportedQuestionCounts)
        self.availableQuestionCounts = Set(availableQuestionCounts).intersection(supportedCounts)

        let frontArtwork = frontArtworkImage(
            sfSymbolName: theme.sfSymbolName,
            appearance: appearance
        )
        let isSymbolIcon = appearance.designStyle != .radar
        frontIconShadowView.image = isSymbolIcon ? frontArtwork : nil
        frontIconShadowView.tintColor = AppAssetColor.black.uiColor
        frontIconShadowView.alpha = isSymbolIcon ? ThemeIconVisualStyle.shadowAlpha : 0
        frontIconShadowView.transform = isSymbolIcon
            ? CGAffineTransform(translationX: 0, y: ThemeIconVisualStyle.shadowOffset)
            : .identity

        frontImageView.image = frontArtwork
        frontImageView.tintColor = appearance.designStyle == .classic
            ? tintColor
            : borderColor
        frontImageView.transform = .identity
        frontTitleLabel.transform = .identity
        frontArtworkDepthView.transform = .identity
        frontTitleDepthView.transform = .identity
        perspectiveStageView.layer.transform = CATransform3DIdentity
        parallaxPoseProbeView.transform = .identity
        layer.sublayerTransform = CATransform3DIdentity
        renderedParallaxInput = .zero
        frontImageSizeConstraint.constant = frontArtworkPointSize(for: appearance.designStyle)

        frontTitleLabel.text = theme.theme
        backTitleLabel.text = theme.theme
        backDescriptionLabel.text = theme.themeDescription.isEmpty
            ? L10n.ThemeCard.defaultThemeDescription
            : theme.themeDescription
        infoButton.accessibilityValue = theme.theme
        infoButton.accessibilityHint = nil

        applyAppearance(
            appearance,
            themeID: themeID,
            themeTintColor: tintColor,
            borderColor: borderColor
        )
        configureCountries(theme: theme, selectedCountry: selectedCountry)
        configureDifficulty(selectedDifficulty, isAvailable: theme.questionOrigin != .bundled)
        // `configureQuestionCounts` must run before `setStartLoading` so the
        // Start button's enabled state is only ever written once, using the
        // freshly-resolved `selectedQuestionCount`. Doing it the other way
        // around (as before) briefly set `isEnabled` from whatever stale
        // `selectedQuestionCount` a recycled card happened to carry, which
        // could make VoiceOver latch onto a transient "unavailable" state
        // even though the button settles on the correct value moments later.
        configureQuestionCounts(selectedQuestionCount: selectedQuestionCount)
        setStartLoading(false)

        faceTransitionDriver.reset(to: .front)
    }

    func setParallaxPresentationPhase(_ phase: HomeThemeCardParallaxPresentationPhase) {
        guard parallaxPresentationPhase != phase else {
            updateDeviceParallaxAvailability()
            return
        }

        let previousPhase = parallaxPresentationPhase
        parallaxPresentationPhase = phase
        if previousPhase.preservesParallaxContinuity,
           !phase.preservesParallaxContinuity {
            if phase == .inactive {
                // Launch/removal must stop sampling before the router snapshots
                // the transition source; no return animation may outlive the card.
                cancelTouchParallaxAndReset()
            } else {
                settleParallaxForPresentationTransition()
            }
        }
        updateDeviceParallaxAvailability()
    }

    func setFace(
        _ targetFace: HomeThemeCardFace,
        animated: Bool,
        completion: ((HomeThemeCardFace) -> Void)? = nil
    ) {
        faceTransitionDriver.setFace(targetFace, animated: animated, completion: completion)
    }

    func finishFlipForResize() {
        faceTransitionDriver.finishAtRequestedFace()
    }

    func setTransitionShadowHidden(_ isHidden: Bool) {
        isTransitionShadowHidden = isHidden
        let shadow = isHidden ? AppShadowStyle.none : configuredShadowStyle
        shadowProxyView.applyShadow(shadow)
    }

    func setTransitionSurfaceHidden(_ isHidden: Bool) {
        isTransitionSurfaceHidden = isHidden
        applyConfiguredSurfaceAppearance()
    }

    func setTransitionContentProgress(
        _ progress: CGFloat,
        sourceGeometry: HomeThemeCardContentGeometry
    ) {
        layoutIfNeeded()
        let visualState = HomeThemeCardTransitionVisualState(progress: progress)
        let parallaxState = HomeThemeCardExpansionParallaxState(progress: progress)
        let remainingTranslation = 1 - visualState.progress
        let imageTranslation = sourceGeometry.imageTranslation(
            toAlignDestinationCenter: frontArtworkDepthView.center,
            in: bounds.size
        )
        let titleTranslation = sourceGeometry.titleTranslation(
            toAlignDestinationCenter: frontTitleDepthView.center,
            in: bounds.size
        )
        let usesSpatialMotion = !reduceMotionProvider()
        let artworkScale = usesSpatialMotion ? parallaxState.artworkScale : 1
        let titleScale = usesSpatialMotion ? parallaxState.titleScale : 1

        frontArtworkDepthView.transform = CGAffineTransform(
            a: artworkScale,
            b: 0,
            c: 0,
            d: artworkScale,
            tx: imageTranslation.x * remainingTranslation,
            ty: imageTranslation.y * remainingTranslation
        )
        frontTitleDepthView.transform = CGAffineTransform(
            a: titleScale,
            b: 0,
            c: 0,
            d: titleScale,
            tx: titleTranslation.x * remainingTranslation,
            ty: titleTranslation.y * remainingTranslation
        )
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
