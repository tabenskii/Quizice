import UIKit

final class SubscriptionPromoBannerCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "subscriptionPromoBannerCell"

    enum AccessibilityID {
        static let button = "homeSubscriptionPromoBanner"
        static let title = "homeSubscriptionPromoTitle"
        static let subtitle = "homeSubscriptionPromoSubtitle"
    }

    private enum Layout {
        static let horizontalInset: CGFloat = 16
        static let verticalInset: CGFloat = 12
        static let contentSpacing: CGFloat = 12
        static let textSpacing: CGFloat = 3
        static let iconSize: CGFloat = 42
        static let iconCornerRadius: CGFloat = 15
        static let chevronSize: CGFloat = 32
        static let chevronCornerRadius: CGFloat = 16
    }

    private enum Typography {
        static let titleSize: CGFloat = 18
        static let subtitleSize: CGFloat = 13
    }

    let actionButton = UIButton(type: .custom)

    private let gradientBackdropView = SubscriptionPromoGradientView()
    private let gradientBorderView = GradientBorderView(
        colors: AIThemeVisualStyle.gradientColors,
        lineWidth: 1.6
    )
    private let cardMaskLayer = CAShapeLayer()
    private let iconContainerView = UIView()
    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let chevronContainerView = UIView()
    private let chevronImageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureHierarchy()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        actionButton.removeTarget(nil, action: nil, for: .allEvents)
        actionButton.backgroundColor = .clear
        actionButton.layer.borderColor = nil
        actionButton.layer.borderWidth = 0
        actionButton.accessibilityLabel = nil
        actionButton.accessibilityHint = nil
        gradientBackdropView.colors = []
        gradientBorderView.isHidden = true
        iconContainerView.backgroundColor = .clear
        iconImageView.tintColor = nil
        titleLabel.text = nil
        titleLabel.textColor = nil
        subtitleLabel.text = nil
        subtitleLabel.textColor = nil
        chevronContainerView.backgroundColor = .clear
        chevronContainerView.layer.borderColor = nil
        chevronContainerView.layer.borderWidth = 0
        chevronImageView.tintColor = nil

        applyRoundedClipping(cornerRadius: 0)
        layer.shadowPath = nil
        applyShadow(.none)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let cornerRadius = actionButton.layer.cornerRadius
        applyRoundedClipping(cornerRadius: cornerRadius)
        cardMaskLayer.frame = actionButton.bounds
        cardMaskLayer.path = UIBezierPath(
            roundedRect: actionButton.bounds,
            cornerRadius: cornerRadius
        ).cgPath
        actionButton.layer.mask = cardMaskLayer
        let shadowBounds = actionButton.convert(actionButton.bounds, to: self)
        layer.shadowPath = UIBezierPath(
            roundedRect: shadowBounds,
            cornerRadius: cornerRadius
        ).cgPath
    }

    func configure(appearance: AppAppearance) {
        overrideUserInterfaceStyle = appearance.resolvedInterfaceStyle
        actionButton.accessibilityLabel = [
            L10n.Subscription.homeTitle,
            L10n.Subscription.homeSubtitle
        ].joined(separator: ". ")
        actionButton.accessibilityHint = L10n.Subscription.homeAccessibilityHint
        actionButton.layer.cornerRadius = appearance.card.cornerRadius
        actionButton.layer.cornerCurve = .continuous
        actionButton.layer.borderWidth = 0
        actionButton.layer.borderColor = UIColor.clear.cgColor
        actionButton.backgroundColor = appearance.card.backgroundColor
        applyRoundedClipping(cornerRadius: appearance.card.cornerRadius)

        titleLabel.text = L10n.Subscription.homeTitle
        titleLabel.font = appearance.typography.font(
            size: Typography.titleSize,
            weight: .semibold
        )
        titleLabel.textColor = appearance.surfaceTextColor
        subtitleLabel.text = L10n.Subscription.homeSubtitle
        subtitleLabel.font = appearance.typography.font(
            size: Typography.subtitleSize,
            weight: .regular
        )
        subtitleLabel.textColor = appearance.secondarySurfaceTextColor

        let premiumAccent: UIColor
        switch appearance.designStyle {
        case .radar:
            premiumAccent = appearance.accentColor
            gradientBackdropView.colors = [
                appearance.accentColor.withAlphaComponent(0.08),
                appearance.accentColor.withAlphaComponent(0.02)
            ]
            gradientBorderView.isHidden = true
            actionButton.layer.borderWidth = max(appearance.card.borderWidth, 1)
            actionButton.layer.borderColor = appearance.accentColor.cgColor
            applyShadow(
                AppShadowStyle(
                    color: appearance.accentColor,
                    opacity: 0.20,
                    radius: 10,
                    offset: .zero
                )
            )

        case .clean, .classic:
            premiumAccent = AIThemeVisualStyle.accentColor
            gradientBackdropView.colors = [
                AIThemeVisualStyle.gradientStartColor.withAlphaComponent(0.10),
                AIThemeVisualStyle.gradientEndColor.withAlphaComponent(0.12)
            ]
            gradientBorderView.isHidden = false
            applyShadow(.none)
        }

        iconContainerView.backgroundColor = premiumAccent.withAlphaComponent(0.13)
        iconImageView.tintColor = premiumAccent
        chevronContainerView.backgroundColor = appearance.row.backgroundColor
        chevronContainerView.layer.borderColor = premiumAccent.withAlphaComponent(0.22).cgColor
        chevronContainerView.layer.borderWidth = appearance.designStyle == .radar ? 1 : 0
        chevronImageView.tintColor = premiumAccent
        setNeedsLayout()
    }

    private func configureHierarchy() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        contentView.clipsToBounds = false
        layer.masksToBounds = false

        actionButton.accessibilityIdentifier = AccessibilityID.button
        actionButton.clipsToBounds = true
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        cardMaskLayer.fillColor = AppAssetColor.black.uiColor.cgColor
        contentView.addSubview(actionButton)

        gradientBackdropView.isUserInteractionEnabled = false
        gradientBackdropView.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addSubview(gradientBackdropView)

        gradientBorderView.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addSubview(gradientBorderView)

        iconContainerView.isUserInteractionEnabled = false
        iconContainerView.layer.cornerRadius = Layout.iconCornerRadius
        iconContainerView.layer.cornerCurve = .continuous
        iconContainerView.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addSubview(iconContainerView)

        iconImageView.image = UIImage(
            systemName: "sparkles",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 18,
                weight: .semibold
            )
        )
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.isUserInteractionEnabled = false
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconContainerView.addSubview(iconImageView)

        titleLabel.accessibilityIdentifier = AccessibilityID.title
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.isAccessibilityElement = false

        subtitleLabel.accessibilityIdentifier = AccessibilityID.subtitle
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 2
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.isAccessibilityElement = false

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.alignment = .fill
        textStack.spacing = Layout.textSpacing
        textStack.isUserInteractionEnabled = false
        textStack.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addSubview(textStack)

        chevronContainerView.isUserInteractionEnabled = false
        chevronContainerView.layer.cornerRadius = Layout.chevronCornerRadius
        chevronContainerView.layer.cornerCurve = .continuous
        chevronContainerView.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addSubview(chevronContainerView)

        chevronImageView.image = UIImage(
            systemName: "chevron.right",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 14,
                weight: .bold
            )
        )
        chevronImageView.contentMode = .scaleAspectFit
        chevronImageView.isUserInteractionEnabled = false
        chevronImageView.translatesAutoresizingMaskIntoConstraints = false
        chevronContainerView.addSubview(chevronImageView)

        actionButton.constrainHomeActionWidth(in: contentView)
        NSLayoutConstraint.activate([
            actionButton.topAnchor.constraint(equalTo: contentView.topAnchor),
            actionButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            gradientBackdropView.leadingAnchor.constraint(equalTo: actionButton.leadingAnchor),
            gradientBackdropView.trailingAnchor.constraint(equalTo: actionButton.trailingAnchor),
            gradientBackdropView.topAnchor.constraint(equalTo: actionButton.topAnchor),
            gradientBackdropView.bottomAnchor.constraint(equalTo: actionButton.bottomAnchor),

            gradientBorderView.leadingAnchor.constraint(equalTo: actionButton.leadingAnchor),
            gradientBorderView.trailingAnchor.constraint(equalTo: actionButton.trailingAnchor),
            gradientBorderView.topAnchor.constraint(equalTo: actionButton.topAnchor),
            gradientBorderView.bottomAnchor.constraint(equalTo: actionButton.bottomAnchor),

            iconContainerView.leadingAnchor.constraint(
                equalTo: actionButton.leadingAnchor,
                constant: Layout.horizontalInset
            ),
            iconContainerView.centerYAnchor.constraint(equalTo: actionButton.centerYAnchor),
            iconContainerView.widthAnchor.constraint(equalToConstant: Layout.iconSize),
            iconContainerView.heightAnchor.constraint(equalToConstant: Layout.iconSize),

            iconImageView.centerXAnchor.constraint(equalTo: iconContainerView.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: iconContainerView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 22),
            iconImageView.heightAnchor.constraint(equalToConstant: 22),

            textStack.leadingAnchor.constraint(
                equalTo: iconContainerView.trailingAnchor,
                constant: Layout.contentSpacing
            ),
            textStack.centerYAnchor.constraint(equalTo: actionButton.centerYAnchor),
            textStack.topAnchor.constraint(
                greaterThanOrEqualTo: actionButton.topAnchor,
                constant: Layout.verticalInset
            ),
            textStack.bottomAnchor.constraint(
                lessThanOrEqualTo: actionButton.bottomAnchor,
                constant: -Layout.verticalInset
            ),

            chevronContainerView.leadingAnchor.constraint(
                equalTo: textStack.trailingAnchor,
                constant: Layout.contentSpacing
            ),
            chevronContainerView.trailingAnchor.constraint(
                equalTo: actionButton.trailingAnchor,
                constant: -Layout.horizontalInset
            ),
            chevronContainerView.centerYAnchor.constraint(equalTo: actionButton.centerYAnchor),
            chevronContainerView.widthAnchor.constraint(equalToConstant: Layout.chevronSize),
            chevronContainerView.heightAnchor.constraint(equalToConstant: Layout.chevronSize),

            chevronImageView.centerXAnchor.constraint(equalTo: chevronContainerView.centerXAnchor),
            chevronImageView.centerYAnchor.constraint(equalTo: chevronContainerView.centerYAnchor),
            chevronImageView.widthAnchor.constraint(equalToConstant: 14),
            chevronImageView.heightAnchor.constraint(equalToConstant: 14)
        ])
    }

    private func applyRoundedClipping(cornerRadius: CGFloat) {
        actionButton.layer.cornerRadius = cornerRadius
        actionButton.layer.cornerCurve = .circular
        actionButton.layer.masksToBounds = true
        gradientBackdropView.cornerRadius = cornerRadius
        gradientBorderView.layer.cornerRadius = cornerRadius
        gradientBorderView.layer.cornerCurve = .circular
        gradientBorderView.layer.masksToBounds = true
    }
}

private final class SubscriptionPromoGradientView: UIView {
    private let gradientLayer = CAGradientLayer()

    var cornerRadius: CGFloat = 0 {
        didSet {
            layer.cornerRadius = cornerRadius
            gradientLayer.cornerRadius = cornerRadius
        }
    }

    var colors: [UIColor] = [] {
        didSet {
            gradientLayer.colors = colors.isEmpty ? nil : colors.map(\.cgColor)
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerCurve = .circular
        layer.masksToBounds = true
        gradientLayer.cornerCurve = .circular
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(gradientLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }
}
