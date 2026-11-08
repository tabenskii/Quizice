import UIKit

extension QuizViewController {
    func launchQuiz(
        themeID: String,
        questionCount: Int,
        difficulty: AIQuizDifficulty
    ) {
        guard !isQuizLaunchPending else { return }
        guard let cardView = expandedThemeCardView, let router else {
            homeStore.send(.launchFailed)
            return
        }

        quizTransitionSourceView = cardView.transitionSourceView
        isQuizLaunchPending = true
        hasQuizLaunchStarted = false
        cardView.isUserInteractionEnabled = false
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        quizPreparationTask?.cancel()
        quizPreparationTask = Task { @MainActor [weak self, weak router] in
            guard let self, let router else { return }
            do {
                let preparedTheme = try await self.themeRepository.prepareQuiz(
                    themeID: themeID,
                    questionCount: questionCount,
                    difficulty: difficulty,
                    locale: locale
                )
                try Task.checkCancellation()
                guard
                    self.homeCardState.phase == .launching,
                    self.homeCardState.themeID == themeID,
                    AppLocalizationStore.shared.resolvedLanguageCode == locale
                else {
                    throw CancellationError()
                }

                guard QuizQuestionCountPolicy.usableQuestionCount(
                    in: preparedTheme.questions.map(QuestionModel.init(quizQuestion:))
                ) > 0 else { throw QuizPreparationError.unavailable }
                self.stopQuizPreparationProgress()
                self.session.chosenTheme = ThemeModel(quizTheme: preparedTheme)
                self.session.questionsCount = questionCount
                self.hasQuizLaunchStarted = true
                router.showQuestion()
            } catch is CancellationError {
                guard !Task.isCancelled else { return }
                self.finishFailedQuizPreparation(message: nil)
            } catch {
                guard !Task.isCancelled else { return }
                if QuizPreparationError.isCancellation(error) {
                    self.finishFailedQuizPreparation(message: nil)
                    return
                }
                self.analytics.reportOperationalError(error, context: .contentLoad)
                self.finishFailedQuizPreparation(message: QuizPreparationError.message(for: error))
            }
        }
        startQuizPreparationProgress(for: cardView)
    }

    private func finishFailedQuizPreparation(message: String?) {
        stopQuizPreparationProgress()
        guard isQuizLaunchPending, !hasQuizLaunchStarted else { return }
        homeStore.send(.launchFailed)
        isQuizLaunchPending = false
        quizTransitionSourceView = nil
        expandedThemeCardView?.isUserInteractionEnabled = true
        updateExpandedThemeCardParallaxPhase()
        if let message {
            presentQuizPreparationFailure(message: message) { [weak self] in
                self?.sendHomeCardAction(.startRequested)
            }
        }
    }

    func presentQuizPreparationFailure(message: String, retry: @escaping () -> Void) {
        guard activeQuizPreparationAlert == nil else { return }
        let dismissAction = QuizAlertAction(
            title: L10n.Common.back,
            emphasis: .secondary,
            accessibilityIdentifier: "quizPreparationAlertDismissButton",
            action: { [weak self] in self?.dismissQuizPreparationFailure() }
        )
        let retryAction = QuizAlertAction(
            title: L10n.AITheme.retry,
            emphasis: .primary,
            accessibilityIdentifier: "quizPreparationAlertRetryButton",
            action: { [weak self] in self?.dismissQuizPreparationFailure(completion: retry) }
        )
        let appearance = currentAppearance()
        let overlay = QuizAlertOverlay(
            title: L10n.Question.loadingFailedTitle,
            message: message,
            systemImage: "exclamationmark.triangle.fill",
            iconColor: appearance.accentColor,
            primaryAction: retryAction,
            secondaryAction: dismissAction,
            onEscape: dismissAction.action
        )
        quizPreparationAlertPresenter.presentingViewController = self
        guard quizPreparationAlertPresenter.present(
            overlay,
            appearance: appearance,
            reduceMotion: cardReduceMotionProvider()
        ) else { return }
        activeQuizPreparationAlert = overlay
        quizPreparationAlertPresenter.alertViewController?.view.accessibilityIdentifier = "quizPreparationErrorAlert"
    }

