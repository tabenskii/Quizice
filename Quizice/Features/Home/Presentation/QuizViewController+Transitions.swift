import UIKit

extension QuizViewController {
    func settleCardForWindowResize() {
        if let animator = expandedCardAnimator, animator.state == .active {
            let position: UIViewAnimatingPosition = animator.isReversed ? .start : .end
            animator.stopAnimation(false)
            animator.finishAnimation(at: position)
        }
        expandedThemeCardView?.finishFlipForResize()
        expandedAIThemeCardView?.finishFlipForResize()
        if let card = expandedAIThemeCardView {
            updateExpandedAIThemeCardFrame(
                card, keyboardFrameInWindow: expandedAIKeyboardFrame,
                duration: 0, options: []
            )
            let overlap: CGFloat
            if let keyboard = expandedAIKeyboardFrame, let window = card.window {
                overlap = card.bounds.intersection(card.convert(keyboard, from: window)).height
            } else {
                overlap = 0
            }
            card.updateKeyboardInsets(overlap: overlap, duration: 0, options: [])
        }
    }

    func reverseExpandedCardTransition() {
        guard
            let animator = expandedCardAnimator,
            animator.state == .active
        else { return }

        animator.isReversed.toggle()
    }

    func installExpandedCardInteractionButton(tracking views: [UIView]) {
        expandedCardInteractionButton?.removeFromSuperview()

        let button = ThemeCardTransitionInteractionButton(frame: .zero)
        button.frame = view.bounds
        button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        button.backgroundColor = .clear
        button.accessibilityIdentifier = "homeExpandedThemeCardTransitionSurfaceButton"
        button.isAccessibilityElement = false
        button.trackedViews = views
        button.onTap = { [weak self] in
            // The card surface always means "show the other side". During the
            // source-to-card morph the reducer intentionally ignores the request;
            // background taps are handled independently by the backdrop.
            self?.handleExpandedThemeCardFlipTap()
        }
        button.layer.zPosition = Appearance.expandedCardLayerZPosition + 2
        view.addSubview(button)
        expandedCardInteractionButton = button
    }

    func completeExpandedCardAnimation(
        animator: UIViewPropertyAnimator,
        position: UIViewAnimatingPosition,
        expandedPosition: UIViewAnimatingPosition,
        targetFrame: CGRect
    ) {
        guard expandedCardAnimator === animator else { return }

        let gridPosition: UIViewAnimatingPosition = expandedPosition == .end ? .start : .end
        if position == expandedPosition, homeCardState.phase == .expanding {
            expandedCardAnimator = nil
            completeExpandedCardPresentation(targetFrame: targetFrame)
        } else if position == gridPosition, homeCardState.phase == .collapsing {
            expandedCardAnimator = nil
            completeExpandedCardCollapse()
        }
    }

    func completeExpandedCardPresentation(targetFrame: CGRect) {
        let presentedCard = homeCardState.presentedCard
        completeExpandedCardTransition(targetFrame: targetFrame)
        expandedCardInteractionButton?.removeFromSuperview()
        expandedCardInteractionButton = nil
        expandedCardSnapshotView?.alpha = 0
        expandedCardSnapshotView?.isHidden = true
        expandedCardSourceContentView?.alpha = 0
        expandedCardSourceContentView?.isHidden = true
        homeStore.send(.expansionCompleted)
        if showRoundConfigurationAfterExpansion {
            showRoundConfigurationAfterExpansion = false
            sendHomeCardAction(.flipRequested)
        }
        updateExpandedThemeCardParallaxPhase()
        if expandedCardNeedsRefresh {
            refreshExpandedThemeCardAppearance()
        }
        if presentedCard == .statistics, !expandedCardScreenViewTracked {
            expandedCardScreenViewTracked = true
            let summary = expandedStatisticsSummary ?? statisticsStore.loadSummary()
            analytics.track(.screenView(screen: .statistics))
            analytics.track(
                .statisticsViewed(
                    attemptsCount: summary.playedQuizzes,
                    totalQuestions: summary.totalQuestions,
                    accuracyPercent: summary.percentage
                )
            )
        } else if presentedCard == .ai, !expandedCardScreenViewTracked {
            expandedCardScreenViewTracked = true
            analytics.track(.screenView(screen: .aiThemeCreation, theme: .ai))
        }
        if presentedCard == .ai {
            UIAccessibility.post(
                notification: .screenChanged,
                argument: expandedAIThemeCardView?.frontFocusView
            )
        } else {
            UIAccessibility.post(
                notification: .screenChanged,
                argument: expandedThemeCardView?.frontFocusView
                    ?? expandedStatisticsCardView?.initialFocusView
            )
        }
    }

    func completeExpandedCardCollapse() {
        let presentedCard = homeCardState.presentedCard
        if case .theme = presentedCard {
            analytics.track(
                .quizSetupCancelled(theme: session.chosenTheme?.analyticsTheme ?? .unknown)
            )
        }
        themesCollectionService.presentedThemeID = nil
        themesCollectionService.isStatisticsPresented = false
        themesCollectionService.isAIThemePresented = false
        themesCollectionView.layoutIfNeeded()
        removeExpandedThemeCardViews()
        homeStore.send(.collapseCompleted)
        restoreGridAfterExpandedCard(presentedCard: presentedCard)
    }

