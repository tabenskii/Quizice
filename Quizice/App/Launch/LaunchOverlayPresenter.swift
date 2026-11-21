import SwiftUI
import UIKit

@MainActor
final class LaunchOverlayPresenter {
    private enum Timing {
        static let holdDuration: TimeInterval = 1.15
        static let homeRevealDuration: TimeInterval = 0.24
        static let reducedMotionRevealDuration: TimeInterval = 0.18
    }

    static let accessibilityIdentifier = "fakeLaunchScreen"

    private var overlayWindow: UIWindow?
    private var activePresentationID: UUID?
    private var activeDismissalID: UUID?
    private var preparationTask: Task<Void, Never>?
    private var preparationDeadlineTask: Task<Void, Never>?
    private var activeReadiness: FakeLaunchReadiness?
    private var prepareContentForReveal: ((@escaping () -> Void) -> Void)?
    private var hasStartedPreparingContent = false
    private weak var coveredAccessibilityView: UIView?
    private var coveredViewWasAccessibilityHidden = false
    private var onDismissed: (() -> Void)?
    private let waitForPreparationTimeout: @MainActor (TimeInterval) async throws -> Void

    init(
        waitForPreparationTimeout: @escaping @MainActor (TimeInterval) async throws -> Void = { timeout in
            try await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
        }
    ) {
        self.waitForPreparationTimeout = waitForPreparationTimeout
    }

    func present(
        in window: UIWindow,
        appearance: AppAppearance,
        holdDuration: TimeInterval = Timing.holdDuration,
        motion: FakeLaunchMotion = .standard,
        preparationTimeout: TimeInterval = 2,
        preparation: (@MainActor () async -> Void)? = nil,
        prepareContentForReveal: ((@escaping () -> Void) -> Void)? = nil,
        onDismissed: (() -> Void)? = nil
    ) {
        guard
            overlayWindow == nil,
            let windowScene = window.windowScene,
            let coveredView = window.rootViewController?.view
        else { return }

        let visualStyle = FakeLaunchVisualStyle(appearance: appearance)
        let presentationID = UUID()
        let readiness = FakeLaunchReadiness(
            state: preparation == nil && prepareContentForReveal == nil ? .ready : .waiting
        )
        let hostingController = UIHostingController(
            rootView: FakeLaunchScreenView(
                appearance: appearance,
                holdDuration: holdDuration,
                motion: motion,
                readiness: readiness,
                onFinished: { [weak self] style in
                    self?.completePresentation(presentationID, with: style)
                }
            )
        )
        let overlayView = hostingController.view!
        overlayView.accessibilityIdentifier = Self.accessibilityIdentifier
        overlayView.accessibilityElementsHidden = true
        overlayView.backgroundColor = visualStyle.backgroundColor
        hostingController.overrideUserInterfaceStyle = appearance.resolvedInterfaceStyle

        let overlayWindow = UIWindow(windowScene: windowScene)
        overlayWindow.accessibilityIdentifier = Self.accessibilityIdentifier
        overlayWindow.accessibilityViewIsModal = true
        overlayWindow.backgroundColor = visualStyle.backgroundColor
        overlayWindow.windowLevel = UIWindow.Level(rawValue: window.windowLevel.rawValue + 1)
        overlayWindow.rootViewController = hostingController

        coveredAccessibilityView = coveredView
        coveredViewWasAccessibilityHidden = coveredView.accessibilityElementsHidden
        coveredView.accessibilityElementsHidden = true
        self.onDismissed = onDismissed
        self.prepareContentForReveal = prepareContentForReveal
        hasStartedPreparingContent = false
        activePresentationID = presentationID
        activeReadiness = readiness
        self.overlayWindow = overlayWindow
        overlayWindow.isHidden = false

        if preparation != nil || prepareContentForReveal != nil {
            preparationTask = Task { @MainActor [weak self] in
                await preparation?()
                guard
                    let self,
                    activePresentationID == presentationID,
                    !Task.isCancelled
                else { return }
                prepareToReveal(presentationID, afterTimeout: false)
            }
        }
        if preparation != nil {
            let waitForPreparationTimeout = self.waitForPreparationTimeout
            preparationDeadlineTask = Task { @MainActor [weak self] in
                do {
                    try await waitForPreparationTimeout(preparationTimeout)
                } catch { return }
                guard let self, activePresentationID == presentationID, !Task.isCancelled else { return }
                // Stop waiting for the server, but keep the splash opaque until
                // UIKit has installed the first screen underneath it.
                prepareToReveal(presentationID, afterTimeout: true)
            }
        }
    }

    private func prepareToReveal(_ presentationID: UUID, afterTimeout: Bool) {
        guard activePresentationID == presentationID, !hasStartedPreparingContent else { return }
        hasStartedPreparingContent = true
        preparationTask?.cancel()
        preparationTask = nil
        preparationDeadlineTask?.cancel()
        preparationDeadlineTask = nil
        let prepareContent = prepareContentForReveal
        prepareContentForReveal = nil
        let contentReady = { [weak self] in
            guard let self, activePresentationID == presentationID,
                  let readiness = activeReadiness, readiness.state == .waiting else { return }
            readiness.state = afterTimeout ? .readyAfterDeadline : .ready
        }
        if let prepareContent {
            prepareContent(contentReady)
        } else {
            contentReady()
        }
    }

    func dismiss(animated: Bool = true) {
        let duration = UIAccessibility.isReduceMotionEnabled
            ? Timing.reducedMotionRevealDuration
            : Timing.homeRevealDuration
        dismiss(animated: animated, duration: duration)
    }

    private func dismiss(animated: Bool, duration: TimeInterval) {
        preparationTask?.cancel()
        preparationTask = nil
        preparationDeadlineTask?.cancel()
        preparationDeadlineTask = nil
        activeReadiness = nil
        prepareContentForReveal = nil
        activePresentationID = nil

        guard let overlayWindow else { return }

        guard animated, UIView.areAnimationsEnabled else {
            activeDismissalID = nil
            overlayWindow.layer.removeAllAnimations()
            finishDismissal(expectedWindow: overlayWindow)
            return
        }

        let dismissalID = UUID()
        activeDismissalID = dismissalID
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]
        ) {
            overlayWindow.alpha = 0
        } completion: { [weak self, weak overlayWindow] _ in
            guard
                let self,
                let overlayWindow,
                activeDismissalID == dismissalID
            else { return }
            finishDismissal(expectedWindow: overlayWindow)
        }
    }

    private func completePresentation(
        _ presentationID: UUID,
        with style: FakeLaunchCompletionStyle
    ) {
        guard activePresentationID == presentationID else { return }

        switch style {
        case .revealHome:
            dismiss(animated: true, duration: Timing.homeRevealDuration)
        case .crossfade:
            dismiss(animated: true, duration: Timing.reducedMotionRevealDuration)
        }
    }

    private func finishDismissal(expectedWindow: UIWindow? = nil) {
        if let expectedWindow, overlayWindow !== expectedWindow {
            return
        }

        overlayWindow?.layer.removeAllAnimations()
        activePresentationID = nil
        activeDismissalID = nil
        activeReadiness = nil
        overlayWindow?.isHidden = true
        overlayWindow?.rootViewController = nil
        overlayWindow = nil

        coveredAccessibilityView?.accessibilityElementsHidden = coveredViewWasAccessibilityHidden
        coveredAccessibilityView = nil
        let dismissedHandler = onDismissed
        onDismissed = nil
        dismissedHandler?()
    }
}