    func dismissQuizPreparationFailure(completion: @escaping () -> Void = {}) {
        guard activeQuizPreparationAlert != nil else { return }
        quizPreparationAlertPresenter.dismiss { [weak self] in
            guard let self, self.activeQuizPreparationAlert != nil else { return }
            self.activeQuizPreparationAlert = nil
            completion()
        }
    }

    private func startQuizPreparationProgress(for cardView: ExpandedThemeCardView) {
        cardView.setStartLoading(true)
    }

    private func stopQuizPreparationProgress() {
        quizPreparationTask = nil
        expandedThemeCardView?.setStartLoading(false)
    }

    func makeExpandedCardBackdrop(appearance: AppAppearance) -> UIView {
        let backdropView: UIView
        if cardReduceTransparencyProvider() {
            let opaqueView = UIView()
            opaqueView.backgroundColor = appearance.backgroundColor.withAlphaComponent(
                Appearance.reducedTransparencyBackdropAlpha
            )
            opaqueView.alpha = 0
            backdropView = opaqueView
            expandedCardBlurView = nil
        } else {
            let blurView = UIVisualEffectView(effect: nil)
            backdropView = blurView
            expandedCardBlurView = blurView
        }

        backdropView.accessibilityIdentifier = AccessibilityID.expandedCardBackdrop
        backdropView.accessibilityElementsHidden = true
        backdropView.isUserInteractionEnabled = false
        let dismissButton = UIButton(type: .custom)
        dismissButton.accessibilityIdentifier = AccessibilityID.expandedCardBackdropDismissButton
        dismissButton.isAccessibilityElement = false
        dismissButton.backgroundColor = .clear
        dismissButton.addTarget(
            self,
            action: #selector(expandedCardBackdropTapped),
            for: .touchUpInside
        )
        expandedCardBackdropDismissButton = dismissButton
        return backdropView
    }

    func installExpandedCardBackdropDismissButton() {
        guard let dismissButton = expandedCardBackdropDismissButton else { return }
        dismissButton.frame = view.bounds
        dismissButton.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dismissButton.layer.zPosition = Appearance.expandedCardBackdropLayerZPosition + 1
        view.addSubview(dismissButton)
    }

    @objc func expandedCardBackdropTapped() {
        switch homeCardState.phase {
        case .expanding, .expandedFront, .expandedBack:
            requestExpandedCardClose()

        case .flippingToBack:
            // Finish the user's dismissal through the sharp front face. Retargeting
            // the interruptible flip avoids waiting for a stale back completion.
            closeAfterFlipToFront = true
            sendHomeCardAction(.flipRequested)

        case .flippingToFront:
            closeAfterFlipToFront = true

        case .grid, .collapsing, .launching:
            break
        }
    }

    func expandedThemeCardFrame() -> CGRect {
        let safeFrame = view.safeAreaLayoutGuide.layoutFrame
        let policy = AppAdaptiveLayout(width: safeFrame.width)
        let width = min(
            max(safeFrame.width - ExpandedCardLayout.horizontalInset * 2, 0),
            policy.expandedCardMaximumWidth
        )
        let top = safeFrame.minY + (policy.isCompact ? ExpandedCardLayout.topInset : 24)
        let maximumBottom = safeFrame.maxY - (policy.isCompact ? ExpandedCardLayout.bottomInset : 24)
        let availableHeight = max(maximumBottom - top, 0)
        let preferredHeight = policy.isCompact ? max(
            width * ExpandedCardLayout.heightToWidthRatio,
            ExpandedCardLayout.minimumHeight
        ) : 672
        let height = min(preferredHeight, availableHeight)
        let centeredY = safeFrame.midY - height / 2
        let originY = max(top, min(centeredY, maximumBottom - height))

        return CGRect(
            x: safeFrame.midX - width / 2,
            y: originY,
            width: width,
            height: height
        ).integral
    }

    func expandedAIThemeCardFrame() -> CGRect {
        expandedThemeCardFrame().offsetBy(dx: 0, dy: -expandedAIKeyboardLift)
    }