    func makeExpandedCardTransitionView(
        frame: CGRect,
        targetFrame: CGRect,
        theme: QuizTheme?,
        appearance: AppAppearance,
        initialCornerRadius: CGFloat,
        initialVisualState: HomeThemeCardTransitionVisualState,
        initialShadow: AppShadowStyle
    ) -> ThemeCardExpansionTransitionView {
        let themeID = theme?.stableID ?? homeCardState.themeID ?? ""
        let tintColor = theme.map(ThemeVisualCatalog.tintColor(for:))
            ?? ThemeVisualCatalog.tintColor(colorHex: nil, themeID: themeID)
        let transitionView = ThemeCardExpansionTransitionView(
            frame: frame,
            targetFrameInRoot: targetFrame,
            surfaceColor: appearance.themeCardBackground(baseColor: tintColor),
            borderColor: appearance.themeCardBorder(baseColor: tintColor),
            borderWidth: appearance.themeCardBorderWidth,
            cornerRadius: initialCornerRadius,
            visualState: initialVisualState,
            shadow: initialShadow
        )
        transitionView.accessibilityIdentifier = AccessibilityID.expandedCardTransition
        return transitionView
    }

    func makeStatisticsCardTransitionView(
        frame: CGRect,
        targetFrame: CGRect,
        surfaceColor: UIColor,
        borderColor: UIColor,
        borderWidth: CGFloat,
        initialCornerRadius: CGFloat,
        initialVisualState: HomeThemeCardTransitionVisualState,
        initialShadow: AppShadowStyle
    ) -> ThemeCardExpansionTransitionView {
        let appearance = currentAppearance()
        let transitionView = ThemeCardExpansionTransitionView(
            frame: frame,
            targetFrameInRoot: targetFrame,
            surfaceColor: surfaceColor,
            borderColor: appearance.designStyle == .radar
                ? appearance.accentColor
                : borderColor,
            borderWidth: borderWidth,
            cornerRadius: initialCornerRadius,
            visualState: initialVisualState,
            shadow: initialShadow,
            usesIntensityLayer: false
        )
        transitionView.accessibilityIdentifier = AccessibilityID.expandedStatisticsCardTransition
        return transitionView
    }

    func makeAIThemeCardTransitionView(
        frame: CGRect,
        targetFrame: CGRect,
        surfaceColor: UIColor,
        borderColor: UIColor,
        borderWidth: CGFloat,
        initialCornerRadius: CGFloat,
        collapsedCornerRadius: CGFloat,
        expandedCornerRadius: CGFloat,
        gradientReferenceWidth: CGFloat,
        initialVisualState: HomeThemeCardTransitionVisualState,
        initialShadow: AppShadowStyle
    ) -> ThemeCardExpansionTransitionView {
        let appearance = currentAppearance()
        let transitionView = ThemeCardExpansionTransitionView(
            frame: frame,
            targetFrameInRoot: targetFrame,
            surfaceColor: surfaceColor,
            borderColor: appearance.designStyle == .radar
                ? appearance.accentColor
                : borderColor,
            borderWidth: borderWidth,
            cornerRadius: initialCornerRadius,
            visualState: initialVisualState,
            shadow: initialShadow,
            usesIntensityLayer: false,
            gradientOutlineConfiguration: appearance.designStyle == .radar
                ? nil
                : ThemeCardTransitionGradientOutlineConfiguration(
                    colors: ExpandedAIThemeCardView.gradientOutlineColors,
                    lineWidth: ExpandedAIThemeCardView.gradientOutlineLineWidth,
                    collapsedCornerRadius: collapsedCornerRadius,
                    expandedCornerRadius: expandedCornerRadius,
                    referenceWidth: gradientReferenceWidth
                ),
            solidBorderColorOverride: appearance.designStyle == .radar
                ? appearance.accentColor
                : nil
        )
        transitionView.accessibilityIdentifier = AccessibilityID.expandedAIThemeCardTransition
        return transitionView
    }

    func transitionBorderColor(for view: UIView?, fallback: UIColor) -> UIColor {
        guard let color = view?.layer.borderColor else { return fallback }
        return UIColor(cgColor: color)
    }

    func completeExpandedCardTransition(targetFrame: CGRect) {
        guard
            let cardView = expandedCardContentView,
            expandedCardTransitionView != nil
        else {
            expandedCardContentView?.alpha = 1
            return
        }

        UIView.performWithoutAnimation {
            cardView.removeFromSuperview()
            cardView.frame = targetFrame
            cardView.alpha = 1
            cardView.layer.zPosition = Appearance.expandedCardLayerZPosition
            expandedThemeCardView?.setTransitionSurfaceHidden(false)
            expandedThemeCardView?.setTransitionShadowHidden(false)
            expandedStatisticsCardView?.setTransitionSurfaceHidden(false)
            expandedStatisticsCardView?.setTransitionShadowHidden(false)
            expandedAIThemeCardView?.setTransitionSurfaceHidden(false)
            expandedAIThemeCardView?.setTransitionShadowHidden(false)
            view.addSubview(cardView)
            expandedCardTransitionView?.removeFromSuperview()
            expandedCardTransitionView = nil
        }
    }
}
