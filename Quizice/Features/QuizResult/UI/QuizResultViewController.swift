import UIKit
#if DEBUG
import SwiftUI
#endif

private final class PerfectScoreCardEffectView: UIView {
    private enum Constants {
        static let borderWidth: CGFloat = 2
        static let animationDuration: CFTimeInterval = 1.8
        static let borderGlowRepeatCount: Float = 4
        static let dimBorderOpacity: Float = 0.45
        static let sweepStartLocations: [NSNumber] = [-1, -0.74, -0.52, -0.3, -0.05]
        static let sweepEndLocations: [NSNumber] = [1.05, 1.3, 1.52, 1.74, 2]
    }

    private let colorWashLayer = CAGradientLayer()
    private let borderGradientLayer = CAGradientLayer()
    private let borderMaskLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        clipsToBounds = true
        backgroundColor = .clear

        colorWashLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.systemPurple.withAlphaComponent(0.18).cgColor,
            UIColor.systemCyan.withAlphaComponent(0.24).cgColor,
            UIColor.systemYellow.withAlphaComponent(0.16).cgColor,
            UIColor.clear.cgColor
        ]
        colorWashLayer.startPoint = CGPoint(x: 0, y: 0)
        colorWashLayer.endPoint = CGPoint(x: 1, y: 1)
        colorWashLayer.locations = Constants.sweepEndLocations
        layer.addSublayer(colorWashLayer)

        borderGradientLayer.colors = [
            UIColor.systemPurple.cgColor,
            UIColor.systemCyan.cgColor,
            UIColor.systemYellow.cgColor,
            UIColor.systemPink.cgColor
        ]
        borderGradientLayer.startPoint = CGPoint(x: 0, y: 0)
        borderGradientLayer.endPoint = CGPoint(x: 1, y: 1)
        borderGradientLayer.opacity = Constants.dimBorderOpacity
        borderGradientLayer.mask = borderMaskLayer
        layer.addSublayer(borderGradientLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        colorWashLayer.frame = bounds
        borderGradientLayer.frame = bounds
        borderMaskLayer.frame = bounds
        borderMaskLayer.fillColor = UIColor.clear.cgColor
        borderMaskLayer.strokeColor = UIColor.white.cgColor
        borderMaskLayer.lineWidth = Constants.borderWidth
        borderMaskLayer.path = UIBezierPath(
            roundedRect: bounds.insetBy(
                dx: Constants.borderWidth / 2,
                dy: Constants.borderWidth / 2
            ),
            cornerRadius: max(layer.cornerRadius - Constants.borderWidth / 2, 0)
        ).cgPath
    }

    func start(reduceMotion: Bool) {
        stop()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The model layer rests fully past the trailing edge. This prevents a
        // colored frame before the animation starts and leaves the card clear
        // after the one-shot sweep is removed.
        colorWashLayer.locations = Constants.sweepEndLocations
        borderGradientLayer.opacity = reduceMotion ? 0.72 : 1
        CATransaction.commit()
        guard !reduceMotion else { return }

        let sweep = CABasicAnimation(keyPath: "locations")
        sweep.fromValue = Constants.sweepStartLocations
        sweep.toValue = Constants.sweepEndLocations
        sweep.duration = Constants.animationDuration
        sweep.repeatCount = 0
        sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        colorWashLayer.add(sweep, forKey: "perfectScoreSweep")

        let glow = CABasicAnimation(keyPath: "opacity")
        glow.fromValue = Constants.dimBorderOpacity
        glow.toValue = 1
        glow.duration = Constants.animationDuration / 2
        glow.autoreverses = true
        glow.repeatCount = Constants.borderGlowRepeatCount
        glow.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        borderGradientLayer.add(glow, forKey: "perfectScoreGlow")
    }

    func stop() {
        colorWashLayer.removeAllAnimations()
        borderGradientLayer.removeAllAnimations()
    }
}

