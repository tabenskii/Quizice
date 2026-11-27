import SwiftUI
import UIKit

private enum PressFeedbackTiming {
    static let pressedDuration: TimeInterval = 0.12
    static let releasedDuration: TimeInterval = 0.16
    static let pressedScale: CGFloat = 0.97
    static let reducedMotionPressedAlpha: CGFloat = 0.82
}

final class Animations {
    
    func animateDownSpring(_ viewToAnimate: UIView) {
        viewToAnimate.setPressFeedback(isPressed: true)
    }
    
    func animateUpSpring(_ viewToAnimate: UIView) {
        viewToAnimate.setPressFeedback(isPressed: false)
    }
    
    func animateDownFloat(_ viewToAnimate: UIView, duration: Double = 0.2) {
        viewToAnimate.setPressFeedback(isPressed: true)
    }
    
    func animateUpFloat(_ viewToAnimate: UIView, duration: Double = 0.15) {
        viewToAnimate.setPressFeedback(isPressed: false)
    }
    
    func animateDownRadius(_ viewToAnimate: UIView) {
        if viewToAnimate.layer.cornerRadius == 0 {
            UIView.animate(withDuration: 1, delay: 0) {
                viewToAnimate.layer.cornerRadius = 15
            }
        } else {
            UIView.animate(withDuration: 1, delay: 0) {
                viewToAnimate.layer.cornerRadius = 0
            }
        }
    }
    
    func animateTintColor(
        _ viewToAnimate: UIView,
        color: UIColor = AppAssetColor.black.uiColor,
        duration: Double = 0.5
    ) {
        UIView.transition(
            with: viewToAnimate,
            duration: duration,
            options: [.transitionCrossDissolve, .allowUserInteraction],
            animations: {
            viewToAnimate.tintColor = color
        })
    }
    
    func animateBackgroundColor(_ viewToAnimate: UIView, color: CGColor, duration: Double = 0.5) {
        UIView.transition(
            with: viewToAnimate,
            duration: duration,
            options: [.transitionCrossDissolve, .allowUserInteraction],
            animations: {
                viewToAnimate.layer.backgroundColor = color
            })
    }
}

extension UIView {
    func setPressFeedback(isPressed: Bool) {
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let duration = isPressed ? PressFeedbackTiming.pressedDuration : PressFeedbackTiming.releasedDuration
        let changes = {
            self.transform = reduceMotion || !isPressed
                ? .identity
                : CGAffineTransform(
                    scaleX: PressFeedbackTiming.pressedScale,
                    y: PressFeedbackTiming.pressedScale
                )
            self.alpha = reduceMotion && isPressed
                ? PressFeedbackTiming.reducedMotionPressedAlpha
                : 1
        }

        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction],
            animations: changes
        )
    }
    
    func fadeIn(duration: TimeInterval = 0.2, onCompletion: (() -> Void)? = nil) {
        self.alpha = 0
        self.isHidden = false
        UIView.animate(withDuration: duration,
                       animations: { self.alpha = 1 },
                       completion: { (value: Bool) in
                          if let complete = onCompletion { complete() }
                       }
        )
    }
    
    func fadeOut(duration: TimeInterval = 0.2, onCompletion: (() -> Void)? = nil) {
        UIView.animate(withDuration: duration,
                       animations: { self.alpha = 0 },
                       completion: { (value: Bool) in
                           self.isHidden = true
                           if let complete = onCompletion { complete() }
                       }
        )
    }
}

extension UIButton {
    func installPressFeedback() {
        addAction(
            UIAction { [weak self] _ in
                self?.setPressFeedback(isPressed: true)
            },
            for: .touchDown
        )
        addAction(
            UIAction { [weak self] _ in
                self?.setPressFeedback(isPressed: false)
            },
            for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit]
        )
    }
}

struct QuizPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : PressFeedbackTiming.pressedScale)
            .opacity(
                reduceMotion && configuration.isPressed
                    ? PressFeedbackTiming.reducedMotionPressedAlpha
                    : 1
            )
            .animation(
                .timingCurve(
                    0.23,
                    1,
                    0.32,
                    1,
                    duration: configuration.isPressed
                        ? PressFeedbackTiming.pressedDuration
                        : PressFeedbackTiming.releasedDuration
                ),
                value: configuration.isPressed
            )
    }
}

enum QuizCardSlideTransition {
    static let presentationDuration: TimeInterval = 0.24
    static let questionAdvanceDuration: TimeInterval = 0.18
    static let options: UIView.AnimationOptions = [.curveEaseOut, .beginFromCurrentState]

    static func horizontalOffset(in containerView: UIView, horizontalInset: CGFloat) -> CGFloat {
        containerView.bounds.width + horizontalInset
    }
}

