import UIKit

extension QuizViewController {
    func refreshAIServiceNotice() {
        aiServiceNoticeTask?.cancel()
        aiServiceNoticeTask = nil
        guard let cardView = expandedAIThemeCardView else { return }
        cardView.setServiceNotice(nil)
        guard let api = aiServiceStatusAPI else { return }
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        aiServiceNoticeTask = Task { @MainActor [weak self, weak cardView] in
            // Failure (including an older backend's 404) leaves this optional text hidden.
            let notice = try? await api.fetchNotice(locale: locale)
            guard !Task.isCancelled,
                  let self, let cardView,
                  self.expandedAIThemeCardView === cardView,
                  AppLocalizationStore.shared.resolvedLanguageCode == locale else { return }
            cardView.setServiceNotice(notice)
            self.aiServiceNoticeTask = nil
        }
    }

    func sendAIThemeCardAction(_ action: HomeAIThemeCardAction) {
        let effect = homeStore.sendAI(action)
        refreshExpandedAIThemeCard()
        guard let effect else { return }
        handleAIThemeCardEffect(effect)
    }

    func handleAIThemeCardEffect(_ effect: HomeAIThemeCardEffect) {
        switch effect {
        case let .flipAvailabilityChanged(isAllowed):
            homeStore.send(.flipAvailabilityChanged(isAllowed))

        case let .submit(submission):
            startAIThemeSubmission(submission)

        case let .cancelSubmission(submission):
            cancelAIThemeSubmission(submission)

        case .submissionCompleted:
            break

        case let .presentAlert(alert):
            presentAIThemeGenerationAlert(alert)

        case .focusPrompt:
            focusAIThemePrompt()
        }
    }

    func refreshExpandedAIThemeCard() {
        guard let cardView = expandedAIThemeCardView else { return }
        let face = cardView.face
        cardView.configure(state: homeAIThemeCardState, appearance: currentAppearance())
        cardView.setFace(face, animated: false)
    }

    func startAIThemeSubmission(_ submission: HomeAIThemeCardSubmission) {
        guard homeAIThemeCardState.activeSubmission?.id == submission.id else { return }

        aiSubmissionTask?.cancel()
        aiProgressTask?.cancel()
        analytics.track(
            .aiGenerationStarted(
                locale: submission.configuration.locale.identifier,
                promptLength: submission.configuration.theme.count,
                questionCount: submission.configuration.questionCount,
                difficulty: submission.configuration.difficulty
            )
        )
        AppLog.quiz.info(
            "AI quiz submission started: locale=\(submission.configuration.locale.identifier, privacy: .public) prompt_length=\(submission.configuration.theme.count, privacy: .public) questions=\(submission.configuration.questionCount, privacy: .public) difficulty=\(submission.configuration.difficulty.rawValue, privacy: .public)"
        )

        startAIThemeProgressUpdates(for: submission.id)
        let service = aiQuizThemeService
        aiSubmissionTask = Task { @MainActor [weak self] in
            do {
                let theme = try await service.generateQuizTheme(
                    configuration: submission.configuration
                )
                try Task.checkCancellation()
                self?.completeAIThemeSubmission(
                    theme: theme,
                    submission: submission
                )
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.failAIThemeSubmission(error: error, submission: submission)
            }
        }
    }

    func startAIThemeProgressUpdates(for requestID: UUID) {
        aiProgressTask?.cancel()
        aiProgressTask = Task { @MainActor [weak self] in
            do {
                for update in AIQuizGenerationPhase.delayedUpdates {
                    try await Task.sleep(nanoseconds: update.delayNanoseconds)
                    try Task.checkCancellation()
                    guard
                        let self,
                        self.homeAIThemeCardState.activeSubmission?.id == requestID
                    else {
                        return
                    }
                    self.homeStore.sendAI(
                        .progressAdvanced(requestID: requestID, phase: update.phase)
                    )
                    self.refreshExpandedAIThemeCard()
                }
            } catch {
                return
            }
        }
    }

