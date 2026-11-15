import UIKit

extension QuizViewController {
    func expandThemeCard(theme: QuizTheme, from sourceView: UIView) {
        guard expandedThemeCardView == nil, expandedCardBackdropView == nil else { return }

        expandedCardScreenViewTracked = false
        view.layoutIfNeeded()
        let sourceFrame = sourceView.convert(sourceView.bounds, to: view)
        let targetFrame = expandedThemeCardFrame()
        let appearance = currentAppearance()
        let reduceMotion = cardReduceMotionProvider()
        let snapshotView = sourceView.snapshotView(afterScreenUpdates: false)
            ?? sourceSnapshotFactory.makeFallback(from: sourceView)
        snapshotView.frame = sourceFrame
        snapshotView.layer.cornerRadius = sourceView.layer.cornerRadius
        snapshotView.layer.cornerCurve = sourceView.layer.cornerCurve
        snapshotView.layer.masksToBounds = true
        snapshotView.layer.zPosition = Appearance.expandedCardLayerZPosition + 1
        snapshotView.accessibilityIdentifier = "homeExpandedThemeCardReducedMotionSourceSnapshot"

        let sourceContent = sourceSnapshotFactory.makeThemeContent(from: sourceView)
        let sourceContentView = sourceContent.view
        sourceContentView.accessibilityIdentifier = AccessibilityID.expandedCardSourceSnapshot

        expandedTheme = theme
        expandedCardLastTrackedFace = .front
        themesCollectionService.presentedThemeID = theme.stableID
        themesCollectionView.isUserInteractionEnabled = false
        updateCollectionScrollAvailability()
        setBackgroundAccessibilityHidden(true)

        let backdropView = makeExpandedCardBackdrop(appearance: appearance)
        backdropView.frame = view.bounds
        backdropView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backdropView.layer.zPosition = Appearance.expandedCardBackdropLayerZPosition
        view.addSubview(backdropView)
        expandedCardBackdropView = backdropView
        installExpandedCardBackdropDismissButton()

        let cardView = ExpandedThemeCardView(frame: targetFrame)
        cardView.reduceMotionProvider = cardReduceMotionProvider
        cardView.deviceParallaxEnabledProvider = cardDeviceParallaxEnabledProvider
        cardView.deviceMotionProvider = cardMotionProvider
        cardView.accessibilityIdentifier = AccessibilityID.expandedCard
        cardView.layer.zPosition = Appearance.expandedCardLayerZPosition
        cardView.configure(
            theme: theme,
            appearance: appearance,
            availableQuestionCounts: homeCardState.availableQuestionCounts,
            selectedQuestionCount: homeCardState.selectedQuestionCount,
            selectedDifficulty: homeCardState.selectedDifficulty
        )
        cardView.setParallaxPresentationPhase(homeCardState.phase.parallaxPresentationPhase)
        wireExpandedThemeCardActions(cardView)
        cardView.layoutIfNeeded()
        expandedThemeCardView = cardView

        if reduceMotion {
            cardView.alpha = 0
            view.addSubview(cardView)
            view.addSubview(snapshotView)
            installExpandedCardInteractionButton(tracking: [cardView, snapshotView])
        } else {
            cardView.setTransitionShadowHidden(true)
            cardView.setTransitionSurfaceHidden(true)
            let transitionView = makeExpandedCardTransitionView(
                frame: sourceFrame,
                targetFrame: targetFrame,
                theme: theme,
                appearance: appearance,
                initialCornerRadius: sourceView.layer.cornerRadius,
                initialVisualState: HomeThemeCardTransitionVisualState(progress: 0),
                initialShadow: appearance.themeCardShadow
            )
            transitionView.layer.zPosition = Appearance.expandedCardLayerZPosition
            view.addSubview(transitionView)
            transitionView.install(
                destinationView: cardView,
                sourceContentView: sourceContentView,
                visualState: HomeThemeCardTransitionVisualState(progress: 0),
                destinationProgressHandler: { [weak cardView] progress in
                    cardView?.setTransitionContentProgress(
                        progress,
                        sourceGeometry: sourceContent.geometry
                    )
                }
            )
            expandedCardTransitionView = transitionView
            installExpandedCardInteractionButton(tracking: [transitionView])
        }

        expandedCardSnapshotView = snapshotView
        expandedCardSourceContentView = sourceContentView
        expandedCardSourceContentGeometry = sourceContent.geometry

        if reduceMotion, expandedCardBlurView == nil {
            backdropView.alpha = 0
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

        animator.addAnimations { [weak self, weak snapshotView, weak cardView, weak backdropView] in
            guard let self else { return }
            if let blurView = self.expandedCardBlurView {
                blurView.effect = UIBlurEffect(style: .systemMaterial)
            } else {
                backdropView?.alpha = 1
            }

            if reduceMotion {
                snapshotView?.alpha = 0
                cardView?.alpha = 1
            } else {
                self.expandedCardTransitionView?.move(
                    to: targetFrame,
                    cornerRadius: appearance.themeCardCornerRadius,
                    visualState: HomeThemeCardTransitionVisualState(progress: 1),
                    shadow: appearance.card.shadow
                )
            }
        }
        animator.addCompletion { [weak self, weak animator] position in
            guard let self, let animator else { return }
            self.completeExpandedCardAnimation(
                animator: animator,
                position: position,
                expandedPosition: .end,
                targetFrame: targetFrame
            )
        }

        expandedCardAnimator = animator
        animator.startAnimation()
    }

    func expandStatisticsCard(
        summary: StatisticsSummary,
        from sourceView: UIView
    ) {
        guard
            expandedThemeCardView == nil,
            expandedStatisticsCardView == nil,
            expandedCardBackdropView == nil
        else { return }

        expandedCardScreenViewTracked = false
        view.layoutIfNeeded()
        let sourceFrame = sourceView.convert(sourceView.bounds, to: view)
        let targetFrame = expandedThemeCardFrame()
        let appearance = currentAppearance()
        let reduceMotion = cardReduceMotionProvider()
        let snapshotView = sourceView.snapshotView(afterScreenUpdates: false)
            ?? sourceSnapshotFactory.makeFallback(from: sourceView)
        snapshotView.frame = sourceFrame
        snapshotView.layer.cornerRadius = sourceView.layer.cornerRadius
        snapshotView.layer.cornerCurve = sourceView.layer.cornerCurve
        snapshotView.layer.masksToBounds = true
        snapshotView.layer.zPosition = Appearance.expandedCardLayerZPosition + 1
        snapshotView.accessibilityIdentifier = "homeExpandedStatisticsCardReducedMotionSourceSnapshot"

        let sourceContentView = sourceSnapshotFactory.makeStatisticsContent(from: sourceView)
        sourceContentView.accessibilityIdentifier = AccessibilityID.expandedStatisticsCardSourceSnapshot

        expandedStatisticsSummary = summary
        themesCollectionService.isStatisticsPresented = true
        themesCollectionView.isUserInteractionEnabled = false
        updateCollectionScrollAvailability()
        setBackgroundAccessibilityHidden(true)

        let backdropView = makeExpandedCardBackdrop(appearance: appearance)
        backdropView.frame = view.bounds
        backdropView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backdropView.layer.zPosition = Appearance.expandedCardBackdropLayerZPosition
        view.addSubview(backdropView)
        expandedCardBackdropView = backdropView
        installExpandedCardBackdropDismissButton()

        let cardView = ExpandedStatisticsCardView(frame: targetFrame)
        cardView.accessibilityIdentifier = AccessibilityID.expandedStatisticsCard
        cardView.layer.zPosition = Appearance.expandedCardLayerZPosition
        cardView.configure(summary: summary, appearance: appearance)
        wireExpandedStatisticsCardActions(cardView)
        cardView.layoutIfNeeded()
        expandedStatisticsCardView = cardView

        if reduceMotion {
            cardView.alpha = 0
            view.addSubview(cardView)
            view.addSubview(snapshotView)
            installExpandedCardInteractionButton(tracking: [cardView, snapshotView])
        } else {
            cardView.setTransitionShadowHidden(true)
            cardView.setTransitionSurfaceHidden(true)
            let transitionView = makeStatisticsCardTransitionView(
                frame: sourceFrame,
                targetFrame: targetFrame,
                surfaceColor: sourceView.backgroundColor ?? .clear,
                borderColor: transitionBorderColor(
                    for: sourceView,
                    fallback: appearance.row.borderColor
                ),
                borderWidth: sourceView.layer.borderWidth,
                initialCornerRadius: sourceView.layer.cornerRadius,
                initialVisualState: HomeThemeCardTransitionVisualState(progress: 0),
                initialShadow: .none
            )
            transitionView.layer.zPosition = Appearance.expandedCardLayerZPosition
            view.addSubview(transitionView)
            transitionView.install(
                destinationView: cardView,
                sourceContentView: sourceContentView,
                visualState: HomeThemeCardTransitionVisualState(progress: 0)
            )
            expandedCardTransitionView = transitionView
            installExpandedCardInteractionButton(tracking: [transitionView])
        }

        expandedCardSnapshotView = snapshotView
        expandedCardSourceContentView = sourceContentView
        expandedCardSourceContentGeometry = nil

        if reduceMotion, expandedCardBlurView == nil {
            backdropView.alpha = 0
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

        animator.addAnimations { [weak self, weak snapshotView, weak cardView, weak backdropView] in
            guard let self else { return }
            if let blurView = self.expandedCardBlurView {
                blurView.effect = UIBlurEffect(style: .systemMaterial)
            } else {
                backdropView?.alpha = 1
            }

            if reduceMotion {
                snapshotView?.alpha = 0
                cardView?.alpha = 1
            } else {
                self.expandedCardTransitionView?.move(
                    to: targetFrame,
                    cornerRadius: appearance.card.cornerRadius,
                    visualState: HomeThemeCardTransitionVisualState(progress: 1),
                    shadow: appearance.card.shadow,
                    surfaceColor: appearance.card.backgroundColor,
                    borderColor: appearance.card.borderColor,
                    borderWidth: appearance.card.borderWidth
                )
            }
        }
        animator.addCompletion { [weak self, weak animator] position in
            guard let self, let animator else { return }
            self.completeExpandedCardAnimation(
                animator: animator,
                position: position,
                expandedPosition: .end,
                targetFrame: targetFrame
            )
        }

        expandedCardAnimator = animator
        animator.startAnimation()
    }

    func expandAIThemeCard(from sourceView: UIView) {
        guard
            expandedThemeCardView == nil,
            expandedStatisticsCardView == nil,
            expandedAIThemeCardView == nil,
            expandedCardBackdropView == nil
        else { return }

        if let effect = homeStore.sendAI(.reset) {
            handleAIThemeCardEffect(effect)
        }
        expandedCardScreenViewTracked = false
        expandedCardLastTrackedFace = .front
        view.layoutIfNeeded()
        let sourceFrame = sourceView.convert(sourceView.bounds, to: view)
        let targetFrame = expandedThemeCardFrame()
        let appearance = currentAppearance()
        let reduceMotion = cardReduceMotionProvider()
        let snapshotView = sourceView.snapshotView(afterScreenUpdates: false)
            ?? sourceSnapshotFactory.makeFallback(from: sourceView)
        snapshotView.frame = sourceFrame
        snapshotView.layer.cornerRadius = sourceView.layer.cornerRadius
        snapshotView.layer.cornerCurve = sourceView.layer.cornerCurve
        snapshotView.layer.masksToBounds = true
        snapshotView.layer.zPosition = Appearance.expandedCardLayerZPosition + 1
        snapshotView.accessibilityIdentifier = "homeExpandedAIThemeCardReducedMotionSourceSnapshot"

        let sourceContentView = sourceSnapshotFactory.makeAIThemeContent(from: sourceView)
        sourceContentView.accessibilityIdentifier = AccessibilityID.expandedAIThemeCardSourceSnapshot

        themesCollectionService.isAIThemePresented = true
        themesCollectionView.isUserInteractionEnabled = false
        updateCollectionScrollAvailability()
        setBackgroundAccessibilityHidden(true)

        let backdropView = makeExpandedCardBackdrop(appearance: appearance)
        backdropView.frame = view.bounds
        backdropView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backdropView.layer.zPosition = Appearance.expandedCardBackdropLayerZPosition
        view.addSubview(backdropView)
        expandedCardBackdropView = backdropView
        installExpandedCardBackdropDismissButton()

        let cardView = ExpandedAIThemeCardView(frame: targetFrame)
        cardView.reduceMotionProvider = cardReduceMotionProvider
        cardView.accessibilityIdentifier = AccessibilityID.expandedAIThemeCard
        cardView.layer.zPosition = Appearance.expandedCardLayerZPosition
        cardView.configure(state: homeAIThemeCardState, appearance: appearance)
        wireExpandedAIThemeCardActions(cardView)
        cardView.layoutIfNeeded()
        let expandedSurfaceColor = cardView.transitionSurfaceColor
        expandedAIThemeCardView = cardView
        refreshAIServiceNotice()

        if reduceMotion {
            cardView.alpha = 0
            view.addSubview(cardView)
            view.addSubview(snapshotView)
            installExpandedCardInteractionButton(tracking: [cardView, snapshotView])
        } else {
            cardView.setTransitionShadowHidden(true)
            cardView.setTransitionSurfaceHidden(true)
            let transitionView = makeAIThemeCardTransitionView(
                frame: sourceFrame,
                targetFrame: targetFrame,
                surfaceColor: sourceView.backgroundColor ?? appearance.card.backgroundColor,
                borderColor: transitionBorderColor(
                    for: sourceView,
                    fallback: appearance.card.borderColor
                ),
                borderWidth: sourceView.layer.borderWidth,
                initialCornerRadius: sourceView.layer.cornerRadius,
                collapsedCornerRadius: sourceView.layer.cornerRadius,
                expandedCornerRadius: appearance.card.cornerRadius,
                gradientReferenceWidth: max(sourceFrame.width, targetFrame.width),
                initialVisualState: HomeThemeCardTransitionVisualState(progress: 0),
                initialShadow: .none
            )
            transitionView.layer.zPosition = Appearance.expandedCardLayerZPosition
            view.addSubview(transitionView)
            transitionView.install(
                destinationView: cardView,
                sourceContentView: sourceContentView,
                visualState: HomeThemeCardTransitionVisualState(progress: 0)
            )
            expandedCardTransitionView = transitionView
            installExpandedCardInteractionButton(tracking: [transitionView])
        }

        expandedCardSnapshotView = snapshotView
        expandedCardSourceContentView = sourceContentView
        expandedCardSourceContentGeometry = nil

        if reduceMotion, expandedCardBlurView == nil {
            backdropView.alpha = 0
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

        animator.addAnimations { [weak self, weak snapshotView, weak cardView, weak backdropView] in
            guard let self else { return }
            if let blurView = self.expandedCardBlurView {
                blurView.effect = UIBlurEffect(style: .systemMaterial)
            } else {
                backdropView?.alpha = 1
            }

            if reduceMotion {
                snapshotView?.alpha = 0
                cardView?.alpha = 1
            } else {
                self.expandedCardTransitionView?.move(
                    to: targetFrame,
                    cornerRadius: appearance.card.cornerRadius,
                    visualState: HomeThemeCardTransitionVisualState(progress: 1),
                    shadow: appearance.card.shadow,
                    surfaceColor: expandedSurfaceColor,
                    borderColor: appearance.card.borderColor,
                    borderWidth: appearance.card.borderWidth
                )
            }
        }
        animator.addCompletion { [weak self, weak animator] position in
            guard let self, let animator else { return }
            self.completeExpandedCardAnimation(
                animator: animator,
                position: position,
                expandedPosition: .end,
                targetFrame: targetFrame
            )
        }

        expandedCardAnimator = animator
        animator.startAnimation()
    }

    func wireExpandedThemeCardActions(_ cardView: ExpandedThemeCardView) {
        cardView.onClose = { [weak self] in
            self?.sendHomeCardAction(.closeRequested)
        }
        cardView.onFlip = { [weak self] in
            self?.handleExpandedThemeCardFlipTap()
        }
        cardView.onBack = { [weak self] in
            self?.handleExpandedThemeCardFlipTap()
        }
        cardView.onCountryChanged = { [weak self] country in
            guard let self, let theme = self.expandedTheme,
                  theme.stableID == "politics_business", !self.isQuizLaunchPending else { return }
            QuestionCountryStore.shared.country = country
            // Drop any prepared batch; keep only the current catalog metadata.
            self.session.chosenTheme = ThemeModel(quizTheme: theme)
        }
        cardView.onDifficultyChanged = { [weak self] difficulty in
            self?.sendHomeCardAction(.difficultySelected(difficulty))
        }
        cardView.onQuestionCountChanged = { [weak self] count in
            self?.sendHomeCardAction(.questionCountSelected(count))
        }
        cardView.onStart = { [weak self] in
            self?.sendHomeCardAction(.startRequested)
        }
        cardView.onAccessibilityEscape = { [weak self] in
            self?.handleExpandedCardAccessibilityEscape()
        }
    }

    func wireExpandedStatisticsCardActions(_ cardView: ExpandedStatisticsCardView) {
        cardView.onClose = { [weak self] in
            self?.sendHomeCardAction(.closeRequested)
        }
        cardView.onAccessibilityEscape = { [weak self] in
            self?.sendHomeCardAction(.closeRequested)
        }
    }

    func wireExpandedAIThemeCardActions(_ cardView: ExpandedAIThemeCardView) {
        cardView.onClose = { [weak self] in
            self?.requestExpandedCardClose()
        }
        cardView.onFlip = { [weak self] in
            self?.handleExpandedThemeCardFlipTap()
        }
        cardView.onBack = { [weak self] in
            guard let self else { return }
            if self.homeAIThemeCardState.isSubmitting {
                self.sendAIThemeCardAction(.cancelRequested)
            }
            self.focusAIThemePromptAfterFlip = true
            self.handleExpandedThemeCardFlipTap()
        }
        cardView.onPromptChanged = { [weak self] prompt in
            self?.sendAIThemeCardAction(.promptChanged(prompt))
        }
        cardView.onQuestionCountChanged = { [weak self] count in
            self?.sendAIThemeCardAction(.questionCountSelected(count))
        }
        cardView.onDifficultyChanged = { [weak self] difficulty in
            self?.sendAIThemeCardAction(.difficultySelected(difficulty))
        }
        cardView.onSubmit = { [weak self] in
            guard let self else { return }
            self.sendAIThemeCardAction(
                .submitRequested(
                    requestID: self.aiRequestIDProvider(),
                    locale: AppLocalizationStore.shared.resolvedLocale,
                    now: self.aiNow()
                )
            )
        }
        cardView.onAccessibilityEscape = { [weak self] in
            self?.handleExpandedCardAccessibilityEscape()
        }
        cardView.onKeyboardFrameChange = { [weak self, weak cardView] frame, duration, options in
            guard let self, let cardView else { return }
            self.updateExpandedAIThemeCardFrame(
                cardView,
                keyboardFrameInWindow: frame,
                duration: duration,
                options: options
            )
        }
    }
}
