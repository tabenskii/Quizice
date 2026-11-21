import UIKit

extension ThemesCollectionService {
    @discardableResult
    func configureSecondaryActionCard(
        in cell: UICollectionViewCell,
        accessibilityIdentifier: String,
        accessibilityLabel: String,
        accessibilityHint: String,
        title: String,
        action: Selector,
        appearance: AppAppearance
    ) -> UIButton {
        let button = makeSecondaryActionButton(
            accessibilityIdentifier: accessibilityIdentifier,
            accessibilityLabel: accessibilityLabel,
            accessibilityHint: accessibilityHint,
            title: title,
            action: action,
            appearance: appearance
        )

        pin(button, to: cell.contentView)
        return button
    }

    private var visibleFeelingLuckyCard: FeelingLuckyCardView? {
        observedCollectionView?.visibleCells
            .lazy
            .flatMap(\.contentView.subviews)
            .compactMap { $0 as? FeelingLuckyCardView }
            .first
    }

    func refreshVisibleFeelingLuckyCard() {
        visibleFeelingLuckyCard?.setLoading(isFeelingLuckyLoading)
    }

    func makeSecondaryActionButton(
        accessibilityIdentifier: String,
        accessibilityLabel: String,
        accessibilityHint: String,
        title: String,
        action: Selector,
        appearance: AppAppearance
    ) -> UIButton {
        let button = HomeActionButton(type: .system)
        button.accessibilityIdentifier = accessibilityIdentifier
        button.accessibilityLabel = accessibilityLabel
        button.accessibilityHint = accessibilityHint
        button.applyActionAppearance(appearance.secondaryButton, appearance: appearance)
        applyCleanOutlineStyleIfNeeded(
            to: button,
            appearance: appearance,
            borderColor: appearance.screenTextColor.withAlphaComponent(0.18)
        )
        button.clipsToBounds = true
        button.setTitle(title, for: .normal)
        button.setTitleColor(appearance.screenTextColor, for: .normal)
        button.titleLabel?.font = appearance.typography.font(size: Appearance.luckyFontSize, weight: .semibold)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(buttonTouchedDown(_:)), for: .touchDown)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.addTarget(self, action: #selector(buttonTouchedUpOutside(_:)), for: .touchUpOutside)
        return button
    }

    func applyCleanOutlineStyleIfNeeded(
        to view: UIView,
        appearance: AppAppearance,
        borderColor: UIColor
    ) {
        guard appearance.designStyle == .clean else { return }
        view.backgroundColor = appearance.card.backgroundColor
        view.layer.borderColor = borderColor.cgColor
        view.layer.borderWidth = max(view.layer.borderWidth, Appearance.buttonBorderWidth)
    }

    func applyRadarTransparentStyleIfNeeded(to button: UIButton, appearance: AppAppearance) {
        guard appearance.designStyle == .radar else { return }
        button.backgroundColor = .clear
    }

    func applyRadarGreenGlowStyleIfNeeded(to button: UIButton, appearance: AppAppearance) {
        guard appearance.designStyle == .radar else { return }
        button.backgroundColor = .clear
        button.clipsToBounds = false
        button.layer.masksToBounds = false
        button.layer.borderWidth = Appearance.buttonBorderWidth
        button.layer.borderColor = appearance.accentColor.cgColor
        button.layer.shadowColor = appearance.accentColor.cgColor
        button.layer.shadowOpacity = Appearance.radarAIThemeGlowOpacity
        button.layer.shadowRadius = Appearance.radarAIThemeGlowRadius
        button.layer.shadowOffset = Appearance.radarAIThemeGlowOffset
        button.setNeedsLayout()
    }

