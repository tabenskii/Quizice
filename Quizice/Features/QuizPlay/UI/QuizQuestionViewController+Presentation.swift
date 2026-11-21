import UIKit
import AVKit
import SwiftUI

extension QuizQuestionViewController {
    // `exceptFocused` lets the caller keep one button (the one the user just
    // double-tapped, which still holds real VoiceOver focus) enabled a
    // little longer. Disabling the currently-focused element immediately
    // makes VoiceOver auto-jump to a neighbor and announce it, talking over
    // the correct/wrong announcement below. `announceAnswerResult` disables
    // it for real once that announcement has actually finished.
    func colorAndDisableButtons(exceptFocused focusedButton: UIButton? = nil) {
        let appearance = currentAppearance()
        for (index, button) in answerButtons.enumerated() {
            if button !== focusedButton {
                button.isEnabled = false
            }
            guard
                let presenter,
                currentAnswerOptions.indices.contains(index)
            else { continue }
            switch presenter.answerFeedback(for: currentAnswerOptions[index].id) {
            case .correct:
                applyAnswerFeedback(.correct, to: button, appearance: appearance, animated: true)
            case .wrong:
                applyAnswerFeedback(.wrong, to: button, appearance: appearance, animated: true)
            case .normal:
                applyAnswerFeedback(.normal, to: button, appearance: appearance, animated: true)
            }
        }
        revealQuestionExplanation()
    }
    
    func resetAllColors() {
        currentAnswerWasCorrect = nil
        let appearance = currentAppearance()
        answerButtons.forEach { button in
            applyAnswerFeedback(.normal, to: button, appearance: appearance)
            button.isEnabled = true
        }
        setTimerBarColor(quizThemeAccentColor(for: appearance))
    }
    
    func loadQuestionToView(_ viewModel: QuizQuestionViewModel) {
        guard !isQuestionTransitionInProgress else { return }

        guard hasLoadedQuestion else {
            applyQuestion(viewModel, updatesQuestionNumber: true)
            hasLoadedQuestion = true
            presenter?.startTimer()
            return
        }

        guard shouldAnimateQuestionTransition else {
            finishQuestionTransition(with: viewModel, animatedQuestionNumber: false)
            return
        }

        animateQuestionTransition(to: viewModel)
    }

    var shouldAnimateQuestionTransition: Bool {
        questionCardView.window != nil && !UIAccessibility.isReduceMotionEnabled
    }

    func applyQuestion(_ viewModel: QuizQuestionViewModel, updatesQuestionNumber: Bool) {
        setQuestionInfoButtonVisible(false)
        setQuestionExplanationVisible(false, animated: false, movesAccessibilityFocus: false)
        questionInfoButton.alpha = 1
        questionExplanationLabel.text = viewModel.explanation
        questionExplanationScrollView.setContentOffset(.zero, animated: false)
        questionBodyScrollView.setContentOffset(.zero, animated: false)
        resetAllColors()

        // The incoming card is prepared off-screen. Put its timer in the initial
        // state before the slide begins so no frame can expose the previous value.
        updateProgress(1)
        themeNameLabel.text = viewModel.themeName
        questionLabel.text = viewModel.questionText
        applyAnswers(viewModel.answers)
        if updatesQuestionNumber {
            questionNumberLabel.text = viewModel.questionNumberText
        }
        announceQuestionLoaded(viewModel)
    }

    // VoiceOver relies on this announcement to know a new question has appeared.
    // Focus alone isn't enough — the question label is inside a card that
    // animates in, and by the time VO would find it the user has moved on.
    //
    // The Next button from the previous question can still hold real
    // VoiceOver focus at this point. Disabling it while it's focused makes
    // VoiceOver jump in on its own and announce whatever neighbor it lands
    // on, talking over this sequence — so focus is moved to the close button
    // *first*, and Next is only disabled once that's settled. Reading order:
    // exit, theme, question number, then the question itself (ending with
    // real focus on the question, not stuck back on Next).
    func announceQuestionLoaded(_ viewModel: QuizQuestionViewModel) {
        guard UIAccessibility.isVoiceOverRunning else {
            nextButton.isEnabled = false
            return
        }

        VoiceOverAnnouncer.focus(closeButton, label: closeButton.accessibilityLabel) { [weak self] in
            guard let self else { return }
            self.nextButton.isEnabled = false
            VoiceOverAnnouncer.announce([
                viewModel.themeName,
                viewModel.questionNumberText
            ]) { [weak self] in
                guard let self else { return }
                UIAccessibility.post(notification: .layoutChanged, argument: self.questionLabel)
            }
        }
    }

