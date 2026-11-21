import UIKit

final class TwoSidedCardTransformCarrierView: UIView {
    override class var layerClass: AnyClass {
        CATransformLayer.self
    }
}

struct TwoSidedCardTransitionConfiguration {
    let duration: TimeInterval
    let curve: UIView.AnimationCurve
    let reducesMotion: Bool
}

/// Owns the shared, interruptible front/back card transition state.
///
/// The driver deliberately receives concrete UIKit surfaces instead of owning
/// card content. This keeps the presentation-layer sampling and reversal
/// behavior in one place while each card remains responsible for its layout,
/// controls, accessibility focus target, and feature state.
final class TwoSidedCardTransitionDriver {
    struct Surfaces {
        let perspectiveStageView: UIView
        let shadowProxyView: UIView
        let rotatingCardView: UIView
        let frontPlaneView: UIView
        let backPlaneView: UIView
        let frontFaceView: UIView
        let backFaceView: UIView
        let interactionOverlayView: UIView
        let containerLayerToReset: CALayer?
        let normalizesFacePresentation: Bool
    }

    private let surfaces: Surfaces
    private let perspectiveDistance: CGFloat
    private let configuration: () -> TwoSidedCardTransitionConfiguration
    private let animationStateDidChange: (() -> Void)?
    private let didSettle: ((HomeThemeCardFace) -> Void)?

    private var activeAnimator: UIViewPropertyAnimator?
    private var animationStart: HomeThemeCardFace?
    private var animationEnd: HomeThemeCardFace?
    private var animationTarget: HomeThemeCardFace?
    private var animationCompletion: ((HomeThemeCardFace) -> Void)?

    private(set) var face: HomeThemeCardFace

    var isAnimating: Bool {
        activeAnimator != nil
    }

    init(
        initialFace: HomeThemeCardFace = .front,
        surfaces: Surfaces,
        perspectiveDistance: CGFloat,
        configuration: @escaping () -> TwoSidedCardTransitionConfiguration,
        animationStateDidChange: (() -> Void)? = nil,
        didSettle: ((HomeThemeCardFace) -> Void)? = nil
    ) {
        face = initialFace
        self.surfaces = surfaces
        self.perspectiveDistance = perspectiveDistance
        self.configuration = configuration
        self.animationStateDidChange = animationStateDidChange
        self.didSettle = didSettle
    }

    func setFace(
        _ targetFace: HomeThemeCardFace,
        animated: Bool,
        completion: ((HomeThemeCardFace) -> Void)? = nil
    ) {
        if let animator = activeAnimator,
           let startFace = animationStart,
           let endFace = animationEnd,
           targetFace == startFace || targetFace == endFace {
            animationTarget = targetFace
            animationCompletion = completion
            animator.isReversed = targetFace == startFace
            return
        }

        guard targetFace != face else {
            cancel()
            normalize(showing: face)
            completion?(face)
            return
        }

        cancel()
        guard animated else {
            face = targetFace
            normalize(showing: targetFace)
            completion?(targetFace)
            return
        }

        beginAnimation(to: targetFace, configuration: configuration(), completion: completion)
    }

    func finishAtRequestedFace() {
        guard let animator = activeAnimator else { return }
        let position: UIViewAnimatingPosition = animator.isReversed ? .start : .end
        animator.stopAnimation(false)
        animator.finishAnimation(at: position)
    }

    func reset(to face: HomeThemeCardFace) {
        activeAnimator?.stopAnimation(true)
        clearAnimationState()
        self.face = face
        normalize(showing: face)
    }

    func cancel(normalize: Bool = true) {
        activeAnimator?.stopAnimation(true)
        clearAnimationState()
        if normalize {
            self.normalize(showing: face)
        }
    }

    func normalize() {
        normalize(showing: face)
    }

    private func beginAnimation(
        to targetFace: HomeThemeCardFace,
        configuration: TwoSidedCardTransitionConfiguration,
        completion: ((HomeThemeCardFace) -> Void)?
    ) {
        let startFace = face
        prepareAnimation(
            from: startFace,
            to: targetFace,
            reducesMotion: configuration.reducesMotion
        )

        let animator = UIViewPropertyAnimator(
            duration: configuration.duration,
            curve: configuration.curve
        ) { [surfaces] in
            Self.applyAnimationEndpoint(
                surfaces: surfaces,
                from: startFace,
                to: targetFace,
                reducesMotion: configuration.reducesMotion
            )
        }
        activeAnimator = animator
        animationStart = startFace
        animationEnd = targetFace
        animationTarget = targetFace
        animationCompletion = completion
        animationStateDidChange?()

        animator.addCompletion { [weak self, weak animator] position in
            guard let self, let animator, activeAnimator === animator else { return }

            let completedFace: HomeThemeCardFace
            switch position {
            case .start:
                completedFace = startFace
            case .end:
                completedFace = targetFace
            case .current:
                completedFace = animationTarget ?? targetFace
            @unknown default:
                completedFace = animationTarget ?? targetFace
            }

            let requestedFace = animationTarget ?? completedFace
            let requestedCompletion = animationCompletion
            clearAnimationState()
            face = completedFace
            normalize(showing: completedFace)

            guard completedFace == requestedFace else {
                setFace(requestedFace, animated: true, completion: requestedCompletion)
                return
            }

            didSettle?(completedFace)
            requestedCompletion?(completedFace)
        }
        animator.startAnimation()
    }