    func pin(_ view: UIView, to container: UIView, bottomInset: CGFloat = .zero) {
        container.addSubview(view)
        view.constrainHomeActionWidth(in: container)

        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -bottomInset)
        ])
    }

    func configureFeelingLuckyCard(in cell: UICollectionViewCell, appearance: AppAppearance) {
        cell.applyShadow(.none)
        let buttons = QuizQuestionCountPolicy.supportedCounts.map { count in
            let button = UIButton(type: .system)
            button.tag = count
            button.setTitle(String(count), for: .normal)
            button.setTitleColor(appearance.screenTextColor, for: .normal)
            button.setTitleColor(appearance.disabledTextColor, for: .disabled)
            button.titleLabel?.font = appearance.typography.font(size: Appearance.luckyFontSize, weight: .semibold)
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.accessibilityIdentifier = "\(Content.feelingLuckyButtonAccessibilityID)-\(count)"
            button.accessibilityLabel = L10n.Home.feelingLuckyQuestionCount(count)
            button.addTarget(self, action: #selector(buttonTouchedDown(_:)), for: .touchDown)
            button.addTarget(self, action: #selector(feelingLuckyButtonTouchedUpInside(_:)), for: .touchUpInside)
            button.addTarget(self, action: #selector(buttonTouchedUpOutside(_:)), for: [.touchUpOutside, .touchCancel])
            return button
        }
        let card = FeelingLuckyCardView(appearance: appearance, buttons: buttons, traits: cell.traitCollection)
        applyCleanOutlineStyleIfNeeded(to: card, appearance: appearance,
                                       borderColor: appearance.screenTextColor.withAlphaComponent(0.18))
        card.setLoading(isFeelingLuckyLoading)
        pin(card, to: cell.contentView)
    }

    private func makeAIThemeTitleLabel(
        appearance: AppAppearance,
        traits: UITraitCollection,
        automaticallyAdjustsFont: Bool = true
    ) -> UILabel {
        let usesAccessibilityLayout = traits.preferredContentSizeCategory.isAccessibilityCategory
        let titleLabel = UILabel()
        titleLabel.accessibilityIdentifier = Content.aiThemeTitleAccessibilityID
        titleLabel.text = L10n.Home.createWithAI
        titleLabel.textColor = appearance.screenTextColor
        titleLabel.adjustsFontForContentSizeCategory = automaticallyAdjustsFont
        titleLabel.font = appearance.typography.font(
            size: Appearance.aiThemeTitleFontSize,
            weight: .semibold,
            compatibleWith: traits
        )
        titleLabel.numberOfLines = usesAccessibilityLayout ? 0 : 1
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.minimumScaleFactor = 0.82
        titleLabel.adjustsFontSizeToFitWidth = !usesAccessibilityLayout
        titleLabel.isUserInteractionEnabled = false
        return titleLabel
    }

    private func makeAIThemeSubtitleLabel(
        appearance: AppAppearance,
        traits: UITraitCollection,
        automaticallyAdjustsFont: Bool = true
    ) -> UILabel {
        let subtitleLabel = UILabel()
        subtitleLabel.accessibilityIdentifier = Content.aiThemeSubtitleAccessibilityID
        subtitleLabel.text = L10n.Subscription.aiCardSubtitle
        subtitleLabel.textColor = appearance.screenTextColor.withAlphaComponent(0.64)
        subtitleLabel.adjustsFontForContentSizeCategory = automaticallyAdjustsFont
        subtitleLabel.font = appearance.typography.font(
            size: Appearance.aiThemeSubtitleFontSize,
            weight: .regular,
            compatibleWith: traits
        )
        subtitleLabel.numberOfLines = traits.preferredContentSizeCategory.isAccessibilityCategory ? 0 : 2
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.isHidden = !hasActivePlusSubscription
        subtitleLabel.isUserInteractionEnabled = false
        return subtitleLabel
    }

    private var aiThemeBadgeTitle: String {
        (hasActivePlusSubscription ? L10n.Subscription.plus : L10n.Subscription.freeBadge)
            .uppercased(with: AppLocalizationStore.shared.resolvedLocale)
    }

    private func aiThemeBadgeWidth(font: UIFont) -> CGFloat {
        max(Layout.aiThemeBadgeMinimumWidth, ceil((aiThemeBadgeTitle as NSString).size(
            withAttributes: [.font: font]
        ).width) + 2 * Layout.aiThemeBadgeHorizontalInset)
    }

    func aiThemeCardHeight(width: CGFloat, traits: UITraitCollection) -> CGFloat {
        let appearance = AppAppearanceStore.shared.appearance(compatibleWith: traits)
        let usesAccessibilityLayout = traits.preferredContentSizeCategory.isAccessibilityCategory
        let badgeFont = appearance.typography.font(
            size: Appearance.aiThemeBadgeFontSize, weight: .bold, compatibleWith: traits
        )
        let trailingWidth = usesAccessibilityLayout
            ? Layout.aiThemeContentLeadingInset
            : Layout.aiThemeBadgeTrailingInset + aiThemeBadgeWidth(font: badgeFont) + Layout.aiThemeContentTrailingSpacing
        let textSize = CGSize(width: max(width - Layout.aiThemeContentLeadingInset - trailingWidth, 1),
                              height: .greatestFiniteMagnitude)
        // Detached measurement labels must keep the font scaled for the supplied
        // traits instead of rescaling it to UIKit's ambient content size category.
        let titleHeight = makeAIThemeTitleLabel(
            appearance: appearance, traits: traits, automaticallyAdjustsFont: false
        ).sizeThatFits(textSize).height
        let subtitleHeight = hasActivePlusSubscription
            ? makeAIThemeSubtitleLabel(
                appearance: appearance, traits: traits, automaticallyAdjustsFont: false
            ).sizeThatFits(textSize).height + 2
            : 0
        let badgeHeight = usesAccessibilityLayout ? 0 : badgeFont.lineHeight + 2 * Layout.aiThemeBadgeVerticalInset
        return max(Layout.aiThemeButtonHeight, ceil(max(titleHeight + subtitleHeight, badgeHeight) + 16))
    }

    func configureAIThemeCard(in cell: UICollectionViewCell, appearance: AppAppearance, traits: UITraitCollection) {
        cell.applyShadow(.none)
        let usesAccessibilityLayout = traits.preferredContentSizeCategory.isAccessibilityCategory
        let button = makeSecondaryActionButton(
            accessibilityIdentifier: Content.aiThemeAccessibilityID,
            accessibilityLabel: L10n.Home.createWithAIAccessibilityLabel,
            accessibilityHint: L10n.Home.createWithAIAccessibilityHint,
            title: L10n.Home.createWithAI,
            action: #selector(aiThemeButtonTouchedUpInside(_:)),
            appearance: appearance
        )
        button.isHidden = isAIThemePresented
        button.isEnabled = !isAIThemePresented
        button.isAccessibilityElement = !isAIThemePresented
        button.accessibilityElementsHidden = isAIThemePresented
        button.accessibilityValue = hasActivePlusSubscription ? L10n.Subscription.aiCardSubtitle : nil
        button.layer.borderWidth = 0
        button.layer.borderColor = UIColor.clear.cgColor
        let aiThemeCornerRadius = Layout.aiThemeButtonHeight / 2
        let titleLabel = makeAIThemeTitleLabel(appearance: appearance, traits: traits)
        let subtitleLabel = makeAIThemeSubtitleLabel(appearance: appearance, traits: traits)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = 2
        textStack.accessibilityIdentifier = Content.aiThemeTextStackAccessibilityID
        textStack.isUserInteractionEnabled = false
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let tierBadge = InsetLabel(
            contentInsets: UIEdgeInsets(
                top: Layout.aiThemeBadgeVerticalInset,
                left: Layout.aiThemeBadgeHorizontalInset,
                bottom: Layout.aiThemeBadgeVerticalInset,
                right: Layout.aiThemeBadgeHorizontalInset
            )
        )
        tierBadge.accessibilityIdentifier = Content.aiThemeBadgeAccessibilityID
        tierBadge.text = aiThemeBadgeTitle
        let tierBadgeAccentColor = appearance.designStyle == .radar
            ? appearance.accentColor
            : AIThemeVisualStyle.accentColor
        tierBadge.textColor = hasActivePlusSubscription
            ? tierBadgeAccentColor
            : appearance.screenTextColor
        tierBadge.adjustsFontForContentSizeCategory = true
        let badgeFont = appearance.typography.font(
            size: Appearance.aiThemeBadgeFontSize,
            weight: .bold,
            compatibleWith: traits
        )
        tierBadge.font = badgeFont
        tierBadge.textAlignment = .center
        tierBadge.backgroundColor = (
            hasActivePlusSubscription
                ? tierBadgeAccentColor
                : appearance.screenTextColor
        ).withAlphaComponent(Appearance.aiThemeBadgeBackgroundAlpha)
        tierBadge.layer.cornerRadius = Appearance.aiThemeBadgeCornerRadius
        tierBadge.layer.borderWidth = Appearance.buttonBorderWidth
        tierBadge.layer.borderColor = (
            hasActivePlusSubscription
                ? tierBadgeAccentColor
                : appearance.screenTextColor
        ).withAlphaComponent(
            Appearance.aiThemeBadgeBorderAlpha
        ).cgColor
        tierBadge.clipsToBounds = true
        tierBadge.isUserInteractionEnabled = false
        tierBadge.translatesAutoresizingMaskIntoConstraints = false

        pin(button, to: cell.contentView)
        cell.contentView.layoutIfNeeded()
        applyRadarGreenGlowStyleIfNeeded(to: button, appearance: appearance)
        button.setTitle(nil, for: .normal)
        button.addSubview(textStack)
        if !usesAccessibilityLayout {
            button.addSubview(tierBadge)
        }
        let gradientBorderView: GradientBorderView?
        if appearance.designStyle == .radar {
            gradientBorderView = nil
        } else {
            let borderView = GradientBorderView(
                colors: AIThemeVisualStyle.gradientColors,
                lineWidth: Appearance.aiThemeGradientBorderWidth,
                cornerRadius: aiThemeCornerRadius
            )
            button.layer.cornerRadius = aiThemeCornerRadius
            borderView.accessibilityIdentifier = Content.aiThemeGradientBorderAccessibilityID
            borderView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(borderView)
            gradientBorderView = borderView
        }

        var contentConstraints = [
            textStack.leadingAnchor.constraint(
                equalTo: button.leadingAnchor,
                constant: Layout.aiThemeContentLeadingInset
            ),
            textStack.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: button.topAnchor, constant: 8),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: button.bottomAnchor, constant: -8)
        ]

        if usesAccessibilityLayout {
            contentConstraints.append(
                textStack.trailingAnchor.constraint(
                    equalTo: button.trailingAnchor,
                    constant: -Layout.aiThemeContentLeadingInset
                )
            )
        } else {
            contentConstraints.append(contentsOf: [
                tierBadge.leadingAnchor.constraint(
                    equalTo: textStack.trailingAnchor,
                    constant: Layout.aiThemeContentTrailingSpacing
                ),
                tierBadge.trailingAnchor.constraint(
                    equalTo: button.trailingAnchor,
                    constant: -Layout.aiThemeBadgeTrailingInset
                ),
                tierBadge.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                tierBadge.widthAnchor.constraint(
                    equalToConstant: aiThemeBadgeWidth(font: badgeFont)
                )
            ])
        }
        NSLayoutConstraint.activate(contentConstraints)

        if let gradientBorderView {
            NSLayoutConstraint.activate([
                gradientBorderView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                gradientBorderView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                gradientBorderView.topAnchor.constraint(equalTo: button.topAnchor),
                gradientBorderView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])
        }
    }

    @objc func feelingLuckyButtonTouchedUpInside(_ sender: UIButton) {
        guard QuizQuestionCountPolicy.supportedCounts.contains(sender.tag) else { return }
        delegate?.feelingLuckyButtonTouchedUpInside(
            sender, questionCount: sender.tag, sourceView: visibleFeelingLuckyCard ?? sender
        )
    }

    @objc func aiThemeButtonTouchedUpInside(_ sender: UIButton) {
        delegate?.aiThemeButtonTouchedUpInside(sender)
    }

    @objc func subscriptionPromoButtonTouchedUpInside(_ sender: UIButton) {
        delegate?.subscriptionPromoButtonTouchedUpInside(sender)
    }

    @objc func statisticsButtonTouchedUpInside(_ sender: UIButton) {
        delegate?.statisticsButtonTouchedUpInside(sender)
    }
}

