import UIKit

extension QuizViewController {
    func handleExpandedThemeCardFlipTap() {
        // A backdrop dismissal is a committed intent. Once an in-flight flip is
        // returning to the front for dismissal, further card taps must not cancel it.
        guard !closeAfterFlipToFront else { return }
        sendHomeCardAction(.flipRequested)
    }

    func flipExpandedThemeCard(to face: HomeThemeCardFace) {
        updateExpandedThemeCardParallaxPhase()
        expandedThemeCardView?.setFace(face, animated: true) { [weak self] completedFace in
            guard let self else { return }
            let previousPhase = self.homeCardState.phase
            self.homeStore.send(.flipCompleted(completedFace))
            self.updateExpandedThemeCardParallaxPhase()
            let completedStableFlip: Bool
            switch (previousPhase, completedFace, self.homeCardState.phase) {
            case (.flippingToBack, .back, .expandedBack),
                 (.flippingToFront, .front, .expandedFront):
                completedStableFlip = true
            default:
                completedStableFlip = false
            }
            if completedStableFlip, self.expandedCardLastTrackedFace != completedFace {
                self.expandedCardLastTrackedFace = completedFace
                self.analytics.track(
                    .themeCardFlipped(
                        theme: self.session.chosenTheme?.analyticsTheme ?? .unknown,
                        visibleFace: completedFace == .front ? .front : .back
                    )
                )
            }
            if completedStableFlip,
               completedFace == .back,
               !self.expandedCardScreenViewTracked {
                self.expandedCardScreenViewTracked = true
                self.analytics.track(
                    .screenView(
                        screen: .themeCardDescription,
                        theme: self.session.chosenTheme?.analyticsTheme ?? .unknown
                    )
                )
            }
            if self.expandedCardNeedsRefresh {
                self.refreshExpandedThemeCardAppearance()
            }
            if completedStableFlip {
                // Without this, VoiceOver can keep announcing traits (e.g. the
                // Start button's enabled/disabled state) it cached before the
                // flip, since nothing else tells it to re-scan the face that
                // just became visible.
                UIAccessibility.post(
                    notification: .layoutChanged,
                    argument: completedFace == .front
                        ? self.expandedThemeCardView?.frontFocusView
                        : self.expandedThemeCardView?.backFocusView
                )
            }
#if DEBUG
            if completedStableFlip, completedFace == .back {
                self.completeDebugCompletedThemePresentation()
            }
#endif
            if self.closeAfterFlipToFront, completedFace == .front {
                self.closeAfterFlipToFront = false
                self.sendHomeCardAction(.closeRequested)
            }
        }
    }

    func flipExpandedAIThemeCard(to face: HomeThemeCardFace) {
        expandedAIThemeCardView?.setFace(face, animated: true) { [weak self] completedFace in
            guard let self else { return }
            let previousPhase = self.homeCardState.phase
            self.homeStore.send(.flipCompleted(completedFace))

            let completedStableFlip: Bool
            switch (previousPhase, completedFace, self.homeCardState.phase) {
            case (.flippingToBack, .back, .expandedBack),
                 (.flippingToFront, .front, .expandedFront):
                completedStableFlip = true
            default:
                completedStableFlip = false
            }

            if completedStableFlip, self.expandedCardLastTrackedFace != completedFace {
                self.expandedCardLastTrackedFace = completedFace
                self.analytics.track(
                    .themeCardFlipped(
                        theme: .ai,
                        visibleFace: completedFace == .front ? .front : .back
                    )
                )
            }

            if self.closeAfterFlipToFront, completedFace == .front {
                self.closeAfterFlipToFront = false
                self.requestExpandedCardClose()
                return
            }

            if completedStableFlip,
               completedFace == .front,
               self.focusAIThemePromptAfterFlip {
                self.focusAIThemePromptAfterFlip = false
                self.focusAIThemePrompt()
            } else if completedStableFlip {
                UIAccessibility.post(
                    notification: .layoutChanged,
                    argument: completedFace == .front
                        ? self.expandedAIThemeCardView?.frontFocusView
                        : self.expandedAIThemeCardView?.backFocusView
                )
            }
            if completedStableFlip { self.applyPendingAIServiceNotice() }
            if self.expandedCardNeedsRefresh {
                self.refreshExpandedThemeCardAppearance()
            }
        }
    }

    func focusAIThemePrompt(
        accessibilityNotification: UIAccessibility.Notification = .layoutChanged
    ) {
        guard let cardView = expandedAIThemeCardView else { return }
        if cardView.face == .front {
            _ = cardView.focusPrompt()
            UIAccessibility.post(
                notification: accessibilityNotification,
                argument: cardView.frontFocusView
            )
            return
        }
        focusAIThemePromptAfterFlip = true
        sendHomeCardAction(.flipRequested)
    }