    private func prepareAnimation(
        from startFace: HomeThemeCardFace,
        to targetFace: HomeThemeCardFace,
        reducesMotion: Bool
    ) {
        surfaces.containerLayerToReset?.transform = CATransform3DIdentity
        surfaces.interactionOverlayView.isHidden = false
        surfaces.shadowProxyView.layer.transform = CATransform3DIdentity
        surfaces.rotatingCardView.layer.transform = CATransform3DIdentity
        surfaces.frontPlaneView.isHidden = false
        surfaces.backPlaneView.isHidden = false
        surfaces.frontFaceView.isHidden = false
        surfaces.backFaceView.isHidden = false

        if reducesMotion {
            surfaces.perspectiveStageView.layer.sublayerTransform = CATransform3DIdentity
            surfaces.frontPlaneView.layer.transform = CATransform3DIdentity
            surfaces.backPlaneView.layer.transform = CATransform3DIdentity
            surfaces.frontPlaneView.alpha = startFace == .front ? 1 : 0
            surfaces.backPlaneView.alpha = startFace == .back ? 1 : 0
        } else if let transition = HomeThemeCardFlipTransition(
            startFace: startFace,
            targetFace: targetFace
        ) {
            var perspective = CATransform3DIdentity
            perspective.m34 = -1 / perspectiveDistance
            surfaces.perspectiveStageView.layer.sublayerTransform = perspective
            surfaces.frontPlaneView.alpha = 1
            surfaces.backPlaneView.alpha = 1
            surfaces.frontPlaneView.layer.transform = Self.rotationY(
                HomeThemeCardFlipTransition.localAngle(for: .front)
            )
            surfaces.backPlaneView.layer.transform = Self.rotationY(
                HomeThemeCardFlipTransition.localAngle(for: .back)
            )
            let carrierAngle = transition.carrierAngle(progress: 0)
            surfaces.shadowProxyView.layer.transform = Self.rotationY(carrierAngle)
            surfaces.rotatingCardView.layer.transform = Self.rotationY(carrierAngle)
        }

        assert(startFace != targetFace)
    }

    private static func applyAnimationEndpoint(
        surfaces: Surfaces,
        from startFace: HomeThemeCardFace,
        to targetFace: HomeThemeCardFace,
        reducesMotion: Bool
    ) {
        if reducesMotion {
            surfaces.shadowProxyView.layer.transform = CATransform3DIdentity
            surfaces.rotatingCardView.layer.transform = CATransform3DIdentity
            surfaces.frontPlaneView.alpha = targetFace == .front ? 1 : 0
            surfaces.backPlaneView.alpha = targetFace == .back ? 1 : 0
        } else if let transition = HomeThemeCardFlipTransition(
            startFace: startFace,
            targetFace: targetFace
        ) {
            let carrierAngle = transition.carrierAngle(progress: 1)
            surfaces.shadowProxyView.layer.transform = rotationY(carrierAngle)
            surfaces.rotatingCardView.layer.transform = rotationY(carrierAngle)
        }
    }

    private func normalize(showing face: HomeThemeCardFace) {
        let frontIsVisible = face == .front
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surfaces.containerLayerToReset?.transform = CATransform3DIdentity
        surfaces.interactionOverlayView.isHidden = true
        surfaces.perspectiveStageView.layer.sublayerTransform = CATransform3DIdentity
        let carrierAngle = HomeThemeCardFlipTransition.carrierAngle(showing: face)
        surfaces.shadowProxyView.layer.transform = Self.rotationY(carrierAngle)
        surfaces.rotatingCardView.layer.transform = Self.rotationY(carrierAngle)
        surfaces.frontPlaneView.isHidden = !frontIsVisible
        surfaces.frontPlaneView.alpha = 1
        surfaces.frontPlaneView.layer.transform = Self.rotationY(
            HomeThemeCardFlipTransition.localAngle(for: .front)
        )
        surfaces.backPlaneView.isHidden = frontIsVisible
        surfaces.backPlaneView.alpha = 1
        surfaces.backPlaneView.layer.transform = Self.rotationY(
            HomeThemeCardFlipTransition.localAngle(for: .back)
        )
        surfaces.frontFaceView.isHidden = !frontIsVisible
        surfaces.backFaceView.isHidden = frontIsVisible
        if surfaces.normalizesFacePresentation {
            surfaces.frontFaceView.alpha = 1
            surfaces.frontFaceView.layer.transform = CATransform3DIdentity
            surfaces.backFaceView.alpha = 1
            surfaces.backFaceView.layer.transform = CATransform3DIdentity
        }
        CATransaction.commit()

        surfaces.frontFaceView.accessibilityElementsHidden = !frontIsVisible
        surfaces.frontFaceView.isUserInteractionEnabled = frontIsVisible
        surfaces.backFaceView.accessibilityElementsHidden = frontIsVisible
        surfaces.backFaceView.isUserInteractionEnabled = !frontIsVisible
        animationStateDidChange?()
    }

    private func clearAnimationState() {
        activeAnimator = nil
        animationStart = nil
        animationEnd = nil
        animationTarget = nil
        animationCompletion = nil
    }

    private static func rotationY(_ angle: CGFloat) -> CATransform3D {
        CATransform3DMakeRotation(angle, 0, 1, 0)
    }
}