    func completeAIThemeSubmission(
        theme: QuizTheme,
        submission: HomeAIThemeCardSubmission
    ) {
        guard
            homeAIThemeCardState.activeSubmission?.id == submission.id,
            let router
        else { return }
        guard case .submissionCompleted = homeStore.sendAI(
            .submissionSucceeded(requestID: submission.id)
        ) else { return }

        aiSubmissionTask = nil
        aiProgressTask?.cancel()
        aiProgressTask = nil
        refreshExpandedAIThemeCard()
        analytics.track(
            .aiGenerationSucceeded(
                locale: submission.configuration.locale.identifier,
                questionCount: theme.questions.count,
                difficulty: submission.configuration.difficulty,
                durationMilliseconds: aiSubmissionDurationMilliseconds(submission)
            )
        )
        AppLog.quiz.info(
            "AI quiz result accepted: questions=\(theme.questions.count, privacy: .public)"
        )

        theme.aiGenerationConfiguration = submission.configuration
        session.chosenTheme = ThemeModel(quizTheme: theme)
        session.questionsCount = theme.questions.count
        analytics.track(.themeSelected(theme: .ai, method: .ai))
        quizTransitionSourceView = expandedAIThemeCardView
        isQuizLaunchPending = true
        hasQuizLaunchStarted = true
        expandedAIThemeCardView?.isUserInteractionEnabled = false
        router.showQuestion()
    }

    func failAIThemeSubmission(
        error: Error,
        submission: HomeAIThemeCardSubmission
    ) {
        guard homeAIThemeCardState.activeSubmission?.id == submission.id else { return }
        let alert = AIQuizGenerationAlert(error: error)
        guard let effect = homeStore.sendAI(
            .submissionFailed(requestID: submission.id, alert: alert)
        ) else { return }

        aiSubmissionTask = nil
        aiProgressTask?.cancel()
        aiProgressTask = nil
        let errorCode = (error as? YandexAIQuizThemeServiceError)?.analyticsCode ?? "unexpected"
        analytics.track(
            .aiGenerationFailed(
                locale: submission.configuration.locale.identifier,
                errorCode: errorCode,
                durationMilliseconds: aiSubmissionDurationMilliseconds(submission)
            )
        )
        analytics.reportOperationalError(error, context: .aiGeneration(code: errorCode))
        refreshExpandedAIThemeCard()
        handleAIThemeCardEffect(effect)
    }

    func cancelAIThemeSubmission(_ submission: HomeAIThemeCardSubmission) {
        aiSubmissionTask?.cancel()
        aiSubmissionTask = nil
        aiProgressTask?.cancel()
        aiProgressTask = nil
        analytics.track(
            .aiGenerationCancelled(
                locale: submission.configuration.locale.identifier,
                durationMilliseconds: aiSubmissionDurationMilliseconds(submission)
            )
        )
        refreshExpandedAIThemeCard()
    }

    func aiSubmissionDurationMilliseconds(
        _ submission: HomeAIThemeCardSubmission
    ) -> Int {
        max(Int(aiNow().timeIntervalSince(submission.startedAt) * 1_000), 0)
    }

    func presentAIAuthenticationRequiredAlert() {
        let alert = AIQuizGenerationAlert(
            error: YandexAIQuizThemeServiceError.authenticationRequired
        )
        let dismissAction = QuizAlertAction(
            title: L10n.Settings.alertAction,
            emphasis: .primary,
            accessibilityIdentifier: AccessibilityID.aiThemeAlertDismissButton,
            action: { [weak self] in self?.aiAlertPresenter.dismiss() }
        )
        let overlay = QuizAlertOverlay(
            title: alert.title,
            message: alert.message,
            systemImage: alert.kind.systemImage,
            iconColor: alert.kind.iconColor(in: currentAppearance()),
            primaryAction: dismissAction,
            secondaryAction: nil,
            onEscape: dismissAction.action
        )

        aiAlertPresenter.presentingViewController = self
        _ = aiAlertPresenter.present(
            overlay,
            appearance: currentAppearance(),
            reduceMotion: cardReduceMotionProvider()
        )
    }