    func updateExpandedAIThemeCardFrame(
        _ cardView: ExpandedAIThemeCardView,
        keyboardFrameInWindow: CGRect?,
        duration: TimeInterval,
        options: UIView.AnimationOptions
    ) {
        guard
            cardView === expandedAIThemeCardView,
            cardView.window != nil,
            homeCardState.phase != .collapsing
        else { return }

        expandedAIKeyboardFrame = keyboardFrameInWindow
        freezeExpandedAIKeyboardAnimation(on: cardView)
        let baseFrame = expandedThemeCardFrame()
        let requestedLift: CGFloat
        if let keyboardFrameInWindow, let window = cardView.window {
            let keyboardFrame = view.convert(keyboardFrameInWindow, from: window)
            let desiredPromptBottom = keyboardFrame.minY - ExpandedCardLayout.keyboardSpacing
            let overlapsHorizontally = keyboardFrame.maxX > baseFrame.minX
                && keyboardFrame.minX < baseFrame.maxX
            requestedLift = overlapsHorizontally ? max(
                baseFrame.minY + cardView.promptContainerMaxYAtRest - desiredPromptBottom,
                0
            ) : 0
        } else {
            requestedLift = 0
        }

        let safeTop = view.safeAreaLayoutGuide.layoutFrame.minY
            + ExpandedCardLayout.keyboardMinimumTopInset
        let maximumLift = max(baseFrame.minY - safeTop, 0)
        expandedAIKeyboardLift = min(requestedLift, maximumLift)
        let targetFrame = expandedAIThemeCardFrame()

        guard duration > 0 else {
            cardView.frame = targetFrame
            self.expandedCardInteractionButton?.frame = self.view.bounds
            return
        }

        let curveRawValue = Int(options.rawValue >> 16)
        let curve: UIView.AnimationCurve
        switch curveRawValue {
        case UIView.AnimationCurve.easeInOut.rawValue:
            curve = .easeInOut
        case UIView.AnimationCurve.easeIn.rawValue:
            curve = .easeIn
        case UIView.AnimationCurve.easeOut.rawValue:
            curve = .easeOut
        case UIView.AnimationCurve.linear.rawValue:
            curve = .linear
        default:
            // UIKit commonly reports the keyboard curve value 7.
            // Keep the card synchronized with the keyboard using a supported
            // moving/morphing curve instead of constructing an unknown enum.
            curve = .easeInOut
        }
        let animator = UIViewPropertyAnimator(duration: duration, curve: curve)
        animator.addAnimations { [weak self, weak cardView] in
            guard let self, let cardView else { return }
            cardView.frame = targetFrame
            self.expandedCardInteractionButton?.frame = self.view.bounds
        }
        animator.addCompletion { [weak self, weak animator] _ in
            guard let self, let animator, self.expandedAIKeyboardAnimator === animator else { return }
            self.expandedAIKeyboardAnimator = nil
        }
        expandedAIKeyboardAnimator = animator
        animator.startAnimation()
    }

    func freezeExpandedAIKeyboardAnimation(
        on cardView: ExpandedAIThemeCardView,
        visibleFrameOverride: CGRect? = nil
    ) {
        guard let animator = expandedAIKeyboardAnimator else { return }

        let visibleFrame = visibleFrameOverride ?? cardView.layer.presentation()?.frame
        animator.stopAnimation(true)
        expandedAIKeyboardAnimator = nil
        cardView.layer.removeAllAnimations()

        guard let visibleFrame else { return }
        cardView.frame = visibleFrame
        expandedAIKeyboardLift = max(expandedThemeCardFrame().minY - visibleFrame.minY, 0)
    }

    func sourceButton(themeID: String) -> UIButton? {
        themesCollectionService.visibleThemeCells
            .map(\.actionButton)
            .first(where: { $0.accessibilityIdentifier == themeID })
    }

    func sourceButtonFrame(themeID: String) -> CGRect? {
        guard let button = sourceButton(themeID: themeID) else { return nil }
        return button.convert(button.bounds, to: view)
    }

    func sourceStatisticsButton() -> UIButton? {
        themesCollectionView.visibleCells
            .compactMap { $0 as? StatisticsCardCollectionViewCell }
            .map(\.actionButton)
            .first
    }

    func sourceAIThemeButton() -> UIButton? {
        themesCollectionView.visibleCells
            .lazy
            .flatMap { $0.contentView.subviews }
            .compactMap { $0 as? UIButton }
            .first(where: {
                $0.accessibilityIdentifier == ThemesCollectionService.Content.aiThemeAccessibilityID
            })
    }
}