final class QuizResultViewController: BaseQuizViewController, QuizResultViewControllerProtocol, QuizCardSlideTransitionDestination {
    private enum AccessibilityID {
        static let rootView = "resultRootView"
        static let cardView = "resultCardView"
        static let perfectScoreEffect = "resultPerfectScoreEffect"
        static let scoreLabel = "resultScoreLabel"
        static let descriptionLabel = "resultDescriptionLabel"
        static let replayButton = "resultReplayButton"
        static let replayLoadingContent = "resultReplayLoadingContent"
        static let replayActivityIndicator = "resultReplayActivityIndicator"
        static let replayProgressStatus = "resultReplayProgressStatus"
        static let themesButton = "resultThemesButton"
        static let contentStackView = "resultContentStackView"
        static let scrollView = "resultScrollView"
    }
    
    private enum Layout {
        static let contentStackSpacing: CGFloat = 22
        static let resultLabelBottomSpacing: CGFloat = 26
        static let descriptionBottomSpacing: CGFloat = 38
        static let cardHorizontalInset: CGFloat = 20
        static let cardVerticalMinimumInset: CGFloat = 48
        static let contentTopInset: CGFloat = 34
        static let contentHorizontalInset: CGFloat = 24
        static let contentBottomInset: CGFloat = 30
        static let actionButtonHeight: CGFloat = 56
        static let maximumContentWidth: CGFloat = 430
        static let actionButtonSpacing: CGFloat = 12
        static let replayLoadingContentSpacing: CGFloat = 10
    }
    
    private enum Typography {
        static let resultFontSize: CGFloat = 38
        static let descriptionFontSize: CGFloat = 21
        static let buttonFontSize: CGFloat = 20
        static let progressFontSize: CGFloat = 15
        static let unlimitedNumberOfLines = 0
        static let resultMinimumScaleFactor: CGFloat = 0.82
    }
    
    private enum Appearance {
        static let cardBackgroundAlpha: CGFloat = 0.26
        static let cardCornerRadius: CGFloat = 30
        static let cardBorderWidth: CGFloat = 1
        static let cardBorderAlpha: CGFloat = 0.18
        static let cardShadowOpacity: Float = 0.22
        static let cardShadowRadius: CGFloat = 16
        static let cardShadowOffset = CGSize(width: 0, height: 10)
        
        static let descriptionTextAlpha: CGFloat = 0.9
        static let disabledButtonTitleAlpha: CGFloat = 0.45
        static let buttonBackgroundAlpha: CGFloat = 0.22
        static let buttonCornerRadius: CGFloat = 22
        static let buttonBorderWidth: CGFloat = 1
        static let buttonBorderAlpha: CGFloat = 0.5
        static let buttonShadowOpacity: Float = 0.2
        static let buttonShadowRadius: CGFloat = 10
        static let buttonShadowOffset = CGSize(width: 0, height: 6)
    }

    private var scrollView: UIScrollView!
    private var maximumWidthConstraint: NSLayoutConstraint!
    private var resultCardView: UIView!
    private var perfectScoreEffectView: PerfectScoreCardEffectView!
    private var contentStackView: UIStackView!
    private var resultLabel: UILabel!
    private var resultDescription: UILabel!
    
    private var replayButton: UIButton!
    private var replayLoadingContentStack: UIStackView!
    private var replayActivityIndicator: UIActivityIndicatorView!
    private var replayLoadingTitleLabel: UILabel!
    private var replayProgressLabel: UILabel!
    private var themesButton: UIButton!
    private var replayGenerationPhase: AIQuizGenerationPhase?
    private var isReplayLoading = false
    private var isPerfectScoreEffectVisible = false
    private var hasPlayedPerfectScoreEffect = false
    weak var router: QuizResultRouting?
    var analytics: AnalyticsTracking = AppMetricaAnalyticsTracker.shared
    
    var presenter: QuizResultPresenterProtocol?