    func requestExpandedCardClose() {
        if homeCardState.isAIThemePresented,
           homeAIThemeCardState.isSubmitting {
            sendAIThemeCardAction(.cancelRequested)
        }
        sendHomeCardAction(.closeRequested)
    }

    func handleExpandedCardAccessibilityEscape() {
        switch homeCardState.phase {
        case .expandedBack:
            if homeCardState.isAIThemePresented,
               homeAIThemeCardState.isSubmitting {
                requestExpandedCardClose()
                return
            }
            closeAfterFlipToFront = true
            sendHomeCardAction(.flipRequested)
        case .expandedFront:
            requestExpandedCardClose()
        case .grid, .expanding, .flippingToBack, .flippingToFront, .collapsing, .launching:
            break
        }
    }

    func collapseExpandedThemeCard() {
        guard let cardView = expandedThemeCardView else {
            resetExpandedThemeCard()
            return
        }

        updateExpandedThemeCardParallaxPhase()

        let reduceMotion = cardReduceMotionProvider()
        let currentSourceButton = homeCardState.themeID.flatMap { sourceButton(themeID: $0) }
        let sourceFrame = currentSourceButton.map { $0.convert($0.bounds, to: view) }
        let targetFrame = cardView.convert(cardView.bounds, to: view)
        let appearance = currentAppearance()
        let snapshotView = expandedCardSnapshotView

        if let currentSourceButton {
            let refreshedSourceContent = sourceSnapshotFactory.makeThemeContent(from: currentSourceButton)
            refreshedSourceContent.view.accessibilityIdentifier = AccessibilityID.expandedCardSourceSnapshot
            expandedCardSourceContentView?.removeFromSuperview()
            expandedCardSourceContentView = refreshedSourceContent.view
            expandedCardSourceContentGeometry = refreshedSourceContent.geometry
        }

        let sourceContentView = expandedCardSourceContentView
        let sourceContentGeometry = expandedCardSourceContentGeometry

        if reduceMotion {
            cardView.alpha = 1
            snapshotView?.isHidden = false
            snapshotView?.alpha = 0
            snapshotView?.layer.zPosition = Appearance.expandedCardLayerZPosition + 1
            if let snapshotView, let sourceFrame {
                snapshotView.frame = sourceFrame
                view.addSubview(snapshotView)
            }
            installExpandedCardInteractionButton(
                tracking: [cardView] + [snapshotView].compactMap { $0 }
            )
        } else {
            sourceContentView?.isHidden = false
            cardView.setTransitionShadowHidden(true)
            cardView.setTransitionSurfaceHidden(true)
            let transitionView = makeExpandedCardTransitionView(
                frame: targetFrame,
                targetFrame: targetFrame,
                theme: expandedTheme,
                appearance: appearance,
                initialCornerRadius: appearance.themeCardCornerRadius,
                initialVisualState: HomeThemeCardTransitionVisualState(progress: 1),
                initialShadow: appearance.card.shadow
            )
            transitionView.layer.zPosition = Appearance.expandedCardLayerZPosition
            view.addSubview(transitionView)
            if let sourceContentView, let sourceContentGeometry {
                transitionView.install(
                    destinationView: cardView,
                    sourceContentView: sourceContentView,
                    visualState: HomeThemeCardTransitionVisualState(progress: 1),
                    destinationProgressHandler: { [weak cardView] progress in
                        cardView?.setTransitionContentProgress(
                            progress,
                            sourceGeometry: sourceContentGeometry
                        )
                    }
                )
            }
            expandedCardTransitionView = transitionView
            installExpandedCardInteractionButton(tracking: [transitionView])
        }

        let animator: UIViewPropertyAnimator
        if reduceMotion {
            animator = UIViewPropertyAnimator(
                duration: AnimationTiming.reducedMotionDuration,
                curve: .easeInOut
            )
        } else {
            animator = UIViewPropertyAnimator(
                duration: AnimationTiming.cardExpansionDuration,
                dampingRatio: AnimationTiming.cardExpansionDampingRatio
            )
        }

        animator.addAnimations { [weak self, weak snapshotView, weak cardView] in
            guard let self else { return }
            self.expandedCardBlurView?.effect = nil
            if self.expandedCardBlurView == nil {
                self.expandedCardBackdropView?.alpha = 0
            }

            if reduceMotion {
                cardView?.alpha = 0
                snapshotView?.alpha = sourceFrame == nil ? 0 : 1
            } else if let sourceFrame {
                self.expandedCardTransitionView?.move(
                    to: sourceFrame,
                    cornerRadius: appearance.themeCardCornerRadius,
                    visualState: HomeThemeCardTransitionVisualState(progress: 0),
                    shadow: appearance.themeCardShadow
                )
            } else {
                self.expandedCardTransitionView?.alpha = 0
            }
        }
        animator.addCompletion { [weak self, weak animator] position in
            guard let self, let animator else { return }
            self.completeExpandedCardAnimation(
                animator: animator,
                position: position,
                expandedPosition: .start,
                targetFrame: targetFrame
            )
        }

        expandedCardAnimator = animator
        animator.startAnimation()
    }