    func animateQuestionTransition(to viewModel: QuizQuestionViewModel) {
        guard let containerView = questionCardView.superview else {
            finishQuestionTransition(with: viewModel, animatedQuestionNumber: false)
            return
        }

        containerView.layoutIfNeeded()
        guard let outgoingCardSnapshot = questionCardView.snapshotView(afterScreenUpdates: false) else {
            finishQuestionTransition(with: viewModel, animatedQuestionNumber: false)
            return
        }

        isQuestionTransitionInProgress = true
        questionCardView.isUserInteractionEnabled = false

        outgoingCardSnapshot.frame = questionCardView.frame
        containerView.insertSubview(outgoingCardSnapshot, aboveSubview: questionCardView)
        outgoingQuestionCardSnapshot = outgoingCardSnapshot

        let horizontalOffset = QuizCardSlideTransition.horizontalOffset(
            in: containerView,
            horizontalInset: Layout.cardHorizontalInset
        )
        questionCardView.transform = CGAffineTransform(translationX: horizontalOffset, y: 0)
        applyQuestion(viewModel, updatesQuestionNumber: false)

        UIView.transition(
            with: questionNumberLabel,
            duration: AnimationTiming.questionNumberTransitionDuration,
            options: [.transitionCrossDissolve, .allowUserInteraction],
            animations: {
                self.questionNumberLabel.text = viewModel.questionNumberText
            }
        )

        UIView.animate(
            withDuration: QuizCardSlideTransition.questionAdvanceDuration,
            delay: 0,
            options: QuizCardSlideTransition.options,
            animations: {
                outgoingCardSnapshot.transform = CGAffineTransform(translationX: -horizontalOffset, y: 0)
                self.questionCardView.transform = .identity
            },
            completion: { _ in
                outgoingCardSnapshot.removeFromSuperview()
                self.outgoingQuestionCardSnapshot = nil
                self.questionCardView.transform = .identity
                self.completeQuestionTransition()
            }
        )
    }

    func finishQuestionTransition(with viewModel: QuizQuestionViewModel, animatedQuestionNumber: Bool) {
        isQuestionTransitionInProgress = false
        questionCardView.isUserInteractionEnabled = true
        questionCardView.transform = .identity
        applyQuestion(viewModel, updatesQuestionNumber: !animatedQuestionNumber)
        if animatedQuestionNumber {
            UIView.transition(
                with: questionNumberLabel,
                duration: AnimationTiming.questionNumberTransitionDuration,
                options: [.transitionCrossDissolve, .allowUserInteraction],
                animations: {
                    self.questionNumberLabel.text = viewModel.questionNumberText
                }
            )
        }
        presenter?.startTimer()
    }

    func finishQuestionAnimationForResize() {
        guard isQuestionTransitionInProgress else { return }
        // The incoming question is already applied. Complete it once, even if
        // removing UIKit animations synchronously invokes their completion.
        completeQuestionTransition()
        outgoingQuestionCardSnapshot?.layer.removeAllAnimations()
        outgoingQuestionCardSnapshot?.removeFromSuperview()
        outgoingQuestionCardSnapshot = nil
        questionCardView.layer.removeAllAnimations()
        questionCardView.transform = .identity
    }

    func completeQuestionTransition() {
        guard isQuestionTransitionInProgress else { return }
        isQuestionTransitionInProgress = false
        questionCardView.isUserInteractionEnabled = true
        presenter?.startTimer()
    }
    
    func applyAnswers(_ currentAnswers: [QuizAnswerOption]) {
        currentAnswerOptions = currentAnswers
        for (index, button) in answerButtons.enumerated() {
            let hasAnswer = currentAnswers.indices.contains(index)
            button.setTitle(hasAnswer ? currentAnswers[index].title : L10n.Question.unavailableAnswer, for: .normal)
            button.isEnabled = hasAnswer
        }
        layoutContentIfPossible()
    }
    