    func presentAIThemeGenerationAlert(_ alert: AIQuizGenerationAlert) {
        guard homeAIThemeCardState.activeAlert == alert else { return }

        aiAlertPresentationTask?.cancel()
        aiAlertPresentationTask = nil
        if tryPresentAIThemeGenerationAlert(alert) { return }

        aiAlertPresentationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.homeAIThemeCardState.activeAlert == alert else { return }
                do {
                    try await Task.sleep(nanoseconds: 50_000_000)
                } catch {
                    return
                }

                guard
                    !Task.isCancelled,
                    self.homeAIThemeCardState.activeAlert == alert
                else { return }
                if self.tryPresentAIThemeGenerationAlert(alert) {
                    self.aiAlertPresentationTask = nil
                    return
                }
            }
        }
    }

    func tryPresentAIThemeGenerationAlert(_ alert: AIQuizGenerationAlert) -> Bool {
        aiAlertPresenter.presentingViewController = self
        return aiAlertPresenter.present(
            makeAIThemeGenerationAlertOverlay(alert),
            appearance: currentAppearance(),
            reduceMotion: cardReduceMotionProvider()
        )
    }

    func makeAIThemeGenerationAlertOverlay(_ alert: AIQuizGenerationAlert) -> QuizAlertOverlay {
        let dismissAction = QuizAlertAction(
            title: alert.offersEditAction
                ? L10n.AITheme.editTheme
                : L10n.Settings.alertAction,
            emphasis: alert.canRetry ? .secondary : .primary,
            accessibilityIdentifier: AccessibilityID.aiThemeAlertDismissButton,
            action: { [weak self] in self?.dismissAIThemeGenerationAlert(alert) }
        )

        let primaryAction: QuizAlertAction
        let secondaryAction: QuizAlertAction?
        if alert.canRetry {
            primaryAction = QuizAlertAction(
                title: L10n.AITheme.retry,
                emphasis: .primary,
                accessibilityIdentifier: AccessibilityID.aiThemeAlertRetryButton,
                action: { [weak self] in self?.retryAIThemeGeneration(after: alert) }
            )
            secondaryAction = dismissAction
        } else {
            primaryAction = dismissAction
            secondaryAction = nil
        }

        return QuizAlertOverlay(
            title: alert.title,
            message: alert.message,
            systemImage: alert.kind.systemImage,
            iconColor: alert.kind.iconColor(in: currentAppearance()),
            primaryAction: primaryAction,
            secondaryAction: secondaryAction,
            onEscape: dismissAction.action
        )
    }

    func retryAIThemeGeneration(after alert: AIQuizGenerationAlert) {
        guard homeAIThemeCardState.activeAlert == alert else { return }
        dismissAIThemeAlertPresentation { [weak self] in
            guard
                let self,
                self.homeAIThemeCardState.activeAlert == alert
            else { return }
            self.clearAIThemeGenerationAlert()
            self.sendAIThemeCardAction(
                .submitRequested(
                    requestID: self.aiRequestIDProvider(),
                    locale: AppLocalizationStore.shared.resolvedLocale,
                    now: self.aiNow()
                )
            )
        }
    }

    func dismissAIThemeGenerationAlert(_ alert: AIQuizGenerationAlert) {
        guard homeAIThemeCardState.activeAlert == alert else { return }
        dismissAIThemeAlertPresentation { [weak self] in
            guard
                let self,
                self.homeAIThemeCardState.activeAlert == alert
            else { return }
            if alert.offersEditAction {
                self.editAIThemeAfterAlert()
            } else {
                self.clearAIThemeGenerationAlert()
            }
        }
    }

    func dismissAIThemeAlertPresentation(completion: @escaping () -> Void) {
        aiAlertPresentationTask?.cancel()
        aiAlertPresentationTask = nil
        aiAlertPresenter.dismiss(completion: completion)
    }

    func clearAIThemeGenerationAlert() {
        homeStore.sendAI(.alertDismissed)
        refreshExpandedAIThemeCard()
    }

    func editAIThemeAfterAlert() {
        clearAIThemeGenerationAlert()
        focusAIThemePromptAfterFlip = true
        if homeCardState.phase == .expandedBack {
            sendHomeCardAction(.flipRequested)
        } else {
            focusAIThemePrompt()
        }
    }
}
