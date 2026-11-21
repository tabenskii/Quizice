import UIKit

extension ExpandedAIThemeCardView {
    var transitionSurfaceColor: UIColor {
        guard let configuredSurfaceStyle else { return .clear }
        return configuredAppearance?.designStyle == .radar
            ? configuredSurfaceStyle.backgroundColor.withAlphaComponent(1)
            : configuredSurfaceStyle.backgroundColor
    }

    func applyAppearance(_ appearance: AppAppearance) {
        let expandedSurfaceStyle = makeExpandedSurfaceStyle(appearance)
        configuredSurfaceStyle = expandedSurfaceStyle
        cardCornerRadius = expandedSurfaceStyle.cornerRadius
        configuredShadowStyle = appearance.designStyle == .radar
            ? AppShadowStyle(
                color: appearance.accentColor,
                opacity: Outline.radarGlowOpacity,
                radius: Outline.radarGlowRadius,
                offset: .zero
            )
            : appearance.card.shadow
        applyConfiguredSurfaceAppearance()
        applyConfiguredShadow()

        frontTitleLabel.font = appearance.typography.font(
            size: Typography.titleSize,
            weight: .bold
        )
        frontTitleLabel.textColor = appearance.surfaceTextColor
        frontSubtitleLabel.font = appearance.typography.font(
            size: Typography.subtitleSize,
            weight: .regular
        )
        frontSubtitleLabel.textColor = appearance.secondarySurfaceTextColor

        promptTextView.font = appearance.typography.font(
            size: Typography.promptSize,
            weight: .regular
        )
        promptTextView.textColor = appearance.surfaceTextColor
        promptTextView.tintColor = appearance.accentColor
        promptPlaceholderLabel.font = appearance.typography.font(
            size: Typography.promptSize,
            weight: .regular
        )
        promptPlaceholderLabel.textColor = appearance.secondarySurfaceTextColor
        promptValidationLabel.font = appearance.typography.font(
            size: Typography.progressSize,
            weight: .medium
        )
        promptValidationLabel.textColor = appearance.destructiveColor
        promptContainerView.applySurfaceStyle(appearance.row)

        backTitleLabel.font = appearance.typography.font(
            size: Typography.titleSize,
            weight: .bold
        )
        backTitleLabel.textColor = appearance.surfaceTextColor
        [questionCountLabel, difficultyLabel].forEach { label in
            label.font = appearance.typography.font(
                size: Typography.sectionTitleSize,
                weight: .semibold
            )
            label.textColor = appearance.surfaceTextColor
        }
        submitTitleLabel.font = appearance.typography.font(
            size: Typography.submitSize,
            weight: .semibold
        )
        progressLabel.font = appearance.typography.font(
            size: Typography.progressSize,
            weight: .medium
        )
        progressLabel.textColor = appearance.secondarySurfaceTextColor
        [frontServiceNoticeLabel, backServiceNoticeLabel].forEach { label in
            label.font = appearance.typography.font(
                size: Typography.serviceNoticeSize,
                weight: .regular,
                compatibleWith: traitCollection
            )
            label.textColor = appearance.secondarySurfaceTextColor
        }

        [closeButton, playButton, backButton].forEach { button in
            button.applyActionAppearance(
                appearance.iconButton,
                appearance: appearance,
                textColor: appearance.surfaceTextColor
            )
        }
        submitButton.applyActionAppearance(
            appearance.primaryButton,
            appearance: appearance,
            textColor: appearance.accentForegroundColor
        )
        submitTitleLabel.textColor = appearance.accentForegroundColor
        submitActivityIndicator.color = appearance.accentForegroundColor

        let keyboardStyle = AIThemeKeyboardStyle(appearance: appearance)
        promptTextView.inputAccessoryView?.tintColor = keyboardStyle.doneButtonTintColor
        promptTextView.inputAccessoryView?.overrideUserInterfaceStyle = keyboardStyle.interfaceStyle
        switch keyboardStyle.interfaceStyle {
        case .dark:
            promptTextView.keyboardAppearance = .dark
        case .light:
            promptTextView.keyboardAppearance = .light
        default:
            promptTextView.keyboardAppearance = .default
        }
    }

