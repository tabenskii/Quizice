import UIKit

extension ExpandedThemeCardView {
    func applyAppearance(
        _ appearance: AppAppearance,
        themeID: String,
        themeTintColor: UIColor,
        borderColor: UIColor
    ) {
        overrideUserInterfaceStyle = appearance.resolvedInterfaceStyle
        cardCornerRadius = appearance.themeCardCornerRadius

        configuredSurfaceColor = appearance.themeCardBackground(baseColor: themeTintColor)
        configuredBorderColor = borderColor
        configuredBorderWidth = appearance.themeCardBorderWidth
        applyConfiguredSurfaceAppearance()
        configuredShadowStyle = appearance.card.shadow
        let shadow = isTransitionShadowHidden ? AppShadowStyle.none : configuredShadowStyle
        shadowProxyView.applyShadow(shadow)

        frontTitleLabel.font = appearance.typography.font(
            size: Typography.frontTitleSize,
            weight: .bold
        )
        frontTitleLabel.textColor = appearance.themeCardTextColor(baseColor: themeTintColor)

        backTitleLabel.font = appearance.typography.font(
            size: Typography.backTitleSize,
            weight: .bold
        )
        backTitleLabel.textColor = appearance.surfaceTextColor
        backDescriptionLabel.font = appearance.typography.font(
            size: Typography.descriptionSize,
            weight: .regular
        )
        backDescriptionLabel.textColor = appearance.secondarySurfaceTextColor
        [difficultyLabel, questionCountLabel].forEach { label in
            label.font = appearance.typography.font(
                size: Typography.captionSize,
                weight: .semibold
            )
            label.textColor = appearance.secondarySurfaceTextColor
        }
        let countryFont = appearance.typography.font(
            size: Typography.captionSize, weight: .semibold
        )
        // Let UIButton own the background throughout its menu transition.
        // iOS 26 temporarily resets a legacy layer-styled menu button's surface.
        var countryConfiguration = UIButton.Configuration.plain()
        countryConfiguration.contentInsets = .zero
        countryConfiguration.cornerStyle = .fixed
        countryConfiguration.baseForegroundColor = appearance.surfaceTextColor
        countryConfiguration.background.backgroundColor = appearance.row.backgroundColor
        countryConfiguration.background.cornerRadius = appearance.row.cornerRadius
        countryConfiguration.background.strokeWidth = appearance.row.borderWidth
        countryConfiguration.background.strokeColor = appearance.row.borderColor
        countryConfiguration.titleLineBreakMode = .byWordWrapping
        countryConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = countryFont
            return attributes
        }
        countryButton.configuration = countryConfiguration
        var subtopicConfiguration = countryConfiguration
        subtopicConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        subtopicButton.configuration = subtopicConfiguration
        unavailableLabel.font = appearance.typography.font(
            size: Typography.unavailableSize,
            weight: .medium
        )
        unavailableLabel.textColor = appearance.destructiveColor

        [closeButton, infoButton, backButton].forEach { button in
            button.applyActionAppearance(
                appearance.iconButton,
                appearance: appearance,
                textColor: appearance.themeCardTextColor(baseColor: themeTintColor)
            )
        }

        let primaryButtonStyle = QuizThemeAccentStyle.primaryButtonStyle(
            themeID: themeID,
            appearance: appearance
        )
        startButton.titleLabel?.font = appearance.typography.font(
            size: Typography.buttonSize,
            weight: .semibold
        )
        startButton.applyActionAppearance(
            primaryButtonStyle,
            appearance: appearance,
            textColor: QuizThemeAccentStyle.primaryButtonTextColor(
                themeID: themeID,
                appearance: appearance
            )
        )
        startActivityIndicator.color = QuizThemeAccentStyle.primaryButtonTextColor(
            themeID: themeID,
            appearance: appearance
        )

