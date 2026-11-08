import UIKit
#if DEBUG
import SwiftUI
#endif

extension QuizViewController {
    func setBackgroundAccessibilityHidden(_ isHidden: Bool) {
        headerStackView.accessibilityElementsHidden = isHidden
        screenStackView.accessibilityElementsHidden = isHidden
        settingsButton.accessibilityElementsHidden = isHidden
        helpButton.accessibilityElementsHidden = isHidden
    }

    func refreshExpandedThemeCardAppearance() {
        switch homeCardState.phase {
        case .expanding, .flippingToBack, .flippingToFront:
            expandedCardNeedsRefresh = true
            return
        case .grid, .collapsing:
            return
        case .expandedFront, .expandedBack, .launching:
            break
        }

        if homeCardState.isStatisticsPresented,
           let cardView = expandedStatisticsCardView {
            expandedCardNeedsRefresh = false
            let summary = statisticsStore.loadSummary()
            expandedStatisticsSummary = summary
            cardView.configure(summary: summary, appearance: currentAppearance())
            if expandedCardBlurView == nil {
                expandedCardBackdropView?.backgroundColor = currentAppearance().backgroundColor.withAlphaComponent(
                    Appearance.reducedTransparencyBackdropAlpha
                )
            }
            return
        }

        if homeCardState.isAIThemePresented,
           let cardView = expandedAIThemeCardView {
            expandedCardNeedsRefresh = false
            let face = cardView.face
            cardView.configure(state: homeAIThemeCardState, appearance: currentAppearance())
            cardView.setFace(face, animated: false)
            if expandedCardBlurView == nil {
                expandedCardBackdropView?.backgroundColor = currentAppearance().backgroundColor.withAlphaComponent(
                    Appearance.reducedTransparencyBackdropAlpha
                )
            }
            return
        }

        guard
            let cardView = expandedThemeCardView,
            let themeID = homeCardState.themeID,
            let theme = themeRepository.themes?.first(where: { $0.stableID == themeID }) ?? expandedTheme
        else { return }

        expandedCardNeedsRefresh = false
        let face = cardView.face
        expandedTheme = theme
        cardView.configure(
            theme: theme,
            appearance: currentAppearance(),
            availableQuestionCounts: homeCardState.availableQuestionCounts,
            selectedQuestionCount: homeCardState.selectedQuestionCount,
            selectedDifficulty: homeCardState.selectedDifficulty
        )
        cardView.setFace(face, animated: false)
        updateExpandedThemeCardParallaxPhase()
        if expandedCardBlurView == nil {
            expandedCardBackdropView?.backgroundColor = currentAppearance().backgroundColor.withAlphaComponent(
                Appearance.reducedTransparencyBackdropAlpha
            )
        }
    }

    func resetExpandedThemeCard() {
        expandedCardAnimator?.stopAnimation(true)
        expandedCardAnimator = nil
        if let effect = homeStore.sendAI(.reset) {
            handleAIThemeCardEffect(effect)
        }
        removeExpandedThemeCardViews()
        homeStore.send(.reset)
        guard isViewLoaded else {
            quizTransitionSourceView = nil
            return
        }
        restoreGridAfterExpandedCard(presentedCard: nil)
    }

    func restoreHomeAfterQuizIfNeeded(force: Bool = false) {
        guard force || (isQuizLaunchPending && hasQuizLaunchStarted) else { return }
        cancelFeelingLuckyLaunch()
        quizTransitionSourceView?.isHidden = false
        isQuizLaunchPending = false
        hasQuizLaunchStarted = false
        resetExpandedThemeCard()
    }