    private func makeExpandedSurfaceStyle(
        _ appearance: AppAppearance
    ) -> AppSurfaceStyle {
        switch appearance.designStyle {
        case .clean:
            return appearance.card

        case .radar:
            return appearance.dialogSurface

        case .classic:
            return AppSurfaceStyle(
                backgroundColor: appearance.row.backgroundColor
                    .opaqueComposited(over: appearance.backgroundColor),
                borderColor: appearance.card.borderColor,
                borderWidth: appearance.card.borderWidth,
                cornerRadius: appearance.card.cornerRadius,
                shadow: appearance.card.shadow
            )
        }
    }

    func applyConfiguredSurfaceAppearance() {
        guard let style = configuredSurfaceStyle else { return }
        let isRadar = configuredAppearance?.designStyle == .radar
        let surfaceColor: UIColor
        if isTransitionSurfaceHidden {
            surfaceColor = .clear
        } else if isRadar {
            surfaceColor = style.backgroundColor.withAlphaComponent(1)
        } else {
            surfaceColor = style.backgroundColor
        }
        let solidBorderColor: UIColor
        let solidBorderWidth: CGFloat
        if isTransitionSurfaceHidden {
            solidBorderColor = .clear
            solidBorderWidth = 0
        } else if isRadar {
            solidBorderColor = configuredAppearance?.accentColor ?? style.borderColor
            solidBorderWidth = max(style.borderWidth, 1)
        } else {
            solidBorderColor = .clear
            solidBorderWidth = 0
        }

        [frontSurfaceView, backSurfaceView].forEach { surfaceView in
            surfaceView.backgroundColor = surfaceColor
            surfaceView.layer.cornerRadius = cardCornerRadius
            surfaceView.layer.cornerCurve = .continuous
            surfaceView.layer.borderColor = solidBorderColor.cgColor
            surfaceView.layer.borderWidth = solidBorderWidth
        }

        let usesGradient = !isRadar && !isTransitionSurfaceHidden
        [frontOutlineView, backOutlineView].forEach { outlineView in
            outlineView.colors = AIThemeVisualStyle.gradientColors
            outlineView.lineWidth = Outline.gradientLineWidth
            outlineView.cornerRadius = cardCornerRadius
            outlineView.isHidden = !usesGradient
        }
        setNeedsLayout()
    }

    func applyConfiguredShadow() {
        shadowProxyView.applyShadow(
            isTransitionShadowHidden ? .none : configuredShadowStyle
        )
    }

    func renderControls() {
        guard let appearance = configuredAppearance else { return }

        promptTextView.isEditable = !isSubmitting
        promptTextView.alpha = isSubmitting ? 0.52 : 1
        playButton.isEnabled = canRevealConfiguration
        playButton.alpha = canRevealConfiguration ? 1 : 0.52
        playButton.accessibilityHint = canRevealConfiguration ? nil : L10n.AITheme.subtitle

        for (index, button) in questionCountButtons.enumerated() {
            guard Self.supportedQuestionCounts.indices.contains(index) else { continue }
            styleOptionButton(
                button,
                isSelected: Self.supportedQuestionCounts[index] == selectedQuestionCount,
                isEnabled: !isSubmitting,
                appearance: appearance
            )
        }
        for (index, button) in difficultyButtons.enumerated() {
            guard Self.supportedDifficulties.indices.contains(index) else { continue }
            styleOptionButton(
                button,
                isSelected: Self.supportedDifficulties[index] == selectedDifficulty,
                isEnabled: !isSubmitting,
                appearance: appearance
            )
        }

        submitButton.isEnabled = canSubmit
        submitButton.alpha = submitButton.isEnabled || isSubmitting ? 1 : 0.52
        submitTitleLabel.text = isSubmitting ? L10n.AITheme.generating : L10n.AITheme.submit
        submitButton.accessibilityLabel = submitTitleLabel.text
        if isSubmitting {
            submitActivityIndicator.startAnimating()
        } else {
            submitActivityIndicator.stopAnimating()
        }
    }

    func styleOptionButton(
        _ button: UIButton,
        isSelected: Bool,
        isEnabled: Bool,
        appearance: AppAppearance
    ) {
        let style = isSelected ? appearance.primaryButton : appearance.row
        let textColor = isSelected
            ? appearance.accentForegroundColor
            : appearance.surfaceTextColor
        button.applyActionAppearance(style, appearance: appearance, textColor: textColor)
        button.titleLabel?.font = appearance.typography.font(
            size: Typography.optionSize,
            weight: .semibold
        )
        button.isEnabled = isEnabled
        button.alpha = isEnabled ? (isSelected ? 1 : 0.78) : 0.52
        if isSelected {
            button.accessibilityTraits.insert(.selected)
        } else {
            button.accessibilityTraits.remove(.selected)
        }
    }