    var cardSlideTransitionDestinationView: UIView { resultCardView }
    var cardSlideTransitionHorizontalInset: CGFloat { Layout.cardHorizontalInset }
    
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
        presenter?.viewDidLoad()
        installLocalizationObserver()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        maximumWidthConstraint.constant = AppAdaptiveLayout(
            width: view.safeAreaLayoutGuide.layoutFrame.width
        ).resultMaximumWidth
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        analytics.track(.screenView(screen: .quizResult, theme: presenter?.analyticsTheme ?? .unknown))
        startPerfectScoreEffectIfNeeded()
        announceResultIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        perfectScoreEffectView.stop()
    }

    // VO doesn't pick up the score label reliably during the card slide-in —
    // post the pre-built announcement so users who can't see the number
    // still hear it. The string is formatted by the presenter (this view is
    // forbidden from referencing score fields directly by S03 contract).
    private func announceResultIfNeeded() {
        guard UIAccessibility.isVoiceOverRunning else { return }
        guard let announcement = presenter?.resultAnnouncement, !announcement.isEmpty else { return }
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }

    func configurePresenter(_ presenter: QuizResultPresenterProtocol) {
        self.presenter = presenter
        self.presenter?.view = self
        applyAppearance()
    }
    
    func updateResultLabels(resultText: String, descriptionText: String) {
        resultLabel.text = resultText
        resultDescription.text = descriptionText
    }

    func setPerfectScoreEffectVisible(_ isVisible: Bool) {
        isPerfectScoreEffectVisible = isVisible
        perfectScoreEffectView.isHidden = !isVisible
        if !isVisible {
            perfectScoreEffectView.stop()
        }
    }

    private func startPerfectScoreEffectIfNeeded() {
        guard isPerfectScoreEffectVisible, !hasPlayedPerfectScoreEffect else { return }
        hasPlayedPerfectScoreEffect = true
        perfectScoreEffectView.start(reduceMotion: UIAccessibility.isReduceMotionEnabled)
    }

    func setReplayGenerationPhase(_ phase: AIQuizGenerationPhase?) {
        guard isViewLoaded else { return }
        let previousPhase = replayGenerationPhase
        replayGenerationPhase = phase
        isReplayLoading = phase != nil
        renderReplayLoading(
            isLoading: isReplayLoading,
            loadingTitle: L10n.AITheme.generating,
            progressTitle: phase?.title
        )

        if previousPhase != phase,
           let phase,
           UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: phase.title)
        }
    }

    func setReplayLoading(_ isLoading: Bool) {
        guard isViewLoaded else { return }
        replayGenerationPhase = nil
        isReplayLoading = isLoading
        renderReplayLoading(
            isLoading: isLoading,
            loadingTitle: L10n.Home.feelingLuckyLoading,
            progressTitle: nil
        )
    }

    private func renderReplayLoading(
        isLoading: Bool,
        loadingTitle: String,
        progressTitle: String?
    ) {
        replayButton.isEnabled = !isLoading
        replayButton.setTitle(isLoading ? nil : L10n.Result.playAgain, for: .normal)
        replayLoadingContentStack.isHidden = !isLoading
        replayLoadingTitleLabel.text = loadingTitle
        replayProgressLabel.text = progressTitle
        replayProgressLabel.isHidden = progressTitle == nil
        replayProgressLabel.accessibilityElementsHidden = progressTitle == nil
        replayButton.accessibilityLabel = isLoading
            ? loadingTitle
            : L10n.Result.playAgain
        if isLoading {
            replayActivityIndicator.startAnimating()
        } else {
            replayActivityIndicator.stopAnimating()
        }
        replayButton.accessibilityTraits = isLoading
            ? replayButton.accessibilityTraits.union(.updatesFrequently)
            : replayButton.accessibilityTraits.subtracting(.updatesFrequently)
    }
    
    private func configureProgrammaticSubviews(in rootView: UIView) {
        configureResultCardView()
        configureLabels()
        configureActionButtons()
        configureContentStackView()
        addSubviews(to: rootView)
        activateLayoutConstraints(in: rootView)
    }
    
    private func configureResultCardView() {
        resultCardView = UIView()
        resultCardView.accessibilityIdentifier = AccessibilityID.cardView
        resultCardView.backgroundColor = AppAssetColor.black.uiColor.withAlphaComponent(
            Appearance.cardBackgroundAlpha
        )
        resultCardView.layer.cornerRadius = Appearance.cardCornerRadius
        resultCardView.layer.borderWidth = Appearance.cardBorderWidth
        resultCardView.layer.borderColor = AppAssetColor.white.uiColor
            .withAlphaComponent(Appearance.cardBorderAlpha)
            .cgColor
        resultCardView.layer.shadowColor = AppAssetColor.black.uiColor.cgColor
        resultCardView.layer.shadowOpacity = Appearance.cardShadowOpacity
        resultCardView.layer.shadowRadius = Appearance.cardShadowRadius
        resultCardView.layer.shadowOffset = Appearance.cardShadowOffset
        resultCardView.translatesAutoresizingMaskIntoConstraints = false

        perfectScoreEffectView = PerfectScoreCardEffectView()
        perfectScoreEffectView.accessibilityIdentifier = AccessibilityID.perfectScoreEffect
        perfectScoreEffectView.layer.cornerRadius = Appearance.cardCornerRadius
        perfectScoreEffectView.layer.cornerCurve = .continuous
        perfectScoreEffectView.isHidden = true
        perfectScoreEffectView.translatesAutoresizingMaskIntoConstraints = false
        resultCardView.addSubview(perfectScoreEffectView)
        NSLayoutConstraint.activate([
            perfectScoreEffectView.leadingAnchor.constraint(equalTo: resultCardView.leadingAnchor),
            perfectScoreEffectView.trailingAnchor.constraint(equalTo: resultCardView.trailingAnchor),
            perfectScoreEffectView.topAnchor.constraint(equalTo: resultCardView.topAnchor),
            perfectScoreEffectView.bottomAnchor.constraint(equalTo: resultCardView.bottomAnchor)
        ])
    }
    
    private func configureLabels() {
        let typography = currentAppearance().typography
        resultLabel = makeLabel(font: typography.font(size: Typography.resultFontSize, weight: .bold), accessibilityIdentifier: AccessibilityID.scoreLabel)
        resultLabel.numberOfLines = Typography.unlimitedNumberOfLines
        
        resultDescription = makeLabel(font: typography.font(size: Typography.descriptionFontSize, weight: .regular), accessibilityIdentifier: AccessibilityID.descriptionLabel)
        resultDescription.numberOfLines = Typography.unlimitedNumberOfLines
        resultDescription.textColor = AppAssetColor.white.uiColor.withAlphaComponent(
            Appearance.descriptionTextAlpha
        )

        replayProgressLabel = makeLabel(
            font: typography.font(size: Typography.progressFontSize, weight: .medium),
            accessibilityIdentifier: AccessibilityID.replayProgressStatus
        )
        replayProgressLabel.numberOfLines = Typography.unlimitedNumberOfLines
        replayProgressLabel.accessibilityTraits.insert(.updatesFrequently)
        replayProgressLabel.isHidden = true
    }
    
    private func configureActionButtons() {
        replayButton = makeActionButton(
            title: L10n.Result.playAgain,
            accessibilityIdentifier: AccessibilityID.replayButton
        )
        replayButton.addTarget(self, action: #selector(replayButtonTapped), for: .touchUpInside)
        configureReplayLoadingContent()

        themesButton = makeActionButton(
            title: L10n.Result.toThemes,
            accessibilityIdentifier: AccessibilityID.themesButton
        )
        themesButton.addTarget(self, action: #selector(themesButtonTapped), for: .touchUpInside)
    }

    private func configureReplayLoadingContent() {
        replayActivityIndicator = UIActivityIndicatorView(style: .medium)
        replayActivityIndicator.accessibilityIdentifier = AccessibilityID.replayActivityIndicator
        replayActivityIndicator.hidesWhenStopped = true

        replayLoadingTitleLabel = UILabel()
        replayLoadingTitleLabel.adjustsFontForContentSizeCategory = true
        replayLoadingTitleLabel.text = L10n.AITheme.generating

        replayLoadingContentStack = UIStackView(
            arrangedSubviews: [replayActivityIndicator, replayLoadingTitleLabel]
        )
        replayLoadingContentStack.accessibilityIdentifier = AccessibilityID.replayLoadingContent
        replayLoadingContentStack.axis = .horizontal
        replayLoadingContentStack.alignment = .center
        replayLoadingContentStack.spacing = Layout.replayLoadingContentSpacing
        replayLoadingContentStack.isHidden = true
        replayLoadingContentStack.isUserInteractionEnabled = false
        replayLoadingContentStack.translatesAutoresizingMaskIntoConstraints = false
        replayButton.addSubview(replayLoadingContentStack)

        NSLayoutConstraint.activate([
            replayLoadingContentStack.centerXAnchor.constraint(equalTo: replayButton.centerXAnchor),
            replayLoadingContentStack.centerYAnchor.constraint(equalTo: replayButton.centerYAnchor),
            replayLoadingContentStack.leadingAnchor.constraint(
                greaterThanOrEqualTo: replayButton.leadingAnchor,
                constant: Layout.contentHorizontalInset
            ),
            replayLoadingContentStack.trailingAnchor.constraint(
                lessThanOrEqualTo: replayButton.trailingAnchor,
                constant: -Layout.contentHorizontalInset
            )
        ])
    }
    
    private func configureContentStackView() {
        let actionsStackView = UIStackView(
            arrangedSubviews: [replayButton, replayProgressLabel, themesButton]
        )
        actionsStackView.axis = .vertical
        actionsStackView.spacing = Layout.actionButtonSpacing

        contentStackView = UIStackView(arrangedSubviews: [resultLabel, resultDescription, actionsStackView])
        contentStackView.accessibilityIdentifier = AccessibilityID.contentStackView
        contentStackView.axis = .vertical
        contentStackView.alignment = .fill
        contentStackView.spacing = Layout.contentStackSpacing
        contentStackView.setCustomSpacing(Layout.resultLabelBottomSpacing, after: resultLabel)
        contentStackView.setCustomSpacing(Layout.descriptionBottomSpacing, after: resultDescription)
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
    }
    
    private func addSubviews(to rootView: UIView) {
        scrollView = UIScrollView()
        scrollView.accessibilityIdentifier = AccessibilityID.scrollView
        scrollView.alwaysBounceVertical = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(scrollView)
        scrollView.addSubview(resultCardView)
        resultCardView.addSubview(contentStackView)
    }
    
    private func activateLayoutConstraints(in rootView: UIView) {
        maximumWidthConstraint = resultCardView.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.maximumContentWidth)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: rootView.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: rootView.safeAreaLayoutGuide.bottomAnchor),
            scrollView.contentLayoutGuide.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            scrollView.contentLayoutGuide.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor),

            resultCardView.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
            resultCardView.centerYAnchor.constraint(equalTo: scrollView.contentLayoutGuide.centerYAnchor),
            resultCardView.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.contentLayoutGuide.leadingAnchor, constant: Layout.cardHorizontalInset),
            resultCardView.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -Layout.cardHorizontalInset),
            maximumWidthConstraint!,
            resultCardView.topAnchor.constraint(greaterThanOrEqualTo: scrollView.contentLayoutGuide.topAnchor, constant: Layout.cardVerticalMinimumInset),
            resultCardView.bottomAnchor.constraint(lessThanOrEqualTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -Layout.cardVerticalMinimumInset),
            
            contentStackView.topAnchor.constraint(equalTo: resultCardView.topAnchor, constant: Layout.contentTopInset),
            contentStackView.leadingAnchor.constraint(equalTo: resultCardView.leadingAnchor, constant: Layout.contentHorizontalInset),
            contentStackView.trailingAnchor.constraint(equalTo: resultCardView.trailingAnchor, constant: -Layout.contentHorizontalInset),
            contentStackView.bottomAnchor.constraint(equalTo: resultCardView.bottomAnchor, constant: -Layout.contentBottomInset),
            
            replayButton.heightAnchor.constraint(greaterThanOrEqualToConstant: Layout.actionButtonHeight),
            themesButton.heightAnchor.constraint(greaterThanOrEqualToConstant: Layout.actionButtonHeight)
        ])

        let cardWidthConstraint = resultCardView.widthAnchor.constraint(
            equalTo: scrollView.frameLayoutGuide.widthAnchor,
            constant: -(Layout.cardHorizontalInset * 2)
        )
        cardWidthConstraint.priority = .defaultHigh
        cardWidthConstraint.isActive = true
    }
    
    private func makeLabel(font: UIFont, accessibilityIdentifier: String) -> UILabel {
        let label = UILabel()
        label.accessibilityIdentifier = accessibilityIdentifier
        label.textColor = AppAssetColor.white.uiColor
        label.font = font
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
    
    private func makeActionButton(title: String, accessibilityIdentifier: String) -> UIButton {
        let button = UIButton(type: .system)
        button.accessibilityIdentifier = accessibilityIdentifier
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.setTitleColor(
            AppAssetColor.white.uiColor.withAlphaComponent(Appearance.disabledButtonTitleAlpha),
            for: .disabled
        )
        button.titleLabel?.font = currentAppearance().typography.font(size: Typography.buttonFontSize, weight: .semibold)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.backgroundColor = AppAssetColor.white.uiColor.withAlphaComponent(
            Appearance.buttonBackgroundAlpha
        )
        button.layer.cornerRadius = Appearance.buttonCornerRadius
        button.layer.borderWidth = Appearance.buttonBorderWidth
        button.layer.borderColor = AppAssetColor.white.uiColor
            .withAlphaComponent(Appearance.buttonBorderAlpha)
            .cgColor
        button.layer.shadowColor = AppAssetColor.black.uiColor.cgColor
        button.layer.shadowOpacity = Appearance.buttonShadowOpacity
        button.layer.shadowRadius = Appearance.buttonShadowRadius
        button.layer.shadowOffset = Appearance.buttonShadowOffset
        button.translatesAutoresizingMaskIntoConstraints = false
        button.installPressFeedback()
        return button
    }

    override func applyAppearance() {
        guard isViewLoaded else { return }
        let appearance = currentAppearance()
        appearance.applyBackground(to: view)
        overrideUserInterfaceStyle = appearance.resolvedInterfaceStyle

        resultCardView?.applySurfaceStyle(appearance.card)
        perfectScoreEffectView?.layer.cornerRadius = resultCardView?.layer.cornerRadius
            ?? Appearance.cardCornerRadius
        resultLabel?.textColor = appearance.surfaceTextColor
        resultLabel?.font = appearance.typography.font(size: Typography.resultFontSize, weight: .bold)
        resultDescription?.textColor = appearance.secondarySurfaceTextColor
        resultDescription?.font = appearance.typography.font(size: Typography.descriptionFontSize, weight: .regular)
        replayButton?.applyActionAppearance(
            QuizThemeAccentStyle.primaryButtonStyle(themeID: presenter?.themeID, appearance: appearance),
            appearance: appearance,
            textColor: QuizThemeAccentStyle.primaryButtonTextColor(
                themeID: presenter?.themeID,
                appearance: appearance
            )
        )
        replayButton?.titleLabel?.font = appearance.typography.font(size: Typography.buttonFontSize, weight: .semibold)
        replayLoadingTitleLabel?.font = appearance.typography.font(size: Typography.buttonFontSize, weight: .semibold)
        replayLoadingTitleLabel?.textColor = QuizThemeAccentStyle.primaryButtonTextColor(
            themeID: presenter?.themeID,
            appearance: appearance
        )
        replayActivityIndicator?.color = QuizThemeAccentStyle.primaryButtonTextColor(
            themeID: presenter?.themeID,
            appearance: appearance
        )
        replayProgressLabel?.font = appearance.typography.font(size: Typography.progressFontSize, weight: .medium)
        replayProgressLabel?.textColor = appearance.secondarySurfaceTextColor
        themesButton?.applyActionAppearance(
            QuizThemeAccentStyle.secondaryButtonStyle(themeID: presenter?.themeID, appearance: appearance),
            appearance: appearance,
            textColor: QuizThemeAccentStyle.secondaryButtonTextColor(themeID: presenter?.themeID, appearance: appearance)
        )
        themesButton?.titleLabel?.font = appearance.typography.font(size: Typography.buttonFontSize, weight: .semibold)
    }

    @objc private func replayButtonTapped() {
        guard replayButton.isEnabled else { return }
        analytics.track(.quizResultAction(theme: presenter?.analyticsTheme ?? .unknown, action: .replay))
        router?.replayQuiz()
    }

    @objc private func themesButtonTapped() {
        analytics.track(.quizResultAction(theme: presenter?.analyticsTheme ?? .unknown, action: .themes))
        router?.returnToThemes()
    }

    override func applyLocalizedStrings() {
        guard isViewLoaded else { return }
        if let replayGenerationPhase {
            setReplayGenerationPhase(replayGenerationPhase)
        } else {
            setReplayLoading(isReplayLoading)
        }
        themesButton.setTitle(L10n.Result.toThemes, for: .normal)
        presenter?.viewDidLoad()
    }
}

#if DEBUG
#Preview("Result") {
    let viewController = QuizResultViewController()
    viewController.loadViewIfNeeded()
    viewController.updateResultLabels(
        resultText: "Твой результат:\n 8/10",
        descriptionText: "Ещё чуть-чуть и был бы как сам создатель квиза, молодец!"
    )
    return viewController
}
#endif