        let segmentFont = appearance.typography.font(
            size: Typography.segmentSize,
            weight: .semibold
        )
        [difficultyControl, questionCountControl].forEach { control in
            control.backgroundColor = appearance.row.backgroundColor
            control.selectedSegmentTintColor = primaryButtonStyle.backgroundColor
            control.layer.cornerRadius = appearance.row.cornerRadius
            control.layer.borderWidth = appearance.row.borderWidth
            control.layer.borderColor = appearance.row.borderColor.cgColor
            control.setTitleTextAttributes(
                [
                    .font: segmentFont,
                    .foregroundColor: appearance.surfaceTextColor
                ],
                for: .normal
            )
            control.setTitleTextAttributes(
                [
                    .font: segmentFont,
                    .foregroundColor: QuizThemeAccentStyle.primaryButtonTextColor(
                        themeID: themeID,
                        appearance: appearance
                    )
                ],
                for: .selected
            )
            control.setTitleTextAttributes(
                [
                    .font: segmentFont,
                    .foregroundColor: appearance.disabledTextColor
                ],
                for: .disabled
            )
        }
    }

    func applyConfiguredSurfaceAppearance() {
        let surfaceColor = isTransitionSurfaceHidden ? UIColor.clear : configuredSurfaceColor
        let borderColor = isTransitionSurfaceHidden ? UIColor.clear : configuredBorderColor
        let borderWidth = isTransitionSurfaceHidden ? CGFloat.zero : configuredBorderWidth

        [frontSurfaceView, backSurfaceView].forEach { surfaceView in
            surfaceView.backgroundColor = surfaceColor
            surfaceView.layer.cornerRadius = cardCornerRadius
            surfaceView.layer.cornerCurve = .continuous
            surfaceView.layer.borderWidth = borderWidth
            surfaceView.layer.borderColor = borderColor.cgColor
        }
        frontFaceView.backgroundColor = surfaceColor
        backFaceView.backgroundColor = surfaceColor
    }

    func configureCountries(theme: QuizTheme, selectedCountry: String?) {
        availableCountries = theme.stableID == "politics_business" ? theme.countries : []
        countryButton.isHidden = availableCountries.isEmpty
        self.selectedCountry = selectedCountry.flatMap { availableCountries.contains($0) ? $0 : nil }
        updateCountryMenu()
    }

    func selectCountry(_ country: String?) {
        guard !isStartLoading, country.map(availableCountries.contains) ?? true else { return }
        guard selectedCountry != country else { return }
        selectedCountry = country
        updateCountryMenu()
        onCountryChanged?(country)
    }

    private func updateCountryMenu() {
        let locale = AppLocalizationStore.shared.resolvedLocale
        let title = selectedCountry.flatMap { locale.localizedString(forRegionCode: $0) }
            ?? L10n.ThemeCard.internationalQuestions
        countryButton.setTitle("\(title) ▾", for: .normal)
        countryButton.accessibilityValue = title
        let codes: [String?] = [nil] + availableCountries.map { Optional($0) }
        countryButton.menu = UIMenu(title: L10n.ThemeCard.country, children: codes.map { code in
            let name = code.map { locale.localizedString(forRegionCode: $0) ?? $0 }
                ?? L10n.ThemeCard.internationalQuestions
            return UIAction(title: name, state: selectedCountry == code ? .on : .off) { [weak self] _ in
                self?.selectCountry(code)
            }
        })
    }

    func configureSubtopics(_ subtopics: [QuizSubtopic], selectedSubtopicID: String?) {
        availableSubtopics = subtopics
        self.selectedSubtopicID = selectedSubtopicID.flatMap { id in
            subtopics.contains { $0.id == id } ? id : nil
        }
        subtopicButton.isHidden = subtopics.isEmpty
        updateSubtopicMenu()
    }

    func selectSubtopic(_ id: String?) {
        guard !isStartLoading, selectedSubtopicID != id,
              id.map({ id in availableSubtopics.contains { $0.id == id } }) ?? true else { return }
        selectedSubtopicID = id
        updateSubtopicMenu()
        onSubtopicChanged?(id)
    }

    private func updateSubtopicMenu() {
        let allTitle = L10n.ThemeCard.allSubtopics
        let title = availableSubtopics.first { $0.id == selectedSubtopicID }?.name ?? allTitle
        subtopicButton.setTitle("\(title) ▾", for: .normal)
        subtopicButton.accessibilityLabel = L10n.ThemeCard.subtopic
        subtopicButton.accessibilityValue = title

        func action(id: String?, title: String) -> UIAction {
            UIAction(title: title, state: selectedSubtopicID == id ? .on : .off) { [weak self] _ in
                self?.selectSubtopic(id)
            }
        }
        let actions = [action(id: nil, title: allTitle)] + availableSubtopics.map { action(id: $0.id, title: $0.name) }
        subtopicButton.menu = UIMenu(title: L10n.ThemeCard.subtopic, children: actions)
    }

    func configureQuestionCounts(selectedQuestionCount: Int?) {
        for (index, count) in Self.supportedQuestionCounts.enumerated() {
            questionCountControl.setEnabled(
                availableQuestionCounts.contains(count),
                forSegmentAt: index
            )
        }

        let resolvedSelection = selectedQuestionCount.flatMap { selection in
            availableQuestionCounts.contains(selection) ? selection : nil
        }
            ?? Self.supportedQuestionCounts.first(where: availableQuestionCounts.contains)

        self.selectedQuestionCount = resolvedSelection
        if let resolvedSelection,
           let index = Self.supportedQuestionCounts.firstIndex(of: resolvedSelection) {
            questionCountControl.selectedSegmentIndex = index
        } else {
            questionCountControl.selectedSegmentIndex = UISegmentedControl.noSegment
        }

        let isAvailable = resolvedSelection != nil
        unavailableLabel.isHidden = isAvailable
        unavailableLabel.accessibilityElementsHidden = isAvailable
        startButton.isEnabled = isAvailable && !isStartLoading
        startButton.accessibilityHint = isAvailable ? nil : L10n.Question.unavailableMessage
        updateBackFaceAccessibilityElements(isAvailable: isAvailable)
    }

    func updateBackFaceAccessibilityElements(isAvailable: Bool) {
        var elements: [Any] = [backTitleLabel, backDescriptionLabel]
        if !countryButton.isHidden {
            elements.append(countryButton)
        }
        if !subtopicButton.isHidden {
            elements.append(subtopicButton)
        }
        if !difficultyControl.isHidden {
            elements.append(contentsOf: [difficultyLabel, difficultyControl])
        }
        elements.append(contentsOf: [questionCountLabel, questionCountControl])
        if !isAvailable {
            elements.append(unavailableLabel)
        }
        elements.append(startButton)
        elements.append(backButton)
        backFaceView.accessibilityElements = elements
    }

    func configureDifficulty(_ difficulty: AIQuizDifficulty, isAvailable: Bool) {
        [difficultyLabel, difficultyControl].forEach {
            $0.isHidden = !isAvailable
            $0.accessibilityElementsHidden = !isAvailable
        }
        difficultyControl.isEnabled = isAvailable
        selectedDifficulty = difficulty
        difficultyControl.selectedSegmentIndex =
            AIQuizDifficulty.allCases.firstIndex(of: difficulty) ?? 1
    }

    func setStartLoading(_ isLoading: Bool) {
        isStartLoading = isLoading
        countryButton.isEnabled = !isLoading
        subtopicButton.isEnabled = !isLoading
        startButton.isEnabled = !isLoading && selectedQuestionCount != nil
        startButton.setTitle(isLoading ? nil : L10n.Common.start, for: .normal)
        startButton.accessibilityLabel = isLoading ? L10n.Home.feelingLuckyLoading : L10n.Common.start
        if isLoading {
            startButton.accessibilityTraits.insert(.updatesFrequently)
            startActivityIndicator.startAnimating()
        } else {
            startButton.accessibilityTraits.remove(.updatesFrequently)
            startActivityIndicator.stopAnimating()
        }
    }

    func frontArtworkImage(sfSymbolName: String, appearance: AppAppearance) -> UIImage? {
        guard let image = ThemeVisualCatalog.logoImage(
            sfSymbolName: sfSymbolName
        ) else {
            return nil
        }

        switch appearance.designStyle {
        case .clean:
            let configuration = UIImage.SymbolConfiguration(
                pointSize: Layout.cleanFrontArtworkPointSize,
                weight: .regular
            )
            return image.applyingSymbolConfiguration(configuration) ?? image

        case .classic:
            return image

        case .radar:
            return image
        }
    }

    func frontArtworkPointSize(for designStyle: AppDesignStyle) -> CGFloat {
        switch designStyle {
        case .classic:
            return Layout.classicFrontArtworkSize.width
        case .clean:
            return Layout.cleanFrontArtworkPointSize
        case .radar:
            return Layout.radarFrontArtworkPointSize
        }
    }

}