    func removeExpandedThemeCardViews() {
        showRoundConfigurationAfterExpansion = false
        quizPreparationTask?.cancel()
        quizPreparationTask = nil
        expandedThemeCardView?.setStartLoading(false)
        aiAlertPresentationTask?.cancel()
        aiAlertPresentationTask = nil
        aiAlertPresenter.dismiss()
        activeQuizPreparationAlert = nil
        quizPreparationAlertPresenter.dismiss()
        expandedAIKeyboardAnimator?.stopAnimation(true)
        expandedAIKeyboardAnimator = nil
        expandedThemeCardView?.setParallaxPresentationPhase(.inactive)
        expandedThemeCardView?.removeFromSuperview()
        expandedStatisticsCardView?.removeFromSuperview()
        expandedAIThemeCardView?.removeFromSuperview()
        expandedCardSnapshotView?.removeFromSuperview()
        expandedCardSourceContentView?.removeFromSuperview()
        expandedCardTransitionView?.removeFromSuperview()
        expandedCardInteractionButton?.removeFromSuperview()
        expandedCardBackdropDismissButton?.removeFromSuperview()
        expandedCardBackdropView?.removeFromSuperview()
        expandedThemeCardView = nil
        expandedStatisticsCardView = nil
        expandedAIThemeCardView = nil
        expandedCardSnapshotView = nil
        expandedCardSourceContentView = nil
        expandedCardSourceContentGeometry = nil
        expandedCardTransitionView = nil
        expandedCardInteractionButton = nil
        expandedCardBackdropDismissButton = nil
        expandedCardBackdropView = nil
        expandedCardBlurView = nil
        expandedTheme = nil
        expandedStatisticsSummary = nil
        aiSubmissionTask?.cancel()
        aiSubmissionTask = nil
        aiProgressTask?.cancel()
        aiProgressTask = nil
        if let effect = homeStore.sendAI(.reset) {
            handleAIThemeCardEffect(effect)
        }
        closeAfterFlipToFront = false
        focusAIThemePromptAfterFlip = false
        expandedCardNeedsRefresh = false
        expandedCardScreenViewTracked = false
        expandedCardLastTrackedFace = nil
        expandedAIKeyboardLift = 0
        expandedAIKeyboardFrame = nil
    }

    func updateExpandedThemeCardParallaxPhase() {
        expandedThemeCardView?.setParallaxPresentationPhase(
            homeCardState.phase.parallaxPresentationPhase
        )
    }

    func restoreGridAfterExpandedCard(presentedCard: HomePresentedCard?) {
        themesCollectionService.presentedThemeID = nil
        themesCollectionService.isStatisticsPresented = false
        themesCollectionService.isAIThemePresented = false
        themesCollectionView.isUserInteractionEnabled = true
        setBackgroundAccessibilityHidden(false)
        updateCollectionScrollAvailability()
        quizTransitionSourceView = nil

        guard let presentedCard else { return }
        themesCollectionView.layoutIfNeeded()
        let focusView: UIView?
        switch presentedCard {
        case let .theme(themeID):
            focusView = sourceButton(themeID: themeID)
        case .statistics:
            focusView = sourceStatisticsButton()
        case .ai:
            focusView = sourceAIThemeButton()
        }
        UIAccessibility.post(
            notification: .screenChanged,
            argument: focusView
        )
    }

#if DEBUG
    var expandedCardAnimatorForTesting: UIViewPropertyAnimator? {
        expandedCardAnimator
    }

    var expandedAIKeyboardAnimatorForTesting: UIViewPropertyAnimator? {
        expandedAIKeyboardAnimator
    }

    var expandedAIKeyboardAnimationCurveForTesting: UIView.AnimationCurve? {
        (expandedAIKeyboardAnimator?.timingParameters as? UICubicTimingParameters)?.animationCurve
    }

    var expandedCardTransitionInitialFrameForTesting: CGRect? {
        expandedCardTransitionView?.targetFrameInRoot
    }

    func updateExpandedAIThemeCardFrameForTesting(
        keyboardFrameInWindow: CGRect?,
        duration: TimeInterval,
        curveRawValue: UInt = UInt(UIView.AnimationCurve.easeInOut.rawValue)
    ) {
        guard let cardView = expandedAIThemeCardView else { return }
        updateExpandedAIThemeCardFrame(
            cardView,
            keyboardFrameInWindow: keyboardFrameInWindow,
            duration: duration,
            options: UIView.AnimationOptions(
                rawValue: curveRawValue << 16
            )
        )
    }

    func freezeExpandedAIKeyboardAnimationForTesting(visibleFrame: CGRect) {
        guard let cardView = expandedAIThemeCardView else { return }
        freezeExpandedAIKeyboardAnimation(
            on: cardView,
            visibleFrameOverride: visibleFrame
        )
    }