    func collapseExpandedStatisticsCard() {
        guard let cardView = expandedStatisticsCardView else {
            resetExpandedThemeCard()
            return
        }

        let reduceMotion = cardReduceMotionProvider()
        let currentSourceButton = sourceStatisticsButton()
        let sourceFrame = currentSourceButton.map { $0.convert($0.bounds, to: view) }
        let targetFrame = cardView.convert(cardView.bounds, to: view)
        let appearance = currentAppearance()
        let snapshotView = expandedCardSnapshotView

        if let currentSourceButton {
            let refreshedSourceContent = sourceSnapshotFactory.makeStatisticsContent(from: currentSourceButton)
            refreshedSourceContent.accessibilityIdentifier = AccessibilityID.expandedStatisticsCardSourceSnapshot
            expandedCardSourceContentView?.removeFromSuperview()
            expandedCardSourceContentView = refreshedSourceContent
        }

        let sourceContentView = expandedCardSourceContentView

        if reduceMotion {
            cardView.alpha = 1
            snapshotView?.isHidden = false
            snapshotView?.alpha = 0
            snapshotView?.layer.zPosition = Appearance.expandedCardLayerZPosition + 1
            if let snapshotView, let sourceFrame {
                snapshotView.frame = sourceFrame
                view.addSubview(snapshotView)
            }
            installExpandedCardInteractionButton(
                tracking: [cardView] + [snapshotView].compactMap { $0 }
            )
        } else {
            sourceContentView?.isHidden = false
            cardView.setTransitionShadowHidden(true)
            cardView.setTransitionSurfaceHidden(true)
            let transitionView = makeStatisticsCardTransitionView(
                frame: targetFrame,
                targetFrame: targetFrame,
                surfaceColor: appearance.card.backgroundColor,
                borderColor: appearance.card.borderColor,
                borderWidth: appearance.card.borderWidth,
                initialCornerRadius: appearance.card.cornerRadius,
                initialVisualState: HomeThemeCardTransitionVisualState(progress: 1),
                initialShadow: appearance.card.shadow
            )
            transitionView.layer.zPosition = Appearance.expandedCardLayerZPosition
            view.addSubview(transitionView)
            if let sourceContentView {
                transitionView.install(
                    destinationView: cardView,
                    sourceContentView: sourceContentView,
                    visualState: HomeThemeCardTransitionVisualState(progress: 1)
                )
            }
            expandedCardTransitionView = transitionView
            installExpandedCardInteractionButton(tracking: [transitionView])
        }

        let animator: UIViewPropertyAnimator
        if reduceMotion {
            animator = UIViewPropertyAnimator(
                duration: AnimationTiming.reducedMotionDuration,
                curve: .easeInOut
            )
        } else {
            animator = UIViewPropertyAnimator(
                duration: AnimationTiming.cardExpansionDuration,
                dampingRatio: AnimationTiming.cardExpansionDampingRatio
            )
        }

        animator.addAnimations { [weak self, weak snapshotView, weak cardView] in
            guard let self else { return }
            self.expandedCardBlurView?.effect = nil
            if self.expandedCardBlurView == nil {
                self.expandedCardBackdropView?.alpha = 0
            }

            if reduceMotion {
                cardView?.alpha = 0
                snapshotView?.alpha = sourceFrame == nil ? 0 : 1
            } else if let sourceFrame {
                self.expandedCardTransitionView?.move(
                    to: sourceFrame,
                    cornerRadius: currentSourceButton?.layer.cornerRadius ?? appearance.row.cornerRadius,
                    visualState: HomeThemeCardTransitionVisualState(progress: 0),
                    shadow: .none,
                    surfaceColor: currentSourceButton?.backgroundColor ?? appearance.row.backgroundColor,
                    borderColor: transitionBorderColor(
                        for: currentSourceButton,
                        fallback: appearance.row.borderColor
                    ),
                    borderWidth: currentSourceButton?.layer.borderWidth ?? appearance.row.borderWidth
                )
            } else {
                self.expandedCardTransitionView?.alpha = 0
            }
        }
        animator.addCompletion { [weak self, weak animator] position in
            guard let self, let animator else { return }
            self.completeExpandedCardAnimation(
                animator: animator,
                position: position,
                expandedPosition: .start,
                targetFrame: targetFrame
            )
        }

        expandedCardAnimator = animator
        animator.startAnimation()
    }

