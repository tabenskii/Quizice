import UIKit

final class ThemeCardTransitionInteractionButton: UIButton {
    var trackedViews: [UIView] = [] {
        didSet {
            initialTrackedFrames = trackedViews.map { $0.layer.frame }
        }
    }
    var onTap: (() -> Void)?
    private var initialTrackedFrames: [CGRect] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard super.point(inside: point, with: event), superview != nil else { return false }

        return trackedViews.enumerated().contains { index, trackedView in
            guard let trackedSuperview = trackedView.superview else { return false }
            let candidateFrames: [CGRect]
            if let presentationFrame = trackedView.layer.presentation()?.frame {
                candidateFrames = [presentationFrame]
            } else {
                candidateFrames = [trackedView.layer.frame] +
                    (initialTrackedFrames.indices.contains(index) ? [initialTrackedFrames[index]] : [])
            }
            return candidateFrames.contains { candidateFrame in
                convert(candidateFrame, from: trackedSuperview).contains(point)
            }
        }
    }

    @objc private func tapped() {
        onTap?()
    }
}

struct ThemeCardTransitionGradientOutlineConfiguration {
    let colors: [UIColor]
    let lineWidth: CGFloat
    let collapsedCornerRadius: CGFloat
    let expandedCornerRadius: CGFloat
    let referenceWidth: CGFloat
}

final class ThemeCardTransitionGradientOutlineView: UIView {
    private enum AccessibilityID {
        static let collapsedRing = "homeExpandedAIThemeCardTransitionCollapsedGradientRing"
        static let expandedRing = "homeExpandedAIThemeCardTransitionExpandedGradientRing"
    }

    private let collapsedRingImageView = UIImageView()
    private let expandedRingImageView = UIImageView()

    init(configuration: ThemeCardTransitionGradientOutlineConfiguration) {
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        accessibilityIdentifier = "homeExpandedAIThemeCardTransitionGradientOutline"

        configure(
            collapsedRingImageView,
            accessibilityIdentifier: AccessibilityID.collapsedRing,
            image: Self.makeResizableRingImage(
                colors: configuration.colors,
                lineWidth: configuration.lineWidth,
                cornerRadius: configuration.collapsedCornerRadius,
                referenceWidth: configuration.referenceWidth
            )
        )
        configure(
            expandedRingImageView,
            accessibilityIdentifier: AccessibilityID.expandedRing,
            image: Self.makeResizableRingImage(
                colors: configuration.colors,
                lineWidth: configuration.lineWidth,
                cornerRadius: configuration.expandedCornerRadius,
                referenceWidth: configuration.referenceWidth
            )
        )
        addSubview(collapsedRingImageView)
        addSubview(expandedRingImageView)
        apply(progress: 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutRingFrames()
    }

    func updateGeometry(frame: CGRect) {
        self.frame = frame
        layoutRingFrames()
    }

    private func layoutRingFrames() {
        collapsedRingImageView.frame = bounds
        expandedRingImageView.frame = bounds
    }

    func apply(progress: CGFloat) {
        let progress = min(max(progress, 0), 1)
        collapsedRingImageView.alpha = 1 - progress
        expandedRingImageView.alpha = progress
    }

    private func configure(
        _ imageView: UIImageView,
        accessibilityIdentifier: String,
        image: UIImage
    ) {
        imageView.backgroundColor = .clear
        imageView.isOpaque = false
        imageView.isUserInteractionEnabled = false
        imageView.accessibilityElementsHidden = true
        imageView.accessibilityIdentifier = accessibilityIdentifier
        imageView.contentMode = .scaleToFill
        imageView.image = image
    }

    private static func makeResizableRingImage(
        colors: [UIColor],
        lineWidth: CGFloat,
        cornerRadius: CGFloat,
        referenceWidth: CGFloat
    ) -> UIImage {
        let verticalCap = max(ceil(cornerRadius), ceil(lineWidth))
        let size = CGSize(
            width: max(ceil(referenceWidth), verticalCap * 2 + 1),
            height: verticalCap * 2 + 1
        )
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = UIScreen.main.scale
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let bounds = CGRect(origin: .zero, size: size)
            let ringPath = UIBezierPath(
                roundedRect: bounds,
                cornerRadius: cornerRadius
            )
            let innerBounds = bounds.insetBy(dx: lineWidth, dy: lineWidth)
            ringPath.append(
                UIBezierPath(
                    roundedRect: innerBounds,
                    cornerRadius: max(cornerRadius - lineWidth, 0)
                )
            )
            ringPath.usesEvenOddFillRule = true

            let graphicsContext = context.cgContext
            graphicsContext.saveGState()
            graphicsContext.addPath(ringPath.cgPath)
            graphicsContext.clip(using: .evenOdd)
            if let gradient = CGGradient(
                colorsSpace: nil,
                colors: colors.map(\.cgColor) as CFArray,
                locations: nil
            ) {
                graphicsContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: bounds.minX, y: bounds.midY),
                    end: CGPoint(x: bounds.maxX, y: bounds.midY),
                    options: []
                )
            } else {
                graphicsContext.setFillColor((colors.first ?? .clear).cgColor)
                graphicsContext.fill(bounds)
            }
            graphicsContext.restoreGState()
        }

        return image.resizableImage(
            withCapInsets: UIEdgeInsets(
                top: verticalCap,
                left: 0,
                bottom: verticalCap,
                right: 0
            ),
            resizingMode: .stretch
        )
    }
}

