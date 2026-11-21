import UIKit

extension ExpandedThemeCardView {
    func configureViewHierarchy() {
        backgroundColor = .clear
        accessibilityIdentifier = AccessibilityID.root
        accessibilityViewIsModal = true
        isAccessibilityElement = false

        perspectiveStageView.translatesAutoresizingMaskIntoConstraints = false
        perspectiveStageView.clipsToBounds = false
        perspectiveStageView.accessibilityIdentifier = AccessibilityID.parallaxCarrier
        addSubview(perspectiveStageView)

        // A clear one-point probe stores the normalized pose so an interrupted
        // spring can sample its presentation value without moving visible content.
        parallaxPoseProbeView.translatesAutoresizingMaskIntoConstraints = false
        parallaxPoseProbeView.backgroundColor = .clear
        parallaxPoseProbeView.isUserInteractionEnabled = false
        parallaxPoseProbeView.accessibilityElementsHidden = true
        addSubview(parallaxPoseProbeView)

        shadowProxyView.accessibilityIdentifier = AccessibilityID.shadowProxy
        shadowProxyView.translatesAutoresizingMaskIntoConstraints = false
        shadowProxyView.backgroundColor = .clear
        shadowProxyView.layer.masksToBounds = false
        perspectiveStageView.addSubview(shadowProxyView)

        rotatingCardView.accessibilityIdentifier = AccessibilityID.rotatingCarrier
        rotatingCardView.translatesAutoresizingMaskIntoConstraints = false
        rotatingCardView.backgroundColor = .clear
        rotatingCardView.layer.masksToBounds = false
        perspectiveStageView.addSubview(rotatingCardView)

        let planes = [
            (frontPlaneView, frontSurfaceView, frontFaceView, AccessibilityID.frontPlane),
            (backPlaneView, backSurfaceView, backFaceView, AccessibilityID.backPlane)
        ]
        planes.forEach { plane in
            let (planeView, surfaceView, faceView, accessibilityIdentifier) = plane
            planeView.accessibilityIdentifier = accessibilityIdentifier
            planeView.translatesAutoresizingMaskIntoConstraints = false
            planeView.backgroundColor = .clear
            planeView.layer.isDoubleSided = false
            // CATransformLayer preserves both sides in one 3D coordinate space.
            // The carrier performs the entire 180-degree turn while these planes
            // keep a fixed offset, so the visual motion never reverses at 90°.
            rotatingCardView.addSubview(planeView)

            surfaceView.translatesAutoresizingMaskIntoConstraints = false
            surfaceView.layer.masksToBounds = true
            planeView.addSubview(surfaceView)

            faceView.translatesAutoresizingMaskIntoConstraints = false
            surfaceView.addSubview(faceView)
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
                faceView.bottomAnchor.constraint(equalTo: surfaceView.bottomAnchor)
            ])

        }

        flipInteractionButton.accessibilityIdentifier = AccessibilityID.flipInteractionOverlay
        flipInteractionButton.isAccessibilityElement = false
        flipInteractionButton.isHidden = true
        flipInteractionButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(flipInteractionButton)

        NSLayoutConstraint.activate([
            perspectiveStageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            perspectiveStageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            perspectiveStageView.topAnchor.constraint(equalTo: topAnchor),
            perspectiveStageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            parallaxPoseProbeView.leadingAnchor.constraint(equalTo: leadingAnchor),
            parallaxPoseProbeView.topAnchor.constraint(equalTo: topAnchor),
            parallaxPoseProbeView.widthAnchor.constraint(equalToConstant: 1),
            parallaxPoseProbeView.heightAnchor.constraint(equalToConstant: 1),

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

    func configureFrontFace() {
        frontFaceView.accessibilityIdentifier = AccessibilityID.front

        frontSurfaceButton.accessibilityIdentifier = AccessibilityID.frontSurfaceButton
        frontSurfaceButton.isAccessibilityElement = false
        frontSurfaceButton.translatesAutoresizingMaskIntoConstraints = false

        frontArtworkDepthView.accessibilityIdentifier = AccessibilityID.frontArtworkDepth
        frontArtworkDepthView.translatesAutoresizingMaskIntoConstraints = false
        frontArtworkDepthView.isUserInteractionEnabled = false

        frontImageView.accessibilityIdentifier = AccessibilityID.frontImage
        frontImageView.contentMode = .scaleAspectFit
        frontImageView.isAccessibilityElement = false
        frontImageView.isUserInteractionEnabled = false
        frontImageView.translatesAutoresizingMaskIntoConstraints = false

        frontIconShadowView.accessibilityIdentifier = AccessibilityID.frontImageShadow
        frontIconShadowView.contentMode = .scaleAspectFit
        frontIconShadowView.isAccessibilityElement = false
        frontIconShadowView.isUserInteractionEnabled = false
        frontIconShadowView.translatesAutoresizingMaskIntoConstraints = false

        frontTitleDepthView.accessibilityIdentifier = AccessibilityID.frontTitleDepth
        frontTitleDepthView.translatesAutoresizingMaskIntoConstraints = false
        frontTitleDepthView.isUserInteractionEnabled = false

        frontTitleLabel.adjustsFontForContentSizeCategory = true
        frontTitleLabel.numberOfLines = 2
        // AI-generated themes can exceed two lines. Word-wrapping without a
        // truncation indicator silently cuts the tail; tail truncation makes
        // the ellipsis visible to the user.
        frontTitleLabel.lineBreakMode = .byTruncatingTail
        frontTitleLabel.textAlignment = .center
        frontTitleLabel.isAccessibilityElement = true
        frontTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        configureIconButton(
            closeButton,
            systemImageName: "xmark",
            accessibilityIdentifier: AccessibilityID.closeButton,
            accessibilityLabel: L10n.ThemeCard.closeAccessibilityLabel
        )
        configureIconButton(
            infoButton,
            systemImageName: "play.fill",
            accessibilityIdentifier: AccessibilityID.infoButton,
            accessibilityLabel: L10n.ThemeCard.showDescriptionAccessibilityLabel
        )

        frontFaceView.addSubview(frontSurfaceButton)
        frontFaceView.addSubview(frontArtworkDepthView)
        frontArtworkDepthView.addSubview(frontIconShadowView)
        frontArtworkDepthView.addSubview(frontImageView)
        frontFaceView.addSubview(frontTitleDepthView)
        frontTitleDepthView.addSubview(frontTitleLabel)
        frontFaceView.addSubview(closeButton)
        frontFaceView.addSubview(infoButton)
        frontImageSizeConstraint = frontArtworkDepthView.widthAnchor.constraint(
            equalToConstant: Layout.cleanFrontArtworkPointSize
        )

        NSLayoutConstraint.activate([
            frontSurfaceButton.leadingAnchor.constraint(equalTo: frontFaceView.leadingAnchor),
            frontSurfaceButton.trailingAnchor.constraint(equalTo: frontFaceView.trailingAnchor),
            frontSurfaceButton.topAnchor.constraint(equalTo: frontFaceView.topAnchor),
            frontSurfaceButton.bottomAnchor.constraint(equalTo: frontFaceView.bottomAnchor),

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

            infoButton.trailingAnchor.constraint(
                equalTo: frontFaceView.trailingAnchor,
                constant: -Layout.controlInset
            ),
            infoButton.bottomAnchor.constraint(
                equalTo: frontFaceView.bottomAnchor,
                constant: -Layout.controlInset
            ),
            infoButton.widthAnchor.constraint(equalToConstant: Layout.iconButtonSize),
            infoButton.heightAnchor.constraint(equalToConstant: Layout.iconButtonSize),

            frontTitleDepthView.leadingAnchor.constraint(
                equalTo: frontFaceView.leadingAnchor,
                constant: Layout.frontImageHorizontalInset
            ),
            frontTitleDepthView.trailingAnchor.constraint(
                lessThanOrEqualTo: infoButton.leadingAnchor,
                constant: -Layout.frontTitleToInfoSpacing
            ),
            frontTitleDepthView.bottomAnchor.constraint(
                equalTo: frontFaceView.bottomAnchor,
                constant: -Layout.frontTitleBottomInset
            ),

            frontTitleLabel.leadingAnchor.constraint(equalTo: frontTitleDepthView.leadingAnchor),
            frontTitleLabel.trailingAnchor.constraint(equalTo: frontTitleDepthView.trailingAnchor),
            frontTitleLabel.topAnchor.constraint(equalTo: frontTitleDepthView.topAnchor),
            frontTitleLabel.bottomAnchor.constraint(equalTo: frontTitleDepthView.bottomAnchor),

            frontArtworkDepthView.centerXAnchor.constraint(equalTo: frontFaceView.centerXAnchor),
            frontArtworkDepthView.centerYAnchor.constraint(
                equalTo: frontFaceView.centerYAnchor,
                constant: Layout.frontArtworkCenterYOffset
            ),
            frontImageSizeConstraint,
            frontArtworkDepthView.heightAnchor.constraint(equalTo: frontArtworkDepthView.widthAnchor),
            frontArtworkDepthView.topAnchor.constraint(
                greaterThanOrEqualTo: closeButton.bottomAnchor,
                constant: Layout.frontImageToTitleSpacing
            ),
            frontArtworkDepthView.bottomAnchor.constraint(
                lessThanOrEqualTo: frontTitleDepthView.topAnchor,
                constant: -Layout.frontImageToTitleSpacing
            ),

            frontImageView.leadingAnchor.constraint(equalTo: frontArtworkDepthView.leadingAnchor),
            frontImageView.trailingAnchor.constraint(equalTo: frontArtworkDepthView.trailingAnchor),
            frontImageView.topAnchor.constraint(equalTo: frontArtworkDepthView.topAnchor),
            frontImageView.bottomAnchor.constraint(equalTo: frontArtworkDepthView.bottomAnchor),

            frontIconShadowView.leadingAnchor.constraint(equalTo: frontArtworkDepthView.leadingAnchor),
            frontIconShadowView.trailingAnchor.constraint(equalTo: frontArtworkDepthView.trailingAnchor),
            frontIconShadowView.topAnchor.constraint(equalTo: frontArtworkDepthView.topAnchor),
            frontIconShadowView.bottomAnchor.constraint(equalTo: frontArtworkDepthView.bottomAnchor)
        ])

        frontFaceView.accessibilityElements = [frontTitleLabel, infoButton, closeButton]
    }

    func configureBackFace() {
        backFaceView.accessibilityIdentifier = AccessibilityID.back

        backSurfaceButton.accessibilityIdentifier = AccessibilityID.backSurfaceButton
        backSurfaceButton.isAccessibilityElement = false
        backSurfaceButton.translatesAutoresizingMaskIntoConstraints = false

        backTapGestureRecognizer.cancelsTouchesInView = false
        backTapGestureRecognizer.delegate = self
        backTapGestureRecognizer.require(toFail: descriptionScrollView.panGestureRecognizer)
        backFaceView.addGestureRecognizer(backTapGestureRecognizer)

        configureIconButton(
            backButton,
            systemImageName: "chevron.left",
            accessibilityIdentifier: AccessibilityID.backButton,
            accessibilityLabel: L10n.ThemeCard.showFrontAccessibilityLabel
        )

        backTitleLabel.accessibilityIdentifier = AccessibilityID.themeNameLabel
        backTitleLabel.adjustsFontForContentSizeCategory = true
        backTitleLabel.numberOfLines = 2
        backTitleLabel.lineBreakMode = .byTruncatingTail
        backTitleLabel.isAccessibilityElement = true
        backTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        descriptionScrollView.accessibilityIdentifier = "descriptionScrollView"
        descriptionScrollView.alwaysBounceVertical = false
        descriptionScrollView.isDirectionalLockEnabled = true
        descriptionScrollView.keyboardDismissMode = .onDrag
        descriptionScrollView.translatesAutoresizingMaskIntoConstraints = false

        backDescriptionLabel.accessibilityIdentifier = AccessibilityID.descriptionLabel
        backDescriptionLabel.adjustsFontForContentSizeCategory = true
        backDescriptionLabel.numberOfLines = 0
        backDescriptionLabel.lineBreakMode = .byWordWrapping
        backDescriptionLabel.isAccessibilityElement = true
        backDescriptionLabel.translatesAutoresizingMaskIntoConstraints = false

        questionFilterButton.accessibilityIdentifier = "descriptionCountryPicker"
        questionFilterButton.accessibilityLabel = L10n.ThemeCard.country
        questionFilterButton.showsMenuAsPrimaryAction = true
        questionFilterButton.titleLabel?.adjustsFontForContentSizeCategory = true
        questionFilterButton.titleLabel?.numberOfLines = 0
        questionFilterButton.isHidden = true
        let filterHeight = questionFilterButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        filterHeight.priority = .defaultHigh
        filterHeight.isActive = true

        difficultyLabel.accessibilityIdentifier = AccessibilityID.difficultyLabel
        difficultyLabel.text = L10n.AITheme.difficulty
        difficultyLabel.adjustsFontForContentSizeCategory = true
        difficultyLabel.numberOfLines = 0

        difficultyControl.accessibilityIdentifier = AccessibilityID.difficultyControl
        difficultyControl.accessibilityLabel = L10n.AITheme.difficulty
        difficultyControl.translatesAutoresizingMaskIntoConstraints = false

        questionCountLabel.accessibilityIdentifier = AccessibilityID.questionCountLabel
        questionCountLabel.text = L10n.ThemeCard.questionCount
        questionCountLabel.adjustsFontForContentSizeCategory = true
        questionCountLabel.numberOfLines = 0

        questionCountControl.accessibilityIdentifier = AccessibilityID.questionCountControl
        questionCountControl.accessibilityLabel = L10n.ThemeCard.questionCount
        questionCountControl.translatesAutoresizingMaskIntoConstraints = false

        unavailableLabel.accessibilityIdentifier = AccessibilityID.unavailableLabel
        unavailableLabel.text = L10n.Question.unavailableMessage
        unavailableLabel.adjustsFontForContentSizeCategory = true
        unavailableLabel.numberOfLines = 0
        unavailableLabel.textAlignment = .center

        startButton.accessibilityIdentifier = AccessibilityID.startButton
        startButton.setTitle(L10n.Common.start, for: .normal)
        startButton.titleLabel?.adjustsFontForContentSizeCategory = true
        startButton.translatesAutoresizingMaskIntoConstraints = false
        startButton.installPressFeedback()

        startActivityIndicator.accessibilityIdentifier = AccessibilityID.startActivityIndicator
        startActivityIndicator.hidesWhenStopped = true
        startActivityIndicator.isUserInteractionEnabled = false
        startActivityIndicator.translatesAutoresizingMaskIntoConstraints = false
        startButton.addSubview(startActivityIndicator)
        NSLayoutConstraint.activate([
            startActivityIndicator.centerXAnchor.constraint(equalTo: startButton.centerXAnchor),
            startActivityIndicator.centerYAnchor.constraint(equalTo: startButton.centerYAnchor)
        ])

        backControlsStack.axis = .vertical
        backControlsStack.alignment = .fill
        backControlsStack.spacing = Layout.controlsSpacing
        backControlsStack.translatesAutoresizingMaskIntoConstraints = false
        [
            questionFilterButton,
            difficultyLabel,
            difficultyControl,
            questionCountLabel,
            questionCountControl,
            unavailableLabel,
            startButton
        ].forEach(backControlsStack.addArrangedSubview)

        backFaceView.addSubview(backSurfaceButton)
        backFaceView.addSubview(backButton)
        backFaceView.addSubview(backTitleLabel)
        backFaceView.addSubview(descriptionScrollView)
        backFaceView.addSubview(backControlsStack)
        descriptionScrollView.addSubview(backDescriptionLabel)

        let difficultyHeight = difficultyControl.heightAnchor.constraint(
            greaterThanOrEqualToConstant: Layout.segmentedControlHeight
        )
        // UIStackView must be able to collapse this control for bundled content.
        difficultyHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            backSurfaceButton.leadingAnchor.constraint(equalTo: backFaceView.leadingAnchor),
            backSurfaceButton.trailingAnchor.constraint(equalTo: backFaceView.trailingAnchor),
            backSurfaceButton.topAnchor.constraint(equalTo: backFaceView.topAnchor),
            backSurfaceButton.bottomAnchor.constraint(equalTo: backFaceView.bottomAnchor),

            backButton.topAnchor.constraint(
                equalTo: backFaceView.topAnchor,
                constant: Layout.controlInset
            ),
            backButton.leadingAnchor.constraint(
                equalTo: backFaceView.leadingAnchor,
                constant: Layout.controlInset
            ),
            backButton.widthAnchor.constraint(equalToConstant: Layout.iconButtonSize),
            backButton.heightAnchor.constraint(equalToConstant: Layout.iconButtonSize),

            backTitleLabel.topAnchor.constraint(
                equalTo: backFaceView.topAnchor,
                constant: Layout.edgeInset
            ),
            backTitleLabel.leadingAnchor.constraint(
                equalTo: backButton.trailingAnchor,
                constant: Layout.backHeaderSpacing
            ),
            backTitleLabel.trailingAnchor.constraint(
                equalTo: backFaceView.trailingAnchor,
                constant: -Layout.edgeInset
            ),

            descriptionScrollView.topAnchor.constraint(
                greaterThanOrEqualTo: backButton.bottomAnchor,
                constant: Layout.backContentSpacing
            ),
            descriptionScrollView.topAnchor.constraint(
                greaterThanOrEqualTo: backTitleLabel.bottomAnchor,
                constant: Layout.backContentSpacing
            ),
            descriptionScrollView.leadingAnchor.constraint(
                equalTo: backFaceView.leadingAnchor,
                constant: Layout.edgeInset
            ),
            descriptionScrollView.trailingAnchor.constraint(
                equalTo: backFaceView.trailingAnchor,
                constant: -Layout.edgeInset
            ),
            descriptionScrollView.bottomAnchor.constraint(
                equalTo: backControlsStack.topAnchor,
                constant: -Layout.backContentSpacing
            ),

            backDescriptionLabel.topAnchor.constraint(
                equalTo: descriptionScrollView.contentLayoutGuide.topAnchor
            ),
            backDescriptionLabel.leadingAnchor.constraint(
                equalTo: descriptionScrollView.contentLayoutGuide.leadingAnchor
            ),
            backDescriptionLabel.trailingAnchor.constraint(
                equalTo: descriptionScrollView.contentLayoutGuide.trailingAnchor
            ),
            backDescriptionLabel.bottomAnchor.constraint(
                equalTo: descriptionScrollView.contentLayoutGuide.bottomAnchor
            ),
            backDescriptionLabel.widthAnchor.constraint(
                equalTo: descriptionScrollView.frameLayoutGuide.widthAnchor
            ),

            backControlsStack.leadingAnchor.constraint(
                equalTo: backFaceView.leadingAnchor,
                constant: Layout.edgeInset
            ),
            backControlsStack.trailingAnchor.constraint(
                equalTo: backFaceView.trailingAnchor,
                constant: -Layout.edgeInset
            ),
            backControlsStack.bottomAnchor.constraint(
                equalTo: backFaceView.bottomAnchor,
                constant: -Layout.edgeInset
            ),

            difficultyHeight,
            questionCountControl.heightAnchor.constraint(
                greaterThanOrEqualToConstant: Layout.segmentedControlHeight
            ),
            startButton.heightAnchor.constraint(
                greaterThanOrEqualToConstant: Layout.startButtonMinimumHeight
            )
        ])

        let preferredDescriptionTopConstraint = descriptionScrollView.topAnchor.constraint(
            equalTo: backTitleLabel.bottomAnchor,
            constant: Layout.backContentSpacing
        )
        preferredDescriptionTopConstraint.priority = .defaultHigh
        preferredDescriptionTopConstraint.isActive = true

        backFaceView.accessibilityElements = [
            backTitleLabel,
            backDescriptionLabel,
            questionFilterButton,
            difficultyLabel,
            difficultyControl,
            questionCountLabel,
            questionCountControl,
            startButton,
            backButton
        ]
    }

    func configureActions() {
        cardParallaxPanGestureRecognizer.name = "expandedThemeCardParallaxPan"
        cardParallaxPanGestureRecognizer.maximumNumberOfTouches = 1
        cardParallaxPanGestureRecognizer.cancelsTouchesInView = true
        cardParallaxPanGestureRecognizer.delaysTouchesBegan = false
        cardParallaxPanGestureRecognizer.delegate = self
        // The outer card owns one pan for both faces. On the back, it recognizes
        // alongside the description scroll view so the whole card remains a
        // continuous tilt surface without taking scrolling away from the user.
        addGestureRecognizer(cardParallaxPanGestureRecognizer)
        backTapGestureRecognizer.require(toFail: cardParallaxPanGestureRecognizer)

        frontSurfaceButton.addTarget(self, action: #selector(flipTapped), for: .touchUpInside)
        backSurfaceButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        infoButton.addTarget(self, action: #selector(flipTapped), for: .touchUpInside)
        flipInteractionButton.addTarget(self, action: #selector(flipTapped), for: .touchUpInside)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        questionCountControl.addTarget(
            self,
            action: #selector(questionCountChanged),
            for: .valueChanged
        )
        difficultyControl.addTarget(
            self,
            action: #selector(difficultyChanged),
            for: .valueChanged
        )
        startButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)

        closeButton.installPressFeedback()
        infoButton.installPressFeedback()
        backButton.installPressFeedback()
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
    }

}