    func showQuestionUnavailable(themeName: String?, message: String) {
        currentAnswerWasCorrect = nil
        hasLoadedQuestion = false
        isQuestionTransitionInProgress = false
        outgoingQuestionCardSnapshot?.removeFromSuperview()
        outgoingQuestionCardSnapshot = nil
        questionCardView.transform = .identity
        questionCardView.isUserInteractionEnabled = true
        setQuestionInfoButtonVisible(false)
        setQuestionExplanationVisible(false, animated: false, movesAccessibilityFocus: false)
        questionExplanationLabel.text = nil
        themeNameLabel.text = themeName ?? L10n.Question.fallbackTheme
        questionNumberLabel.text = L10n.Question.unavailableNumber
        questionLabel.text = message
        currentAnswerOptions = []
        timerBar.progress = .zero
        let appearance = currentAppearance()
        setTimerBarColor(quizThemeAccentColor(for: appearance))
        answerButtons.forEach { button in
            button.setTitle(Content.disabledAnswerPlaceholder, for: .normal)
            applyAnswerFeedback(.normal, to: button, appearance: appearance)
            button.isEnabled = false
        }
        layoutContentIfPossible()
        nextButton.isEnabled = false
    }

    func revealQuestionExplanation() {
        guard
            !isQuestionInfoAvailable,
            let explanation = questionExplanationLabel.text,
            !explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        isQuestionInfoAvailable = true
        // Answer feedback already announces the result and explanation in order.
        // Moving VoiceOver focus here would interrupt that announcement.
        setQuestionExplanationVisible(
            true,
            animated: true,
            movesAccessibilityFocus: false
        )
    }

    func setQuestionInfoButtonVisible(_ isVisible: Bool) {
        guard questionInfoButton != nil else { return }

        isQuestionInfoAvailable = isVisible
        applyQuestionExplanationVisibility()
    }
    
    func correctAnswerTapped(isTrue: Bool) {
        currentAnswerWasCorrect = isTrue
        let appearance = currentAppearance()
        if isTrue {
            feedbackPlayer.play(.correct)
            animateTimerBarColor(timerFeedbackColor(isCorrect: true, appearance: appearance))
        } else {
            feedbackPlayer.play(.incorrect)
            animateTimerBarColor(timerFeedbackColor(isCorrect: false, appearance: appearance))
        }
        announceAnswerResult(isCorrect: isTrue)
    }

    // The audio "correct/wrong" cue doesn't carry meaning for users who rely on
    // VoiceOver — post an explicit announcement, and when wrong, tell them which
    // option was correct so they can learn without having to sweep the buttons.
    // The explanation is read automatically afterwards, and only once all of
    // that has actually finished speaking does focus move to Next — moving
    // focus any earlier would cut the explanation off mid-sentence.
    func announceAnswerResult(isCorrect: Bool) {
        guard UIAccessibility.isVoiceOverRunning else {
            answerButtons.forEach { $0.isEnabled = false }
            return
        }
        let announcement: String
        if isCorrect {
            announcement = L10n.Question.answeredCorrect
        } else if let correctTitle = currentCorrectAnswerTitle() {
            announcement = L10n.Question.answeredWrong(correctAnswer: correctTitle)
        } else {
            announcement = L10n.Question.answeredWrongUnknown
        }

        var followUpMessages: [String] = []
        if let explanation = questionExplanationLabel.text?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !explanation.isEmpty {
            followUpMessages.append(explanation)
        }

        VoiceOverAnnouncer.announce([announcement] + followUpMessages) { [weak self] in
            guard let self else { return }
            self.answerButtons.forEach { $0.isEnabled = false }
            UIAccessibility.post(notification: .layoutChanged, argument: self.nextButton)
        }
    }

    private func currentCorrectAnswerTitle() -> String? {
        guard let presenter else { return nil }
        return currentAnswerOptions.first { option in
            presenter.answerFeedback(for: option.id) == .correct
        }?.title
    }

