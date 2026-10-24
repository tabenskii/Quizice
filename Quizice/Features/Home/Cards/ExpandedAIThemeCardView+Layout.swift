import UIKit

extension ExpandedAIThemeCardView {
    func configureHierarchy() {
        backgroundColor = .clear
        accessibilityIdentifier = AccessibilityID.root
        accessibilityViewIsModal = true
        isAccessibilityElement = false
        clipsToBounds = false

        perspectiveStageView.translatesAutoresizingMaskIntoConstraints = false
        perspectiveStageView.clipsToBounds = false
        addSubview(perspectiveStageView)

        shadowProxyView.translatesAutoresizingMaskIntoConstraints = false
        shadowProxyView.backgroundColor = .clear
        shadowProxyView.layer.masksToBounds = false
        perspectiveStageView.addSubview(shadowProxyView)

        rotatingCardView.translatesAutoresizingMaskIntoConstraints = false
        rotatingCardView.backgroundColor = .clear
        rotatingCardView.layer.masksToBounds = false
        perspectiveStageView.addSubview(rotatingCardView)

        configurePlane(
            frontPlaneView,
            surfaceView: frontSurfaceView,
            faceView: frontFaceView,
            outlineView: frontOutlineView,
            accessibilityIdentifier: AccessibilityID.front
        )
        configurePlane(
            backPlaneView,
            surfaceView: backSurfaceView,
            faceView: backFaceView,
            outlineView: backOutlineView,
            accessibilityIdentifier: AccessibilityID.back
        )

        flipInteractionButton.isHidden = true
        flipInteractionButton.isAccessibilityElement = false
        flipInteractionButton.backgroundColor = .clear
        flipInteractionButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(flipInteractionButton)

        NSLayoutConstraint.activate([
            perspectiveStageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            perspectiveStageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            perspectiveStageView.topAnchor.constraint(equalTo: topAnchor),
            perspectiveStageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            shadowProxyView.leadingAnchor.constraint(equalTo: perspectiveStageView.leadingAnchor),
            shadowProxyView.trailingAnchor.constraint(equalTo: perspectiveStageView.trailingAnchor),
            shadowProxyView.topAnchor.constraint(equalTo: perspectiveStageView.topAnchor),
            shadowProxyView.bottomAnchor.constraint(equalTo: perspectiveStageView.bottomAnchor),

            rotatingCardView.leadingAnchor.constraint(equalTo: perspectiveStageView.leadingAnchor),
            rotatingCardView.trailingAnchor.constraint(equalTo: perspectiveStageView.trailingAnchor),
            rotatingCardView.topAnchor.constraint(equalTo: perspectiveStageView.topAnchor),
            rotatingCardView.bottomAnchor.constraint(equalTo: perspectiveStageView.bottomAnchor),

            flipInteractionButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            flipInteractionButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            flipInteractionButton.topAnchor.constraint(equalTo: topAnchor),
            flipInteractionButton.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        configureFrontFace()
        configureBackFace()
    }

    func configurePlane(
        _ planeView: UIView,
        surfaceView: UIView,
        faceView: UIView,
        outlineView: UIView,
        accessibilityIdentifier: String
    ) {
        planeView.translatesAutoresizingMaskIntoConstraints = false
        planeView.backgroundColor = .clear
        planeView.layer.isDoubleSided = false
        rotatingCardView.addSubview(planeView)

        surfaceView.translatesAutoresizingMaskIntoConstraints = false
        surfaceView.layer.masksToBounds = true
        planeView.addSubview(surfaceView)

        faceView.accessibilityIdentifier = accessibilityIdentifier
        faceView.translatesAutoresizingMaskIntoConstraints = false
        faceView.backgroundColor = .clear
        surfaceView.addSubview(faceView)

        outlineView.translatesAutoresizingMaskIntoConstraints = false
        surfaceView.addSubview(outlineView)

        NSLayoutConstraint.activate([
            planeView.leadingAnchor.constraint(equalTo: rotatingCardView.leadingAnchor),
            planeView.trailingAnchor.constraint(equalTo: rotatingCardView.trailingAnchor),
            planeView.topAnchor.constraint(equalTo: rotatingCardView.topAnchor),
            planeView.bottomAnchor.constraint(equalTo: rotatingCardView.bottomAnchor),

            surfaceView.leadingAnchor.constraint(equalTo: planeView.leadingAnchor),
            surfaceView.trailingAnchor.constraint(equalTo: planeView.trailingAnchor),
            surfaceView.topAnchor.constraint(equalTo: planeView.topAnchor),
            surfaceView.bottomAnchor.constraint(equalTo: planeView.bottomAnchor),

            faceView.leadingAnchor.constraint(equalTo: surfaceView.leadingAnchor),
            faceView.trailingAnchor.constraint(equalTo: surfaceView.trailingAnchor),
            faceView.topAnchor.constraint(equalTo: surfaceView.topAnchor),
            faceView.bottomAnchor.constraint(equalTo: surfaceView.bottomAnchor),

            outlineView.leadingAnchor.constraint(equalTo: surfaceView.leadingAnchor),
            outlineView.trailingAnchor.constraint(equalTo: surfaceView.trailingAnchor),
            outlineView.topAnchor.constraint(equalTo: surfaceView.topAnchor),
            outlineView.bottomAnchor.constraint(equalTo: surfaceView.bottomAnchor)
        ])
    }

    func configureFrontFace() {
        configureLabel(frontTitleLabel, numberOfLines: 2)
        frontTitleLabel.text = L10n.AITheme.title
        configureLabel(frontSubtitleLabel, numberOfLines: 0)
        frontSubtitleLabel.text = L10n.AITheme.subtitle

        frontHeaderTextStack.axis = .vertical
        frontHeaderTextStack.spacing = Layout.titleSpacing
        frontHeaderTextStack.addArrangedSubview(frontTitleLabel)
        frontHeaderTextStack.addArrangedSubview(frontSubtitleLabel)

        frontHeaderControlSpacer.translatesAutoresizingMaskIntoConstraints = false
        frontHeaderControlSpacer.widthAnchor.constraint(
            equalToConstant: Layout.controlReservation
        ).isActive = true
        frontHeaderStack.axis = .horizontal
        frontHeaderStack.alignment = .top
        frontHeaderStack.addArrangedSubview(frontHeaderTextStack)
        frontHeaderStack.addArrangedSubview(frontHeaderControlSpacer)

        promptContainerView.translatesAutoresizingMaskIntoConstraints = false
        promptContainerView.heightAnchor.constraint(
            greaterThanOrEqualToConstant: Layout.promptMinimumHeight
        ).isActive = true

        promptTextView.accessibilityIdentifier = AccessibilityID.promptEditor
        promptTextView.accessibilityLabel = L10n.AITheme.title
        promptTextView.accessibilityHint = L10n.AITheme.subtitle
        promptTextView.adjustsFontForContentSizeCategory = true
        promptTextView.backgroundColor = .clear
        // The card owns vertical scrolling. A second scroll owner in the editor
        // creates a dead nested-scroll region on compact devices.
        promptTextView.isScrollEnabled = false
        promptTextView.textContainerInset = UIEdgeInsets(
            top: Layout.promptTextInset,
            left: Layout.promptTextInset,
            bottom: Layout.promptTextInset,
            right: Layout.promptTextInset
        )
        promptTextView.delegate = self
        promptTextView.translatesAutoresizingMaskIntoConstraints = false

        promptPlaceholderLabel.text = L10n.AITheme.promptPlaceholder
        promptPlaceholderLabel.adjustsFontForContentSizeCategory = true
        promptPlaceholderLabel.numberOfLines = 0
        promptPlaceholderLabel.isAccessibilityElement = false
        promptPlaceholderLabel.isUserInteractionEnabled = false
        promptPlaceholderLabel.translatesAutoresizingMaskIntoConstraints = false

        promptValidationLabel.accessibilityIdentifier = AccessibilityID.promptValidation
        promptValidationLabel.adjustsFontForContentSizeCategory = true
        promptValidationLabel.numberOfLines = 2
        promptValidationLabel.lineBreakMode = .byWordWrapping
        promptValidationLabel.isAccessibilityElement = true
        promptValidationLabel.isHidden = true
        promptValidationLabel.translatesAutoresizingMaskIntoConstraints = false

        promptContainerView.addSubview(promptTextView)
        promptContainerView.addSubview(promptPlaceholderLabel)
        NSLayoutConstraint.activate([
            promptTextView.leadingAnchor.constraint(equalTo: promptContainerView.leadingAnchor),
            promptTextView.trailingAnchor.constraint(equalTo: promptContainerView.trailingAnchor),
            promptTextView.topAnchor.constraint(equalTo: promptContainerView.topAnchor),
            promptTextView.bottomAnchor.constraint(equalTo: promptContainerView.bottomAnchor),

            promptPlaceholderLabel.leadingAnchor.constraint(
                equalTo: promptContainerView.leadingAnchor,
                constant: Layout.promptTextInset + 5
            ),
            promptPlaceholderLabel.trailingAnchor.constraint(
                equalTo: promptContainerView.trailingAnchor,
                constant: -(Layout.promptTextInset + 5)
            ),
            promptPlaceholderLabel.topAnchor.constraint(
                equalTo: promptTextView.topAnchor,
                constant: Layout.promptTextInset
            )
        ])

        frontContentStack.axis = .vertical
        frontContentStack.spacing = Layout.sectionSpacing
        frontContentStack.translatesAutoresizingMaskIntoConstraints = false
        frontContentStack.addArrangedSubview(frontHeaderStack)
        frontContentStack.addArrangedSubview(promptContainerView)
        frontContentStack.addArrangedSubview(promptValidationLabel)
        configureServiceNoticeLabel(
            frontServiceNoticeLabel,
            accessibilityIdentifier: AccessibilityID.frontServiceNotice
        )
        frontContentStack.addArrangedSubview(frontServiceNoticeLabel)

        configureScrollView(frontScrollView)
        frontScrollView.contentInset.bottom = Layout.scrollBottomInset
        frontScrollView.verticalScrollIndicatorInsets.bottom = Layout.scrollBottomInset
        frontScrollView.addSubview(frontContentStack)

        configureIconButton(
            closeButton,
            systemImageName: "xmark",
            accessibilityIdentifier: AccessibilityID.closeButton,
            accessibilityLabel: L10n.ThemeCard.closeAccessibilityLabel
        )
        configureIconButton(
            playButton,
            systemImageName: "play.fill",
            accessibilityIdentifier: AccessibilityID.playButton,
            accessibilityLabel: L10n.ThemeCard.showDescriptionAccessibilityLabel
        )

        frontFaceView.addSubview(frontScrollView)
        frontFaceView.addSubview(closeButton)
        frontFaceView.addSubview(playButton)
        NSLayoutConstraint.activate([
            frontScrollView.leadingAnchor.constraint(equalTo: frontFaceView.leadingAnchor),
            frontScrollView.trailingAnchor.constraint(equalTo: frontFaceView.trailingAnchor),
            frontScrollView.topAnchor.constraint(equalTo: frontFaceView.topAnchor),
            frontScrollView.bottomAnchor.constraint(equalTo: frontFaceView.bottomAnchor),

            frontContentStack.leadingAnchor.constraint(
                equalTo: frontScrollView.contentLayoutGuide.leadingAnchor,
                constant: Layout.edgeInset
            ),
            frontContentStack.trailingAnchor.constraint(
                equalTo: frontScrollView.contentLayoutGuide.trailingAnchor,
                constant: -Layout.edgeInset
            ),
            frontContentStack.topAnchor.constraint(
                equalTo: frontScrollView.contentLayoutGuide.topAnchor,
                constant: Layout.edgeInset
            ),
            frontContentStack.bottomAnchor.constraint(
                equalTo: frontScrollView.contentLayoutGuide.bottomAnchor,
                constant: -Layout.edgeInset
            ),
            frontContentStack.widthAnchor.constraint(
                equalTo: frontScrollView.frameLayoutGuide.widthAnchor,
                constant: -(Layout.edgeInset * 2)
            ),

            closeButton.topAnchor.constraint(
                equalTo: frontFaceView.topAnchor,
                constant: Layout.controlInset
            ),
            closeButton.trailingAnchor.constraint(
                equalTo: frontFaceView.trailingAnchor,
                constant: -Layout.controlInset
            ),
            closeButton.widthAnchor.constraint(equalToConstant: Layout.iconButtonSize),
            closeButton.heightAnchor.constraint(equalToConstant: Layout.iconButtonSize),

            playButton.trailingAnchor.constraint(
                equalTo: frontFaceView.trailingAnchor,
                constant: -Layout.controlInset
            ),
            playButton.bottomAnchor.constraint(
                equalTo: frontFaceView.bottomAnchor,
                constant: -Layout.controlInset
            ),
            playButton.widthAnchor.constraint(equalToConstant: Layout.iconButtonSize),
            playButton.heightAnchor.constraint(equalToConstant: Layout.iconButtonSize)
        ])

        frontFaceView.accessibilityElements = [
            frontTitleLabel,
            frontSubtitleLabel,
            promptTextView,
            promptValidationLabel,
            frontServiceNoticeLabel,
            playButton,
            closeButton
        ]
    }

    func configureBackFace() {
        configureLabel(backTitleLabel, numberOfLines: 2)
        backTitleLabel.lineBreakMode = .byTruncatingTail
        backTitleLabel.allowsDefaultTighteningForTruncation = true
        configureLabel(questionCountLabel, numberOfLines: 0)
        questionCountLabel.text = L10n.AITheme.questionCount
        configureLabel(difficultyLabel, numberOfLines: 0)
        difficultyLabel.text = L10n.AITheme.difficulty

        backHeaderControlSpacer.translatesAutoresizingMaskIntoConstraints = false
        backHeaderControlSpacer.widthAnchor.constraint(
            equalToConstant: Layout.controlReservation
        ).isActive = true
        backHeaderStack.axis = .horizontal
        backHeaderStack.alignment = .top
        backHeaderStack.addArrangedSubview(backHeaderControlSpacer)
        backHeaderStack.addArrangedSubview(backTitleLabel)

        configureSelectorStack(questionCountStack)
        questionCountStack.accessibilityIdentifier = AccessibilityID.questionCountSelector
        questionCountButtons = Self.supportedQuestionCounts.enumerated().map { index, count in
            let button = makeOptionButton(
                title: String(count),
                accessibilityLabel: L10n.AITheme.questionCountAccessibility(count: count),
                tag: index,
                action: #selector(questionCountTapped(_:))
            )
            questionCountStack.addArrangedSubview(button)
            return button
        }

        configureSelectorStack(difficultyStack)
        difficultyStack.accessibilityIdentifier = AccessibilityID.difficultySelector
        difficultyButtons = Self.supportedDifficulties.enumerated().map { index, difficulty in
            let button = makeOptionButton(
                title: difficulty.title,
                accessibilityLabel: difficulty.title,
                tag: index,
                action: #selector(difficultyTapped(_:))
            )
            difficultyStack.addArrangedSubview(button)
            return button
        }
        updateAdaptiveSelectorLayout()

        submitButton.accessibilityIdentifier = AccessibilityID.submitButton
        submitButton.translatesAutoresizingMaskIntoConstraints = false
        submitButton.heightAnchor.constraint(
            greaterThanOrEqualToConstant: Layout.submitMinimumHeight
        ).isActive = true
        submitButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
        submitButton.installPressFeedback()

        submitActivityIndicator.hidesWhenStopped = true
        submitActivityIndicator.isUserInteractionEnabled = false
        submitTitleLabel.adjustsFontForContentSizeCategory = true
        submitTitleLabel.numberOfLines = 1
        submitTitleLabel.minimumScaleFactor = 0.78
        submitTitleLabel.adjustsFontSizeToFitWidth = true
        submitTitleLabel.isUserInteractionEnabled = false
        submitContentStack.axis = .horizontal
        submitContentStack.alignment = .center
        submitContentStack.spacing = Layout.submitContentSpacing
        submitContentStack.isUserInteractionEnabled = false
        submitContentStack.translatesAutoresizingMaskIntoConstraints = false
        submitContentStack.addArrangedSubview(submitActivityIndicator)
        submitContentStack.addArrangedSubview(submitTitleLabel)
        submitButton.addSubview(submitContentStack)
        NSLayoutConstraint.activate([
            submitContentStack.centerXAnchor.constraint(equalTo: submitButton.centerXAnchor),
            submitContentStack.centerYAnchor.constraint(equalTo: submitButton.centerYAnchor),
            submitContentStack.leadingAnchor.constraint(
                greaterThanOrEqualTo: submitButton.leadingAnchor,
                constant: Layout.edgeInset
            ),
            submitContentStack.trailingAnchor.constraint(
                lessThanOrEqualTo: submitButton.trailingAnchor,
                constant: -Layout.edgeInset
            )
        ])

        progressLabel.accessibilityIdentifier = AccessibilityID.progressStatus
        progressLabel.accessibilityTraits.insert(.updatesFrequently)
        progressLabel.adjustsFontForContentSizeCategory = true
        progressLabel.numberOfLines = 0
        progressLabel.textAlignment = .center
        progressLabel.isHidden = true
        configureServiceNoticeLabel(
            backServiceNoticeLabel,
            accessibilityIdentifier: AccessibilityID.backServiceNotice
        )

        backContentStack.axis = .vertical
        backContentStack.spacing = Layout.sectionSpacing
        backContentStack.translatesAutoresizingMaskIntoConstraints = false
        [
            backHeaderStack,
            questionCountLabel,
            questionCountStack,
            difficultyLabel,
            difficultyStack,
            submitButton,
            progressLabel,
            backServiceNoticeLabel
        ].forEach(backContentStack.addArrangedSubview)
        backContentStack.setCustomSpacing(Layout.selectorSpacing, after: questionCountLabel)
        backContentStack.setCustomSpacing(Layout.selectorSpacing, after: difficultyLabel)

        configureScrollView(backScrollView)
        backScrollView.addSubview(backContentStack)

        configureIconButton(
            backButton,
            systemImageName: "chevron.left",
            accessibilityIdentifier: AccessibilityID.backButton,
            accessibilityLabel: L10n.ThemeCard.showFrontAccessibilityLabel
        )

        backFaceView.addSubview(backScrollView)
        backFaceView.addSubview(backButton)
        NSLayoutConstraint.activate([
            backScrollView.leadingAnchor.constraint(equalTo: backFaceView.leadingAnchor),
            backScrollView.trailingAnchor.constraint(equalTo: backFaceView.trailingAnchor),
            backScrollView.topAnchor.constraint(equalTo: backFaceView.topAnchor),
            backScrollView.bottomAnchor.constraint(equalTo: backFaceView.bottomAnchor),

            backContentStack.leadingAnchor.constraint(
                equalTo: backScrollView.contentLayoutGuide.leadingAnchor,
                constant: Layout.edgeInset
            ),
            backContentStack.trailingAnchor.constraint(
                equalTo: backScrollView.contentLayoutGuide.trailingAnchor,
                constant: -Layout.edgeInset
            ),
            backContentStack.topAnchor.constraint(
                equalTo: backScrollView.contentLayoutGuide.topAnchor,
                constant: Layout.edgeInset
            ),
            backContentStack.bottomAnchor.constraint(
                equalTo: backScrollView.contentLayoutGuide.bottomAnchor,
                constant: -Layout.edgeInset
            ),
            backContentStack.widthAnchor.constraint(
                equalTo: backScrollView.frameLayoutGuide.widthAnchor,
                constant: -(Layout.edgeInset * 2)
            ),

            backButton.topAnchor.constraint(
                equalTo: backFaceView.topAnchor,
                constant: Layout.controlInset
            ),
            backButton.leadingAnchor.constraint(
                equalTo: backFaceView.leadingAnchor,
                constant: Layout.controlInset
            ),
            backButton.widthAnchor.constraint(equalToConstant: Layout.iconButtonSize),
            backButton.heightAnchor.constraint(equalToConstant: Layout.iconButtonSize)
        ])

        var backAccessibilityElements: [Any] = [backTitleLabel, questionCountLabel]
        backAccessibilityElements.append(contentsOf: questionCountButtons)
        backAccessibilityElements.append(difficultyLabel)
        backAccessibilityElements.append(contentsOf: difficultyButtons)
        backAccessibilityElements.append(contentsOf: [
            submitButton,
            progressLabel,
            backServiceNoticeLabel,
            backButton
        ])
        backFaceView.accessibilityElements = backAccessibilityElements
    }

    func configureScrollView(_ scrollView: UIScrollView) {
        scrollView.alwaysBounceVertical = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false
    }

    func configureLabel(_ label: UILabel, numberOfLines: Int) {
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = numberOfLines
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
    }

    func configureServiceNoticeLabel(_ label: UILabel, accessibilityIdentifier: String) {
        configureLabel(label, numberOfLines: 0)
        label.accessibilityIdentifier = accessibilityIdentifier
        label.isAccessibilityElement = true
        label.accessibilityElementsHidden = true
        label.isHidden = true
    }

    func configureSelectorStack(_ stackView: UIStackView) {
        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.distribution = .fillEqually
        stackView.spacing = Layout.selectorSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.heightAnchor.constraint(
            greaterThanOrEqualToConstant: Layout.selectorButtonHeight
        ).isActive = true
    }

    func makeOptionButton(
        title: String,
        accessibilityLabel: String,
        tag: Int,
        action: Selector
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.tag = tag
        button.setTitle(title, for: .normal)
        button.accessibilityLabel = accessibilityLabel
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.72
        button.titleLabel?.numberOfLines = 1
        button.heightAnchor.constraint(
            greaterThanOrEqualToConstant: Layout.selectorButtonHeight
        ).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
        button.installPressFeedback()
        return button
    }

    func configureIconButton(
        _ button: UIButton,
        systemImageName: String,
        accessibilityIdentifier: String,
        accessibilityLabel: String?
    ) {
        button.accessibilityIdentifier = accessibilityIdentifier
        button.accessibilityLabel = accessibilityLabel
        button.setImage(
            UIImage(
                systemName: systemImageName,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
            ),
            for: .normal
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        button.installPressFeedback()
    }

    func configureActions() {
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        playButton.addTarget(self, action: #selector(flipTapped), for: .touchUpInside)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        flipInteractionButton.addTarget(
            self,
            action: #selector(flipInteractionTapped),
            for: .touchUpInside
        )
    }

}
