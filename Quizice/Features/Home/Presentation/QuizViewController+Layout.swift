import UIKit

extension QuizViewController {
    func configureProgrammaticSubviews(in rootView: UIView) {
        configureHeaderViews()
        configureSettingsButton()
        configureHelpButton()
        configureHeaderStack()
        configureThemesCollectionView()
        configureScreenStack()
        configureInitialStartupVisibilityIfNeeded()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (viewController: QuizViewController, _: UITraitCollection) in
            viewController.themesCollectionService.captureScrollAnchor()
            viewController.themesCollectionView.collectionViewLayout.invalidateLayout()
            viewController.view.setNeedsLayout()
        }

        rootView.addSubview(headerStackView)
        rootView.addSubview(screenStackView)
        rootView.addSubview(settingsButton)
        rootView.addSubview(helpButton)
        applyLayerOrdering()
        activateLayoutConstraints(in: rootView)
    }

    func configureThemesCollectionService() {
        themesCollectionView.backgroundColor = .clear
        themesCollectionService.delegate = self
        themesCollectionView.delegate = themesCollectionService
        themesCollectionView.dataSource = themesCollectionService
        themesCollectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: Content.themeCellReuseIdentifier)
        themesCollectionView.register(
            ThemesViewportCollectionViewCell.self,
            forCellWithReuseIdentifier: ThemesViewportCollectionViewCell.reuseIdentifier
        )
        themesCollectionView.register(
            StatisticsCardCollectionViewCell.self,
            forCellWithReuseIdentifier: StatisticsCardCollectionViewCell.reuseIdentifier
        )
        themesCollectionView.register(
            SubscriptionPromoBannerCollectionViewCell.self,
            forCellWithReuseIdentifier: SubscriptionPromoBannerCollectionViewCell.reuseIdentifier
        )
    }

    func configureHeaderViews() {
        let typography = currentAppearance().typography
        motivationContainerView = UIView()
        motivationContainerView.translatesAutoresizingMaskIntoConstraints = false

        motivationLabel = makeLabel(text: motivationPromptProvider(nil), font: typography.font(size: Typography.motivationFontSize, weight: .bold))
        motivationLabel.numberOfLines = 2
        motivationLabel.accessibilityIdentifier = AccessibilityID.motivationLabel
        motivationLabel.adjustsFontForContentSizeCategory = true

        motivationContainerView.addSubview(motivationLabel)

        NSLayoutConstraint.activate([
            motivationLabel.leadingAnchor.constraint(equalTo: motivationContainerView.leadingAnchor),
            motivationLabel.trailingAnchor.constraint(equalTo: motivationContainerView.trailingAnchor),
            motivationLabel.topAnchor.constraint(equalTo: motivationContainerView.topAnchor),
            motivationLabel.bottomAnchor.constraint(equalTo: motivationContainerView.bottomAnchor)
        ])

#if DEBUG
        debugCatalogSourceLabel = InsetLabel(
            contentInsets: UIEdgeInsets(top: 4, left: 7, bottom: 4, right: 7)
        )
        debugCatalogSourceLabel.accessibilityIdentifier = AccessibilityID.backendCatalogSource
        debugCatalogSourceLabel.font = .monospacedSystemFont(
            ofSize: Typography.backendSourceFontSize,
            weight: .semibold
        )
        debugCatalogSourceLabel.textColor = AppAssetColor.white.uiColor
        debugCatalogSourceLabel.layer.cornerRadius = 9
        debugCatalogSourceLabel.clipsToBounds = true
        debugCatalogSourceLabel.isHidden = !DebugBackendSettings.shouldShowSourceIndicators
        debugCatalogSourceLabel.setContentHuggingPriority(.required, for: .horizontal)
        debugCatalogSourceLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        debugCatalogSourceLabel.isAccessibilityElement = false
        updateDebugCatalogSourceIndicator()
#endif
    }

    func configureSettingsButton() {
        settingsButton = UIButton(type: .system)
        settingsButtonVisualSurface = UIView()
        settingsButtonVisualSurface.accessibilityIdentifier = AccessibilityID.settingsVisualSurface
        settingsButtonVisualSurface.isUserInteractionEnabled = false
        settingsButtonVisualSurface.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.accessibilityIdentifier = AccessibilityID.settingsButton
        settingsButton.accessibilityLabel = L10n.Settings.title
        let settingsIcon = UIImage(
            systemName: Content.settingsIconName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: Typography.settingsIconPointSize, weight: .semibold)
        )
        settingsButton.setImage(settingsIcon, for: .normal)
        settingsButton.tintColor = AppAssetColor.white.uiColor
        settingsButton.insertSubview(settingsButtonVisualSurface, at: 0)
        NSLayoutConstraint.activate([
            settingsButtonVisualSurface.centerXAnchor.constraint(equalTo: settingsButton.centerXAnchor),
            settingsButtonVisualSurface.centerYAnchor.constraint(equalTo: settingsButton.centerYAnchor),
            settingsButtonVisualSurface.widthAnchor.constraint(equalToConstant: Layout.settingsButtonVisualSize),
            settingsButtonVisualSurface.heightAnchor.constraint(equalToConstant: Layout.settingsButtonVisualSize)
        ])
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.addTarget(self, action: #selector(settingsButtonTapped), for: .touchUpInside)
#if DEBUG
        let debugMenuGesture = UILongPressGestureRecognizer(
            target: self,
            action: #selector(settingsButtonLongPressed(_:))
        )
        debugMenuGesture.minimumPressDuration = 0.5
        settingsButton.addGestureRecognizer(debugMenuGesture)
#endif
        settingsButton.installPressFeedback()
    }

    func configureHelpButton() {
        helpButton = UIButton(type: .system)
        helpButtonVisualSurface = UIView()
        helpButtonVisualSurface.accessibilityIdentifier = AccessibilityID.helpVisualSurface
        helpButtonVisualSurface.isUserInteractionEnabled = false
        helpButtonVisualSurface.translatesAutoresizingMaskIntoConstraints = false
        helpButton.accessibilityIdentifier = AccessibilityID.helpButton
        helpButton.accessibilityLabel = L10n.Onboarding.helpAccessibilityLabel
        helpButton.accessibilityHint = L10n.Onboarding.helpAccessibilityHint
        let helpIcon = UIImage(
            systemName: Content.helpIconName,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: Typography.settingsIconPointSize,
                weight: .bold
            )
        )
        helpButton.setImage(helpIcon, for: .normal)
        helpButton.tintColor = AppAssetColor.white.uiColor
        helpButton.insertSubview(helpButtonVisualSurface, at: 0)
        NSLayoutConstraint.activate([
            helpButtonVisualSurface.centerXAnchor.constraint(equalTo: helpButton.centerXAnchor),
            helpButtonVisualSurface.centerYAnchor.constraint(equalTo: helpButton.centerYAnchor),
            helpButtonVisualSurface.widthAnchor.constraint(equalToConstant: Layout.settingsButtonVisualSize),
            helpButtonVisualSurface.heightAnchor.constraint(equalToConstant: Layout.settingsButtonVisualSize)
        ])
        helpButton.translatesAutoresizingMaskIntoConstraints = false
        helpButton.addTarget(self, action: #selector(helpButtonTapped), for: .touchUpInside)
        helpButton.installPressFeedback()
    }

    func configureHeaderStack() {
        var arrangedSubviews: [UIView] = [motivationContainerView]
#if DEBUG
        arrangedSubviews.append(debugCatalogSourceLabel)
#endif
        headerStackView = UIStackView(arrangedSubviews: arrangedSubviews)
        headerStackView.accessibilityIdentifier = AccessibilityID.headerStackView
        headerStackView.axis = .vertical
        headerStackView.alignment = .leading
        headerStackView.spacing = Layout.headerStackSpacing
        headerStackView.isLayoutMarginsRelativeArrangement = true
        headerStackView.directionalLayoutMargins = Layout.headerMargins
        headerStackView.isUserInteractionEnabled = false
        headerStackView.translatesAutoresizingMaskIntoConstraints = false
    }