    func applyAnswerFeedback(
        _ state: AnswerFeedbackState,
        to button: UIButton,
        appearance: AppAppearance,
        animated: Bool = false
    ) {
        answerFeedbackStates[ObjectIdentifier(button)] = state
        let changes = answerFeedbackChanges(for: state, appearance: appearance)
        button.setTitleColor(changes.normalTitleColor, for: .normal)
        button.setTitleColor(changes.disabledTitleColor, for: .disabled)

        let animations = {
            button.alpha = changes.alpha
            button.backgroundColor = changes.backgroundColor
            button.layer.borderWidth = changes.borderWidth
            button.layer.borderColor = changes.borderColor.cgColor
        }

        if animated {
            UIView.animate(
                withDuration: AnimationTiming.answerFeedbackDuration,
                delay: 0,
                options: AnimationTiming.answerFeedbackOptions,
                animations: animations
            )
        } else {
            animations()
        }

        if animated, changes.shouldAnimateLegacyBackground {
            animationsEngine.animateBackgroundColor(
                button,
                color: changes.backgroundColor.cgColor,
                duration: AnimationTiming.answerFeedbackDuration
            )
        }
    }

    struct AnswerFeedbackChanges {
        let alpha: CGFloat
        let backgroundColor: UIColor
        let borderWidth: CGFloat
        let borderColor: UIColor
        let normalTitleColor: UIColor
        let disabledTitleColor: UIColor
        let shouldAnimateLegacyBackground: Bool
    }

    func answerFeedbackChanges(for state: AnswerFeedbackState, appearance: AppAppearance) -> AnswerFeedbackChanges {
        var alpha: CGFloat = 1
        var backgroundColor = appearance.answerDefaultColor
        var borderWidth = appearance.row.borderWidth
        var borderColor = appearance.row.borderColor
        let normalTitleColor = appearance.surfaceTextColor
        var disabledTitleColor = appearance.disabledTextColor
        var shouldAnimateLegacyBackground = false

        switch (appearance.designStyle, state) {
        case (_, .normal):
            break

        case (.clean, .correct):
            borderWidth = Appearance.answerFeedbackBorderWidth
            borderColor = appearance.correctAnswerColor
            disabledTitleColor = appearance.surfaceTextColor

        case (.clean, .wrong):
            borderWidth = Appearance.answerFeedbackBorderWidth
            borderColor = appearance.wrongAnswerColor
            disabledTitleColor = appearance.surfaceTextColor

        case (.radar, .correct):
            borderWidth = Appearance.answerFeedbackBorderWidth
            borderColor = appearance.accentColor
            disabledTitleColor = appearance.surfaceTextColor

        case (.radar, .wrong):
            borderColor = appearance.disabledTextColor
            disabledTitleColor = appearance.disabledTextColor
            alpha = Appearance.radarDimmedAnswerAlpha

        case (_, .correct):
            backgroundColor = appearance.correctAnswerColor
            disabledTitleColor = appearance.surfaceTextColor
            shouldAnimateLegacyBackground = true

        case (_, .wrong):
            backgroundColor = appearance.wrongAnswerColor
            shouldAnimateLegacyBackground = true
        }

        return AnswerFeedbackChanges(
            alpha: alpha,
            backgroundColor: backgroundColor,
            borderWidth: borderWidth,
            borderColor: borderColor,
            normalTitleColor: normalTitleColor,
            disabledTitleColor: disabledTitleColor,
            shouldAnimateLegacyBackground: shouldAnimateLegacyBackground
        )
    }

    func timerFeedbackColor(isCorrect: Bool, appearance: AppAppearance) -> UIColor {
        switch appearance.designStyle {
        case .radar:
            return isCorrect ? appearance.accentColor : appearance.disabledTextColor
        default:
            return isCorrect ? appearance.correctAnswerColor : appearance.wrongAnswerColor
        }
    }

    func setTimerBarColor(_ color: UIColor) {
        timerBar.progressTintColor = color
        timerBar.tintColor = color
    }

    func animateTimerBarColor(_ color: UIColor) {
        UIView.transition(
            with: timerBar,
            duration: AnimationTiming.answerFeedbackDuration,
            options: [.transitionCrossDissolve, .allowUserInteraction],
            animations: {
                self.setTimerBarColor(color)
            }
        )
    }
}