    func collapseExpandedAIThemeCard() {
        guard let cardView = expandedAIThemeCardView else {
            resetExpandedThemeCard()
            return
        }

        freezeExpandedAIKeyboardAnimation(on: cardView)
        _ = cardView.resignPrompt()
        let reduceMotion = cardReduceMotionProvider()
        let currentSourceButton = sourceAIThemeButton()
        let sourceFrame = currentSourceButton.map { $0.convert($0.bounds, to: view) }
        let targetFrame = cardView.convert(cardView.bounds, to: view)
        let appearance = currentAppearance()
        let snapshotView = expandedCardSnapshotView

        if let currentSourceButton {
            let refreshedSourceContent = sourceSnapshotFactory.makeAIThemeContent(from: currentSourceButton)
            refreshedSourceContent.accessibilityIdentifier = AccessibilityID.expandedAIThemeCardSourceSnapshot
            expandedCardSourceContentView?.removeFromSuperview()
            expandedCardSourceContentView = refreshedSourceContent
        }

        let sourceContentView = expandedCardSourceContentView
        if reduceMotion {
            cardView.alpha = 1
            snapshotView?.isHidden = false
            snapshotView?.alpha = 0
            snapshotView?.layer.zPosition = Appearance.expandedCardLayerZPosition + 1
            if let snapshotView, let sourceFrame {
                snapshotView.frame = sourceFrame
                view.addSubview(snapshotView)
            }
            installExpandedCardInteractionButton(
                tracking: [cardView] + [snapshotView].compactMap { $0 }
            )
        } else {
            sourceContentView?.isHidden = false
            cardView.setTransitionShadowHidden(true)
            cardView.setTransitionSurfaceHidden(true)
            let transitionView = makeAIThemeCardTransitionView(
                frame: targetFrame,
                targetFrame: targetFrame,
                surfaceColor: cardView.transitionSurfaceColor,
                borderColor: appearance.card.borderColor,
                borderWidth: appearance.card.borderWidth,
                initialCornerRadius: appearance.card.cornerRadius,
                collapsedCornerRadius: currentSourceButton?.layer.cornerRadius
                    ?? appearance.row.cornerRadius,
                expandedCornerRadius: appearance.card.cornerRadius,
                gradientReferenceWidth: max(sourceFrame?.width ?? 0, targetFrame.width),
                initialVisualState: HomeThemeCardTransitionVisualState(progress: 1),
                initialShadow: appearance.card.shadow
            )
            transitionView.layer.zPosition = Appearance.expandedCardLayerZPosition
            view.addSubview(transitionView)
            if let sourceContentView {
                transitionView.install(
                    destinationView: cardView,
                    sourceContentView: sourceContentView,
                    visualState: HomeThemeCardTransitionVisualState(progress: 1)
                )
            }
            expandedCardTransitionView = transitionView
            installExpandedCardInteractionButton(tracking: [transitionView])
        }

        let animator: UIViewPropertyAnimator
        if reduceMotion {
            animator = UIViewPropertyAnimator(
                duration: AnimationTiming.reducedMotionDuration,
                curve: .easeInOut
            )
        } else {
            animator = UIViewPropertyAnimator(
                duration: AnimationTiming.cardExpansionDuration,
                dampingRatio: AnimationTiming.cardExpansionDampingRatio
            )
        }

        animator.addAnimations { [weak self, weak snapshotView, weak cardView] in
            guard let self else { return }
            self.expandedCardBlurView?.effect = nil
            if self.expandedCardBlurView == nil {
                self.expandedCardBackdropView?.alpha = 0
            }

            if reduceMotion {
                cardView?.alpha = 0
                snapshotView?.alpha = sourceFrame == nil ? 0 : 1
            } else if let sourceFrame {
                self.expandedCardTransitionView?.move(
                    to: sourceFrame,
                    cornerRadius: currentSourceButton?.layer.cornerRadius ?? appearance.row.cornerRadius,
                    visualState: HomeThemeCardTransitionVisualState(progress: 0),
                    shadow: .none,
                    surfaceColor: currentSourceButton?.backgroundColor ?? appearance.row.backgroundColor,
                    borderColor: self.transitionBorderColor(
                        for: currentSourceButton,
                        fallback: appearance.row.borderColor
                    ),
                    borderWidth: currentSourceButton?.layer.borderWidth ?? appearance.row.borderWidth
                )
            } else {
                self.expandedCardTransitionView?.alpha = 0
            }
        }
        animator.addCompletion { [weak self, weak animator] position in
            guard let self, let animator else { return }
            self.completeExpandedCardAnimation(
                animator: animator,
                position: position,
                expandedPosition: .start,
                targetFrame: targetFrame
            )
        }

        expandedCardAnimator = animator
        animator.startAnimation()
    }
}