#if DEBUG
    func updateDebugCatalogSourceIndicator() {
        guard let debugCatalogSourceLabel else { return }
        debugCatalogSourceLabel.text = debugCatalogSourceState.title
        debugCatalogSourceLabel.accessibilityLabel = debugCatalogSourceState.title
        switch debugCatalogSourceState {
        case .loading:
            debugCatalogSourceLabel.backgroundColor = AppAssetColor.gray.uiColor
        case .backend:
            debugCatalogSourceLabel.backgroundColor = AppAssetColor.fallbackGreen.uiColor
        case .backendStale:
            debugCatalogSourceLabel.backgroundColor = AppAssetColor.fallbackOrange.uiColor
        case .local:
            debugCatalogSourceLabel.backgroundColor = AppAssetColor.fallbackOrange.uiColor
        }
    }
#endif

    func configureThemesCollectionView() {
        let layout = HomeThemesCollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = Layout.collectionItemSpacing
        layout.minimumInteritemSpacing = Layout.collectionItemSpacing
        layout.sectionInset = Layout.collectionSectionInsets

        themesCollectionView = HomeThemesCollectionView(frame: .zero, collectionViewLayout: layout)
        themesCollectionView.accessibilityIdentifier = AccessibilityID.themesCollectionView
        themesCollectionView.accessibilityLabel = L10n.Home.themesCollectionAccessibilityLabel
        themesCollectionView.alwaysBounceVertical = false
        themesCollectionView.bounces = false
        themesCollectionView.canCancelContentTouches = true
        themesCollectionView.contentInsetAdjustmentBehavior = .never
        themesCollectionView.delaysContentTouches = true
        themesCollectionView.showsVerticalScrollIndicator = false
        themesCollectionView.isScrollEnabled = false
        themesCollectionView.translatesAutoresizingMaskIntoConstraints = false
        themesCollectionView.setContentHuggingPriority(.defaultLow, for: .vertical)
        themesCollectionView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    func configureScreenStack() {
        screenStackView = UIStackView(arrangedSubviews: [themesCollectionView])
        screenStackView.accessibilityIdentifier = AccessibilityID.screenStackView
        screenStackView.axis = .vertical
        screenStackView.alignment = .fill
        screenStackView.spacing = Layout.screenStackSpacing
        screenStackView.isLayoutMarginsRelativeArrangement = false
        screenStackView.translatesAutoresizingMaskIntoConstraints = false
    }

    func applyLayerOrdering() {
        headerStackView.layer.zPosition = Appearance.headerLayerZPosition
        motivationContainerView.layer.zPosition = Appearance.headerLayerZPosition
        screenStackView.layer.zPosition = Appearance.collectionLayerZPosition
        themesCollectionView.layer.zPosition = Appearance.collectionLayerZPosition
        settingsButton.layer.zPosition = Appearance.controlsLayerZPosition
        helpButton.layer.zPosition = Appearance.controlsLayerZPosition
    }

    func activateLayoutConstraints(in rootView: UIView) {
        let preferredWidth = screenStackView.widthAnchor.constraint(equalTo: rootView.safeAreaLayoutGuide.widthAnchor)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            screenStackView.centerXAnchor.constraint(equalTo: rootView.safeAreaLayoutGuide.centerXAnchor),
            screenStackView.widthAnchor.constraint(lessThanOrEqualTo: rootView.safeAreaLayoutGuide.widthAnchor),
            screenStackView.widthAnchor.constraint(lessThanOrEqualToConstant: 1_180),
            preferredWidth,
            screenStackView.topAnchor.constraint(equalTo: rootView.safeAreaLayoutGuide.topAnchor),
            screenStackView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            headerStackView.topAnchor.constraint(equalTo: rootView.safeAreaLayoutGuide.topAnchor, constant: Layout.screenTopInset),
            headerStackView.leadingAnchor.constraint(equalTo: screenStackView.leadingAnchor),
            headerStackView.trailingAnchor.constraint(equalTo: screenStackView.trailingAnchor),

            settingsButton.topAnchor.constraint(equalTo: rootView.safeAreaLayoutGuide.topAnchor, constant: Layout.settingsButtonTopInset),
            settingsButton.trailingAnchor.constraint(equalTo: screenStackView.trailingAnchor, constant: -Layout.settingsButtonTrailingInset),
            settingsButton.widthAnchor.constraint(equalToConstant: Layout.settingsButtonSize),
            settingsButton.heightAnchor.constraint(equalToConstant: Layout.settingsButtonSize),

            helpButton.topAnchor.constraint(
                equalTo: settingsButton.bottomAnchor,
                constant: Layout.helpButtonSpacing
            ),
            helpButton.trailingAnchor.constraint(equalTo: settingsButton.trailingAnchor),
            helpButton.widthAnchor.constraint(equalToConstant: Layout.settingsButtonSize),
            helpButton.heightAnchor.constraint(equalToConstant: Layout.settingsButtonSize),

            motivationContainerView.widthAnchor.constraint(equalTo: headerStackView.layoutMarginsGuide.widthAnchor)
        ])
    }

    func makeLabel(text: String, font: UIFont) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = AppAssetColor.white.uiColor
        label.font = font
        label.textAlignment = .left
        label.numberOfLines = Typography.unlimitedNumberOfLines
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    func configureInitialStartupVisibilityIfNeeded() {
        guard session.startup1st else { return }
        startupAnimatedViews.forEach { $0.alpha = AnimationTiming.initialVisibleAlpha }
    }

    func updateCollectionScrollAvailability() {
        let canScroll = themesCollectionService.usesOuterScrolling && themesCollectionView.isUserInteractionEnabled
        themesCollectionView.isScrollEnabled = canScroll
        themesCollectionView.alwaysBounceVertical = canScroll
        themesCollectionView.bounces = canScroll
    }

    func updateCollectionTopInset() {
        let oldTopInset = themesCollectionView.contentInset.top
        let safeAreaTop = view.safeAreaInsets.top
        let headerBottom = headerStackView.frame.maxY - safeAreaTop
        let controlsBottom = helpButton.frame.maxY - safeAreaTop
        let topInset = max(headerBottom, controlsBottom) + Layout.headerToCollectionSpacing
        guard abs(oldTopInset - topInset) > Layout.scrollActivationTolerance else { return }

        let contentOffsetFromTopInset = themesCollectionView.contentOffset.y + oldTopInset
        themesCollectionView.contentInset.top = topInset
        themesCollectionView.verticalScrollIndicatorInsets.top = topInset
        themesCollectionView.collectionViewLayout.invalidateLayout()

        if !themesCollectionView.isDragging && !themesCollectionView.isDecelerating {
            themesCollectionView.contentOffset.y = contentOffsetFromTopInset - topInset
        }
    }

    func updateMotivationHeaderVisibility(for scrollView: UIScrollView) {
        let scrolledDistance = max(scrollView.contentOffset.y + scrollView.adjustedContentInset.top, .zero)
        let progress = min(scrolledDistance / Layout.motivationFadeDistance, 1)
        let alpha = 1 - progress

        motivationLabel.alpha = alpha
    }

    func animateStartupViews() {
        let visibleCells = sortedVisibleThemeCells()
        prepareStartupAnimation(visibleCells: visibleCells)

        guard !UIAccessibility.isReduceMotionEnabled else {
            startupAnimatedViews.forEach { $0.alpha = Appearance.visibleAlpha }
            visibleCells.forEach { $0.alpha = Appearance.visibleAlpha }
            return
        }

        UIView.animate(
            withDuration: AnimationTiming.revealDuration,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]
        ) {
            self.startupAnimatedViews.forEach { $0.alpha = Appearance.visibleAlpha }
        }
        animateThemeCells(visibleCells)
    }

    func sortedVisibleThemeCells() -> [UICollectionViewCell] {
        themesCollectionService.visibleThemeCells.sorted { lhs, rhs in
            let verticalDistance = abs(lhs.frame.minY - rhs.frame.minY)
            if verticalDistance > Layout.visibleCellRowSortingTolerance {
                return lhs.frame.minY < rhs.frame.minY
            }
            return lhs.frame.minX < rhs.frame.minX
        }
    }

    func prepareStartupAnimation(visibleCells: [UICollectionViewCell]) {
        visibleCells.forEach { cell in
            cell.alpha = AnimationTiming.initialVisibleAlpha
        }
    }

    func animateThemeCells(_ visibleCells: [UICollectionViewCell]) {
        for (index, cell) in visibleCells.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * AnimationTiming.cellFadeInStagger) {
                UIView.animate(
                    withDuration: AnimationTiming.revealDuration,
                    delay: 0,
                    options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]
                ) {
                    cell.alpha = Appearance.visibleAlpha
                }
            }
        }
    }
}