protocol QuizCardSlideTransitionSource: AnyObject {
    var cardSlideTransitionSourceView: UIView { get }
    var cardSlideTransitionHorizontalInset: CGFloat { get }
    var cardSlideTransitionCrossfadesSource: Bool { get }
}

extension QuizCardSlideTransitionSource {
    var cardSlideTransitionCrossfadesSource: Bool { false }
}

protocol QuizCardSlideTransitionDestination: AnyObject {
    var cardSlideTransitionDestinationView: UIView { get }
    var cardSlideTransitionHorizontalInset: CGFloat { get }
    var cardSlideTransitionDestinationCompanionViews: [UIView] { get }
}

extension QuizCardSlideTransitionDestination {
    var cardSlideTransitionDestinationCompanionViews: [UIView] { [] }
}

final class QuizCardSlidePresentationAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    weak var sourceViewController: QuizCardSlideTransitionSource?

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        QuizCardSlideTransition.presentationDuration
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard
            let toViewController = transitionContext.viewController(forKey: .to),
            let toView = transitionContext.view(forKey: .to)
        else {
            transitionContext.completeTransition(false)
            return
        }

        let containerView = transitionContext.containerView
        let finalFrame = transitionContext.finalFrame(for: toViewController)
        toView.frame = finalFrame.isEmpty ? containerView.bounds : finalFrame
        containerView.addSubview(toView)

        guard
            !UIAccessibility.isReduceMotionEnabled,
            let fromViewController = sourceViewController ?? (transitionContext.viewController(forKey: .from) as? QuizCardSlideTransitionSource),
            let toViewController = toViewController as? QuizCardSlideTransitionDestination
        else {
            sourceViewController = nil
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            return
        }

        toView.setNeedsLayout()
        toView.layoutIfNeeded()

        let crossfadesSource = fromViewController.cardSlideTransitionCrossfadesSource
        let sourceView = crossfadesSource ? nil : fromViewController.cardSlideTransitionSourceView
        let sourceSnapshot = sourceView?.snapshotView(afterScreenUpdates: false)
        let destinationView = toViewController.cardSlideTransitionDestinationView
        let destinationCompanionViews = crossfadesSource
            ? []
            : toViewController.cardSlideTransitionDestinationCompanionViews
        let companionAlphas = destinationCompanionViews.map(\.alpha)
        let originalBackgroundColor = toView.backgroundColor
        let originalDestinationAlpha = toView.alpha
        let sourceWasHidden = sourceView?.isHidden ?? false
        let destinationWasInteractive = destinationView.isUserInteractionEnabled
        let horizontalInset = max(
            fromViewController.cardSlideTransitionHorizontalInset,
            toViewController.cardSlideTransitionHorizontalInset
        )
        let horizontalOffset = QuizCardSlideTransition.horizontalOffset(
            in: containerView,
            horizontalInset: horizontalInset
        )

        guard
            horizontalOffset > 0,
            crossfadesSource || sourceSnapshot != nil
        else {
            sourceViewController = nil
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            return
        }

        if let sourceView, let sourceSnapshot {
            sourceSnapshot.frame = sourceView.convert(sourceView.bounds, to: containerView)
            sourceView.isHidden = true
            toView.backgroundColor = .clear
            containerView.addSubview(sourceSnapshot)
        } else {
            // Fade the destination with its background so the whole outgoing screen remains visible underneath.
            toView.alpha = 0
        }
        destinationView.transform = CGAffineTransform(translationX: horizontalOffset, y: 0)
        destinationCompanionViews.forEach { $0.alpha = 0 }
        destinationView.isUserInteractionEnabled = false

        UIView.animate(
            withDuration: transitionDuration(using: transitionContext),
            delay: 0,
            options: QuizCardSlideTransition.options,
            animations: {
                sourceSnapshot?.transform = CGAffineTransform(translationX: -horizontalOffset, y: 0)
                toView.alpha = originalDestinationAlpha
                destinationView.transform = .identity
                for (view, alpha) in zip(destinationCompanionViews, companionAlphas) {
                    view.alpha = alpha
                }
            },
            completion: { _ in
                let completed = !transitionContext.transitionWasCancelled
                sourceSnapshot?.removeFromSuperview()
                sourceView?.isHidden = sourceWasHidden
                toView.alpha = originalDestinationAlpha
                destinationView.transform = .identity
                for (view, alpha) in zip(destinationCompanionViews, companionAlphas) {
                    view.alpha = alpha
                }
                destinationView.isUserInteractionEnabled = destinationWasInteractive
                toView.backgroundColor = originalBackgroundColor
                self.sourceViewController = nil
                transitionContext.completeTransition(completed)
            }
        )
    }
}