final class ThemeCardExpansionTransitionView: UIView {
    private let clippingView = UIView()
    private let baseSurfaceView = UIView()
    private let expandedSurfaceView = UIView()
    private weak var destinationView: UIView?
    private weak var sourceContentView: UIView?
    private var sourceContentSize = CGSize.zero
    private var destinationProgressHandler: ((CGFloat) -> Void)?
    let targetFrameInRoot: CGRect
    private let usesIntensityLayer: Bool
    private let gradientOutlineView: ThemeCardTransitionGradientOutlineView?
    private let gradientBorderWidth: CGFloat
    private let solidBorderColorOverride: UIColor?

    init(
        frame: CGRect,
        targetFrameInRoot: CGRect,
        surfaceColor: UIColor,
        borderColor: UIColor,
        borderWidth: CGFloat,
        cornerRadius: CGFloat,
        visualState: HomeThemeCardTransitionVisualState,
        shadow: AppShadowStyle,
        usesIntensityLayer: Bool = true,
        gradientOutlineConfiguration: ThemeCardTransitionGradientOutlineConfiguration? = nil,
        solidBorderColorOverride: UIColor? = nil
    ) {
        self.targetFrameInRoot = targetFrameInRoot
        self.usesIntensityLayer = usesIntensityLayer
        self.solidBorderColorOverride = solidBorderColorOverride
        if let gradientOutlineConfiguration, gradientOutlineConfiguration.lineWidth > 0 {
            self.gradientOutlineView = ThemeCardTransitionGradientOutlineView(
                configuration: gradientOutlineConfiguration
            )
            self.gradientBorderWidth = gradientOutlineConfiguration.lineWidth
        } else {
            self.gradientOutlineView = nil
            self.gradientBorderWidth = 0
        }
        super.init(frame: frame)

        backgroundColor = .clear
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        isUserInteractionEnabled = false
        layer.masksToBounds = false
        applyShadow(shadow)

        clippingView.frame = bounds
        clippingView.backgroundColor = .clear
        clippingView.layer.cornerRadius = cornerRadius
        clippingView.layer.cornerCurve = .continuous
        clippingView.layer.masksToBounds = true
        clippingView.layer.borderColor = (solidBorderColorOverride ?? borderColor).cgColor
        clippingView.layer.borderWidth = gradientOutlineView == nil ? borderWidth : 0
        addSubview(clippingView)

        if let gradientOutlineView {
            gradientOutlineView.updateGeometry(frame: clippingView.bounds)
            gradientOutlineView.apply(progress: visualState.progress)
            clippingView.addSubview(gradientOutlineView)
        }

        baseSurfaceView.frame = transitionSurfaceFrame(in: clippingView.bounds)
        baseSurfaceView.backgroundColor = surfaceColor
        baseSurfaceView.layer.cornerRadius = transitionSurfaceCornerRadius(from: cornerRadius)
        baseSurfaceView.layer.cornerCurve = .continuous
        baseSurfaceView.accessibilityIdentifier = "homeExpandedThemeCardTransitionChrome"
        baseSurfaceView.isAccessibilityElement = false
        baseSurfaceView.isUserInteractionEnabled = false
        clippingView.addSubview(baseSurfaceView)

        expandedSurfaceView.frame = transitionSurfaceFrame(in: clippingView.bounds)
        expandedSurfaceView.backgroundColor = surfaceColor
        expandedSurfaceView.layer.cornerRadius = transitionSurfaceCornerRadius(from: cornerRadius)
        expandedSurfaceView.layer.cornerCurve = .continuous
        expandedSurfaceView.alpha = visualState.expandedSurfaceLayerAlpha
        expandedSurfaceView.isHidden = !usesIntensityLayer
        expandedSurfaceView.accessibilityIdentifier = "homeExpandedThemeCardTransitionIntensity"
        expandedSurfaceView.isAccessibilityElement = false
        expandedSurfaceView.isUserInteractionEnabled = false
        clippingView.addSubview(expandedSurfaceView)

        updateShadowPath(cornerRadius: cornerRadius)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func install(
        destinationView: UIView,
        sourceContentView: UIView,
        visualState: HomeThemeCardTransitionVisualState,
        destinationProgressHandler: ((CGFloat) -> Void)? = nil
    ) {
        self.destinationView = destinationView
        self.sourceContentView = sourceContentView
        self.destinationProgressHandler = destinationProgressHandler
        sourceContentSize = sourceContentView.bounds.size
        destinationView.removeFromSuperview()
        sourceContentView.removeFromSuperview()
        destinationView.layer.zPosition = 2
        sourceContentView.layer.zPosition = 3
        clippingView.addSubview(destinationView)
        clippingView.addSubview(sourceContentView)
        updateContentFrames(containerFrame: frame)
        apply(visualState: visualState)
    }

    func move(
        to containerFrame: CGRect,
        cornerRadius: CGFloat,
        visualState: HomeThemeCardTransitionVisualState,
        shadow: AppShadowStyle,
        surfaceColor: UIColor? = nil,
        borderColor: UIColor? = nil,
        borderWidth: CGFloat? = nil
    ) {
        frame = containerFrame
        clippingView.frame = bounds
        clippingView.layer.cornerRadius = cornerRadius
        if let borderColor, gradientOutlineView == nil {
            clippingView.layer.borderColor = (solidBorderColorOverride ?? borderColor).cgColor
        }
        if let borderWidth, gradientOutlineView == nil {
            clippingView.layer.borderWidth = borderWidth
        }
        gradientOutlineView?.updateGeometry(frame: clippingView.bounds)
        baseSurfaceView.frame = transitionSurfaceFrame(in: clippingView.bounds)
        baseSurfaceView.layer.cornerRadius = transitionSurfaceCornerRadius(from: cornerRadius)
        if let surfaceColor {
            baseSurfaceView.backgroundColor = surfaceColor
            expandedSurfaceView.backgroundColor = surfaceColor
        }
        expandedSurfaceView.frame = transitionSurfaceFrame(in: clippingView.bounds)
        expandedSurfaceView.layer.cornerRadius = transitionSurfaceCornerRadius(from: cornerRadius)
        updateContentFrames(containerFrame: containerFrame)
        apply(visualState: visualState)
        applyShadow(shadow)
        updateShadowPath(cornerRadius: cornerRadius)
    }

    private func apply(visualState: HomeThemeCardTransitionVisualState) {
        sourceContentView?.alpha = visualState.sourceContentAlpha
        destinationView?.alpha = visualState.expandedContentAlpha
        destinationProgressHandler?(visualState.progress)
        gradientOutlineView?.apply(progress: visualState.progress)
        expandedSurfaceView.alpha = usesIntensityLayer
            ? visualState.expandedSurfaceLayerAlpha
            : 0
    }

    private func updateContentFrames(containerFrame: CGRect) {
        let geometry = HomeThemeCardTransitionGeometry(
            containerFrame: containerFrame,
            targetFrame: targetFrameInRoot
        )
        destinationView?.frame = geometry.cardFrameInContainer
        sourceContentView?.bounds = CGRect(origin: .zero, size: sourceContentSize)
        sourceContentView?.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    private func updateShadowPath(cornerRadius: CGFloat) {
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: cornerRadius
        ).cgPath
    }

    private func transitionSurfaceFrame(in bounds: CGRect) -> CGRect {
        gradientOutlineView == nil
            ? bounds
            : bounds.insetBy(dx: gradientBorderWidth, dy: gradientBorderWidth)
    }

    private func transitionSurfaceCornerRadius(from outerCornerRadius: CGFloat) -> CGFloat {
        gradientOutlineView == nil
            ? outerCornerRadius
            : max(outerCornerRadius - gradientBorderWidth, 0)
    }

}

final class HomeThemesCollectionViewFlowLayout: UICollectionViewFlowLayout {
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.size != collectionView?.bounds.size
            || super.shouldInvalidateLayout(forBoundsChange: newBounds)
    }