    func updatePromptPlaceholderVisibility() {
        promptPlaceholderLabel.isHidden = !promptTextView.text.isEmpty
    }

    func textViewDidChange(_ textView: UITextView) {
        guard textView === promptTextView else { return }
        textView.invalidateIntrinsicContentSize()
        setNeedsLayout()
        layoutIfNeeded()
        scrollPromptCaretIntoView()
        updatePromptPlaceholderVisibility()
        canRevealConfiguration = !textView.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        let isPromptTooLong = textView.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .count > AIQuizGenerationConfiguration.maximumThemeLength
        promptValidationLabel.text = isPromptTooLong
            ? L10n.AITheme.promptTooLong(maximumLength: AIQuizGenerationConfiguration.maximumThemeLength)
            : nil
        promptValidationLabel.isHidden = !isPromptTooLong
        promptValidationLabel.accessibilityElementsHidden = !isPromptTooLong
        canRevealConfiguration = canRevealConfiguration && !isPromptTooLong
        canSubmit = canRevealConfiguration && !isSubmitting
        renderControls()
        onPromptChanged?(textView.text)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        guard textView === promptTextView else { return }
        scrollPromptCaretIntoView()
    }

    @objc func closeTapped() {
        onClose?()
    }

    @objc func flipTapped() {
        guard canRevealConfiguration else { return }
        resignPrompt()
        onFlip?()
    }

    @objc func flipInteractionTapped() {
        onFlip?()
    }

    @objc func backTapped() {
        onBack?()
    }

    @objc func questionCountTapped(_ sender: UIButton) {
        guard
            !isSubmitting,
            Self.supportedQuestionCounts.indices.contains(sender.tag)
        else { return }
        selectedQuestionCount = Self.supportedQuestionCounts[sender.tag]
        renderControls()
        onQuestionCountChanged?(selectedQuestionCount)
    }

    @objc func difficultyTapped(_ sender: UIButton) {
        guard
            !isSubmitting,
            Self.supportedDifficulties.indices.contains(sender.tag)
        else { return }
        selectedDifficulty = Self.supportedDifficulties[sender.tag]
        renderControls()
        onDifficultyChanged?(selectedDifficulty)
    }

    @objc func submitTapped() {
        guard submitButton.isEnabled, !isSubmitting else { return }
        onSubmit?()
    }

}

private extension UIColor {
    func opaqueComposited(over backgroundColor: UIColor) -> UIColor {
        var foregroundRed: CGFloat = 0
        var foregroundGreen: CGFloat = 0
        var foregroundBlue: CGFloat = 0
        var foregroundAlpha: CGFloat = 0
        var backgroundRed: CGFloat = 0
        var backgroundGreen: CGFloat = 0
        var backgroundBlue: CGFloat = 0
        var backgroundAlpha: CGFloat = 0

        guard
            getRed(
                &foregroundRed,
                green: &foregroundGreen,
                blue: &foregroundBlue,
                alpha: &foregroundAlpha
            ),
            backgroundColor.getRed(
                &backgroundRed,
                green: &backgroundGreen,
                blue: &backgroundBlue,
                alpha: &backgroundAlpha
            )
        else {
            return backgroundColor.withAlphaComponent(1)
        }

        let outputAlpha = foregroundAlpha
            + backgroundAlpha * (1 - foregroundAlpha)
        guard outputAlpha > 0 else { return .clear }

        return UIColor(
            red: (
                foregroundRed * foregroundAlpha
                    + backgroundRed * backgroundAlpha * (1 - foregroundAlpha)
            ) / outputAlpha,
            green: (
                foregroundGreen * foregroundAlpha
                    + backgroundGreen * backgroundAlpha * (1 - foregroundAlpha)
            ) / outputAlpha,
            blue: (
                foregroundBlue * foregroundAlpha
                    + backgroundBlue * backgroundAlpha * (1 - foregroundAlpha)
            ) / outputAlpha,
            alpha: 1
        )
    }
}