private final class FeelingLuckyCardView: UIView {
    private let prompt = UILabel()
    private let buttons: [UIButton]
    private let options: UIStackView
    private let progress: UIActivityIndicatorView
    private let loadingContent: UIStackView

    init(appearance: AppAppearance, buttons: [UIButton], traits: UITraitCollection) {
        self.buttons = buttons
        options = UIStackView(arrangedSubviews: buttons)
        let progress = UIActivityIndicatorView(style: .medium)
        self.progress = progress
        let loadingLabel = UILabel()
        loadingContent = UIStackView(arrangedSubviews: [progress, loadingLabel])
        super.init(frame: .zero)

        accessibilityIdentifier = ThemesCollectionService.Content.feelingLuckyAccessibilityID
        translatesAutoresizingMaskIntoConstraints = false
        applySurfaceStyle(appearance.secondaryButton)
        clipsToBounds = true

        prompt.text = L10n.Home.feelingLucky
        prompt.textAlignment = .center
        loadingLabel.text = L10n.Home.feelingLuckyLoading
        for label in [prompt, loadingLabel] {
            label.textColor = appearance.screenTextColor
            label.font = appearance.typography.font(size: 17, weight: .semibold, compatibleWith: traits)
            label.adjustsFontForContentSizeCategory = true
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.65
        }

        options.distribution = .fillEqually
        let selectionContent = UIStackView(arrangedSubviews: [prompt, options])
        selectionContent.axis = .vertical
        selectionContent.translatesAutoresizingMaskIntoConstraints = false
        addSubview(selectionContent)

        let isAccessibilitySize = traits.preferredContentSizeCategory.isAccessibilityCategory
        NSLayoutConstraint.activate([
            selectionContent.leadingAnchor.constraint(equalTo: leadingAnchor),
            selectionContent.trailingAnchor.constraint(equalTo: trailingAnchor),
            selectionContent.topAnchor.constraint(equalTo: topAnchor),
            selectionContent.bottomAnchor.constraint(equalTo: bottomAnchor),
            options.heightAnchor.constraint(equalToConstant: isAccessibilitySize ? 60 : 44)
        ])

        for button in buttons.dropFirst() {
            let divider = UIView()
            divider.translatesAutoresizingMaskIntoConstraints = false
            divider.backgroundColor = appearance.screenTextColor.withAlphaComponent(0.18)
            divider.isUserInteractionEnabled = false
            button.addSubview(divider)
            NSLayoutConstraint.activate([
                divider.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                divider.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                divider.widthAnchor.constraint(equalToConstant: 1),
                divider.heightAnchor.constraint(equalTo: button.heightAnchor, multiplier: 0.6)
            ])
        }

        progress.accessibilityIdentifier = ThemesCollectionService.Content.feelingLuckyProgressAccessibilityID
        progress.color = appearance.screenTextColor
        loadingContent.alignment = .center
        loadingContent.spacing = 10
        loadingContent.translatesAutoresizingMaskIntoConstraints = false
        loadingContent.isUserInteractionEnabled = false
        addSubview(loadingContent)
        NSLayoutConstraint.activate([
            loadingContent.centerXAnchor.constraint(equalTo: centerXAnchor),
            loadingContent.centerYAnchor.constraint(equalTo: centerYAnchor),
            loadingContent.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            loadingContent.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setLoading(_ isLoading: Bool) {
        let showsOptions = !isLoading
        isAccessibilityElement = isLoading
        accessibilityLabel = isLoading ? L10n.Home.feelingLuckyLoading : nil
        accessibilityTraits = isLoading ? [.staticText, .updatesFrequently] : []
        prompt.alpha = showsOptions ? 1 : 0
        buttons.forEach { $0.isEnabled = showsOptions }
        options.alpha = showsOptions ? 1 : 0
        options.isUserInteractionEnabled = showsOptions
        options.accessibilityElementsHidden = isLoading
        loadingContent.isHidden = showsOptions
        if isLoading {
            progress.startAnimating()
        } else {
            progress.stopAnimating()
        }
    }
}