    override func invalidationContext(forBoundsChange newBounds: CGRect) -> UICollectionViewLayoutInvalidationContext {
        let context = super.invalidationContext(forBoundsChange: newBounds)
        if newBounds.size != collectionView?.bounds.size,
           let flowContext = context as? UICollectionViewFlowLayoutInvalidationContext {
            flowContext.invalidateFlowLayoutDelegateMetrics = true
            flowContext.invalidateFlowLayoutAttributes = true
        }
        return context
    }
}

final class HomeThemesCollectionView: UICollectionView {
    private enum Animation {
        static let bottomFadeDuration: CFTimeInterval = 0.20
        static let bottomFadeKey = "home.bottomFade.colors"
    }

    private let bottomFadeMaskLayer = CAGradientLayer()
    private var bottomFadeVisibility: CGFloat = 0
    private var bottomFadeHeight: CGFloat = 0
    weak var moreThemesButton: MoreThemesFadeButton?

    override init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) {
        super.init(frame: frame, collectionViewLayout: layout)
        configureTransparentBackground()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureTransparentBackground()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateBottomFadeMask(
            animated: false,
            preservesActiveAnimation: true
        )
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        if hitView != nil, isMoreThemesTouch(at: point) {
            return self
        }
        return hitView
    }

    func isMoreThemesTouch(at point: CGPoint) -> Bool {
        guard let button = moreThemesButton, !button.isHidden, button.alpha > 0.01 else {
            return false
        }
        return button.point(inside: convert(point, to: button), with: nil)
    }

    override func touchesShouldCancel(in view: UIView) -> Bool {
        if view is UIControl {
            return true
        }
        return super.touchesShouldCancel(in: view)
    }

    func updateBottomFade(
        visibility: CGFloat,
        height: CGFloat,
        animated: Bool = false
    ) {
        let targetVisibility = min(max(visibility, 0), 1)
        let targetHeight = max(height, 0)
        let visibilityChanged = abs(bottomFadeVisibility - targetVisibility) > 0.001
        let heightChanged = abs(bottomFadeHeight - targetHeight) > 0.001

        bottomFadeVisibility = targetVisibility
        bottomFadeHeight = targetHeight
        updateBottomFadeMask(
            animated: animated && visibilityChanged,
            preservesActiveAnimation: !visibilityChanged && !heightChanged
        )
    }

    private func configureTransparentBackground() {
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (collectionView: HomeThemesCollectionView, _: UITraitCollection) in
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.reloadData()
        }
        backgroundColor = .clear
        backgroundView = nil
        isOpaque = false
        layer.isOpaque = false

        bottomFadeMaskLayer.startPoint = CGPoint(x: 0.5, y: 0)
        bottomFadeMaskLayer.endPoint = CGPoint(x: 0.5, y: 1)
    }

    private func updateBottomFadeMask(
        animated: Bool,
        preservesActiveAnimation: Bool
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard bottomFadeHeight > 0, bounds.height > 0 else {
            bottomFadeMaskLayer.removeAllAnimations()
            layer.mask = nil
            return
        }

        let fadeStart = max(1 - bottomFadeHeight / bounds.height, 0)
        let opaqueColor = AppAssetColor.white.uiColor.cgColor
        let targetColors = [
            opaqueColor,
            opaqueColor,
            AppAssetColor.white.uiColor.withAlphaComponent(1 - bottomFadeVisibility).cgColor
        ]
        let currentColors = bottomFadeMaskLayer.presentation()?.colors
            ?? bottomFadeMaskLayer.colors
            ?? [opaqueColor, opaqueColor, opaqueColor]

        bottomFadeMaskLayer.frame = bounds
        bottomFadeMaskLayer.locations = [0, NSNumber(value: Double(fadeStart)), 1]
        bottomFadeMaskLayer.colors = targetColors
        layer.mask = bottomFadeMaskLayer

        guard animated else {
            if !preservesActiveAnimation {
                bottomFadeMaskLayer.removeAnimation(forKey: Animation.bottomFadeKey)
            }
            return
        }

        let colorsAnimation = CABasicAnimation(keyPath: "colors")
        colorsAnimation.fromValue = currentColors
        colorsAnimation.toValue = targetColors
        colorsAnimation.duration = Animation.bottomFadeDuration
        colorsAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        bottomFadeMaskLayer.add(
            colorsAnimation,
            forKey: Animation.bottomFadeKey
        )
    }
}

#if DEBUG
#Preview("Quiz") {
    QuizFactory.shared.startup1st = false
    QuizFactory.shared.themes = [
        QuizTheme(id: "music", theme: "Музыка", themeDescription: "Вопросы о треках, артистах и музыкальных эпохах.", questions: []),
        QuizTheme(id: "technology", theme: "Технологии", themeDescription: "Гаджеты, IT-компании и цифровая культура.", questions: []),
        QuizTheme(id: "history_culture", theme: "История и культура", themeDescription: "Исторические события, искусство и традиции.", questions: []),
        QuizTheme(id: "politics_business", theme: "Политика и бизнес", themeDescription: "Лидеры, компании и громкие решения.", questions: [])
    ]

    let viewController = QuizViewController()
    let navigationController = UINavigationController(rootViewController: viewController)
    navigationController.setNavigationBarHidden(true, animated: false)
    return navigationController
}
#endif