    @objc func settingsButtonLongPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        presentDebugMenu()
    }

    func presentDebugMenu() {
        guard !isQuizLaunchPending, presentedViewController == nil else { return }

        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.prepare()
        feedback.impactOccurred()

        let controller = UIHostingController(
            rootView: DebugMenuView(viewModel: makeDebugMenuViewModel())
        )
        controller.view.accessibilityIdentifier = DebugMenuView.AccessibilityID.root
        controller.overrideUserInterfaceStyle = .dark
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .large
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 28
        }
        present(controller, animated: true)
    }

    func makeDebugMenuViewModel() -> DebugMenuViewModel {
        DebugMenuViewModel(
            isInterfaceHidden: isDebugInterfaceHidden,
            isSubscriptionActive:
                SubscriptionEntitlementStore.shared.hasActivePlusSubscription,
            appearance: currentAppearance(),
            toggleInterfaceVisibility: { [weak self] in
                self?.toggleDebugInterfaceVisibility()
            },
            toggleLocalhostBackend: { [weak self] in
                self?.toggleDebugLocalhostBackend()
            },
            toggleLocalContentOnly: { [weak self] in
                self?.toggleDebugLocalContentOnly()
            },
            toggleDirectAI: { [weak self] in
                self?.toggleDebugDirectAI()
            },
            setSubscriptionPromoVisible: { [weak self] isVisible in
                self?.themesCollectionService.showsSubscriptionPromo = isVisible
            },
            setSubscriptionActive: { isActive in
                SubscriptionEntitlementStore.shared.setDebugSubscriptionActive(isActive)
            },
            selectBackgroundStyle: { [weak self] style in
                self?.selectBackgroundStyle(style)
            }
        )
    }

    func selectBackgroundStyle(_ style: AppBackgroundStyle) {
        let store = AppAppearanceStore.shared
        guard store.backgroundStyle != style else { return }

        let feedback = UISelectionFeedbackGenerator()
        feedback.prepare()
        store.backgroundStyle = style
        feedback.selectionChanged()
    }

    func toggleDebugLocalhostBackend() {
        let defaults = UserDefaults.standard
        let usesLocalhostBackend = !defaults.bool(forKey: DebugBackendSettings.useLocalhostKey)
        defaults.set(usesLocalhostBackend, forKey: DebugBackendSettings.useLocalhostKey)
        if usesLocalhostBackend {
            defaults.set(false, forKey: DebugBackendSettings.useLocalContentOnlyKey)
        }

        let feedback = UISelectionFeedbackGenerator()
        feedback.prepare()
        feedback.selectionChanged()
        presentDebugBackendRestartAlert(selection: L10n.Settings.localhostBackend)
    }

    func toggleDebugLocalContentOnly() {
        let defaults = UserDefaults.standard
        let usesLocalContentOnly = !defaults.bool(forKey: DebugBackendSettings.useLocalContentOnlyKey)
        defaults.set(usesLocalContentOnly, forKey: DebugBackendSettings.useLocalContentOnlyKey)
        if usesLocalContentOnly {
            defaults.set(false, forKey: DebugBackendSettings.useLocalhostKey)
        }

        let feedback = UISelectionFeedbackGenerator()
        feedback.prepare()
        feedback.selectionChanged()
        presentDebugBackendRestartAlert(selection: L10n.Settings.localContentOnly)
    }

    func toggleDebugDirectAI(
        prepareAPIKey: () -> Bool = { DebugYandexAIAPIKeyStore.resolveAPIKey() != nil }
    ) {
        let defaults = UserDefaults.standard
        let usesDirectAI = !defaults.bool(forKey: DebugAIRuntimeSettings.useDirectAIKey)
        guard !usesDirectAI || prepareAPIKey() else {
            presentDebugDirectAIMissingKeyAlert()
            return
        }
        defaults.set(usesDirectAI, forKey: DebugAIRuntimeSettings.useDirectAIKey)

        let feedback = UISelectionFeedbackGenerator()
        feedback.prepare()
        feedback.selectionChanged()
        presentDebugBackendRestartAlert(selection: L10n.Settings.directAI)
    }

    private func presentDebugDirectAIMissingKeyAlert() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let presenter = self.debugAlertPresenter() else { return }
            let alert = UIAlertController(
                title: L10n.AITheme.Error.Configuration.title,
                message: L10n.AITheme.Error.Configuration.message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: L10n.Settings.alertAction, style: .default))
            presenter.present(alert, animated: true)
        }
    }

    private func presentDebugBackendRestartAlert(selection: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let presenter = self.debugAlertPresenter() else { return }
            let alert = UIAlertController(
                title: L10n.Settings.restartRequiredTitle,
                message: L10n.Settings.restartRequiredMessage(selection: selection),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: L10n.Settings.alertAction, style: .default))
            presenter.present(alert, animated: true)
        }
    }

    private func debugAlertPresenter() -> UIViewController? {
        var presenter: UIViewController = self
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        guard !(presenter is UIAlertController) else { return nil }
        return presenter
    }
#endif

    @objc func settingsButtonTapped() {
        guard !isQuizLaunchPending else { return }
        router?.showSettings()
    }

    @objc func helpButtonTapped() {
        guard !isQuizLaunchPending, homeCardState.phase == .grid else { return }
        router?.showOnboarding()
    }

#if DEBUG
    func toggleDebugInterfaceVisibility() {
        isDebugInterfaceHidden.toggle()

        headerStackView.isHidden = isDebugInterfaceHidden
        screenStackView.isHidden = isDebugInterfaceHidden
    }
#endif

}
