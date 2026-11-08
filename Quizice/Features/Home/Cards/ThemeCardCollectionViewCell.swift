import UIKit

@MainActor
enum ThemeCardLayoutMetrics {
    static let horizontalInset: CGFloat = 12
    static let stackedLeadingInset: CGFloat = 16
    static let iconSize: CGFloat = 32
    static let iconTitleSpacing: CGFloat = 8
    static let verticalInset: CGFloat = 8
    static let titleFontSize: CGFloat = 16
    static let maximumTitleLines = 0
    static let singleLineHeight: CGFloat = 64

    struct Grid {
        let columnCount: Int
        let cardWidth: CGFloat
        let stacksContent: Bool
        let font: UIFont

        var textWidth: CGFloat {
            let leadingInset = stacksContent ? stackedLeadingInset : horizontalInset
            return max(cardWidth - leadingInset - horizontalInset - (stacksContent ? 0 : iconSize + iconTitleSpacing), 1)
        }

        func rowHeight(titles: [String]) -> CGFloat {
            let measuringLabel = UILabel()
            measuringLabel.font = font
            measuringLabel.numberOfLines = maximumTitleLines
            measuringLabel.lineBreakMode = .byWordWrapping
            measuringLabel.allowsDefaultTighteningForTruncation = false
            let textHeight = titles.map {
                measuringLabel.text = $0
                return ceil(measuringLabel.sizeThatFits(
                    CGSize(width: textWidth, height: .greatestFiniteMagnitude)
                ).height)
            }.max() ?? font.lineHeight
            let contentHeight = stacksContent
                ? iconSize + iconTitleSpacing + textHeight
                : max(iconSize, textHeight)
            return max(singleLineHeight, contentHeight + verticalInset * 2)
        }
    }

    static func grid(
        titles: [String], width: CGFloat, spacing: CGFloat,
        font: UIFont, traitCollection: UITraitCollection, preferredColumnCount: Int = 2
    ) -> Grid {
        let widestWord = titles.flatMap { $0.split(whereSeparator: \.isWhitespace) }
            .map { ceil((String($0) as NSString).size(withAttributes: [.font: font]).width) }
            .max() ?? 0
        var columnCount = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
            ? 1 : max(1, preferredColumnCount)
        func widthForColumns(_ count: Int) -> CGFloat {
            floor((width - spacing * CGFloat(count - 1)) / CGFloat(count))
        }
        while columnCount > 1,
              widestWord > widthForColumns(columnCount) - stackedLeadingInset - horizontalInset {
            columnCount -= 1
        }
        let cardWidth = widthForColumns(columnCount)
        let stacksContent = widestWord > cardWidth - horizontalInset * 2 - iconSize - iconTitleSpacing
        let leadingInset = stacksContent ? stackedLeadingInset : horizontalInset
        let textWidth = max(cardWidth - leadingInset - horizontalInset - (stacksContent ? 0 : iconSize + iconTitleSpacing), 1)
        // Only fit an unbreakable word after giving it the full card width.
        // Keep the user's enlarged type everywhere that it fits naturally.
        let fittedFont = widestWord > textWidth
            ? font.withSize(max(min(titleFontSize, font.pointSize), font.pointSize * textWidth / widestWord))
            : font
        return Grid(
            columnCount: columnCount, cardWidth: cardWidth,
            stacksContent: stacksContent, font: fittedFont
        )
    }
}

final class ThemeCardCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "homeThemeCardCell"

    let actionButton = UIButton(type: .custom)

    private let themeIconSlotView = UIView()
    private let themeIconShadowView = UIImageView()
    private let themeImageView = UIImageView()
    private let themeTitleLabel = UILabel()
    private var horizontalContentConstraints: [NSLayoutConstraint] = []
    private var stackedContentConstraints: [NSLayoutConstraint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViewHierarchy()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: actionButton.layer.cornerRadius
        ).cgPath
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        actionButton.removeTarget(nil, action: nil, for: .allEvents)
        actionButton.accessibilityIdentifier = nil
        actionButton.accessibilityLabel = nil
        actionButton.accessibilityHint = nil
        actionButton.backgroundColor = .clear
        actionButton.layer.cornerRadius = 0
        actionButton.layer.borderWidth = 0
        actionButton.layer.borderColor = nil
        actionButton.isHidden = false
        actionButton.isEnabled = true
        actionButton.isUserInteractionEnabled = true
        actionButton.accessibilityElementsHidden = false
        actionButton.alpha = 1
        actionButton.transform = .identity

        themeImageView.image = nil
        themeImageView.tintColor = nil
        themeImageView.transform = .identity
        themeImageView.accessibilityIdentifier = nil

        themeIconShadowView.image = nil
        themeIconShadowView.tintColor = nil
        themeIconShadowView.alpha = 1
        themeIconShadowView.transform = .identity

        themeTitleLabel.text = nil
        themeTitleLabel.textColor = nil
        themeTitleLabel.accessibilityIdentifier = nil

        contentView.backgroundColor = .clear
        backgroundColor = .clear
        applyShadow(.none)
    }

    func configure(
        theme: QuizTheme, appearance: AppAppearance, isSourceHidden: Bool,
        grid: ThemeCardLayoutMetrics.Grid? = nil
    ) {
        let themeID = theme.stableID
        let tintColor = ThemeVisualCatalog.tintColor(for: theme)
        let borderColor = appearance.themeCardBorder(baseColor: tintColor)

        contentView.backgroundColor = .clear
        contentView.clipsToBounds = false
        backgroundColor = .clear
        layer.masksToBounds = false
        applyShadow(.none)

        actionButton.accessibilityIdentifier = themeID
        actionButton.accessibilityLabel = L10n.ThemeCard.accessibilityLabel(themeName: theme.theme)
        actionButton.accessibilityHint = L10n.ThemeCard.accessibilityHint
        actionButton.backgroundColor = appearance.themeCardBackground(baseColor: tintColor)
        actionButton.layer.cornerRadius = appearance.themeCardCornerRadius
        actionButton.layer.borderWidth = appearance.themeCardBorderWidth
        actionButton.layer.borderColor = borderColor.cgColor
        actionButton.layer.masksToBounds = true

        let isSymbolIcon = appearance.designStyle != .radar
        let logoImage = ThemeVisualCatalog.logoImage(
            sfSymbolName: theme.sfSymbolName
        )
        themeImageView.image = logoImage
        themeImageView.tintColor = appearance.themeCardIconColor(baseColor: tintColor)
        themeImageView.transform = .identity
        themeImageView.accessibilityIdentifier = "\(ThemesCollectionService.Content.themeImageAccessibilityIDPrefix)-\(themeID)"

        themeIconShadowView.image = isSymbolIcon ? logoImage : nil
        themeIconShadowView.tintColor = AppAssetColor.black.uiColor
        themeIconShadowView.alpha = isSymbolIcon ? ThemeIconVisualStyle.shadowAlpha : 0
        themeIconShadowView.transform = isSymbolIcon
            ? CGAffineTransform(translationX: 0, y: ThemeIconVisualStyle.shadowOffset)
            : .identity

        themeTitleLabel.font = grid?.font ?? appearance.typography.font(
            size: ThemeCardLayoutMetrics.titleFontSize,
            weight: .semibold,
            compatibleWith: traitCollection
        )
        themeTitleLabel.text = theme.theme
        themeTitleLabel.textColor = appearance.themeCardTextColor(baseColor: tintColor)
        themeTitleLabel.accessibilityIdentifier = "\(ThemesCollectionService.Content.themeTitleAccessibilityIDPrefix)-\(themeID)"
        NSLayoutConstraint.deactivate(horizontalContentConstraints + stackedContentConstraints)
        NSLayoutConstraint.activate(grid?.stacksContent == true
            ? stackedContentConstraints : horizontalContentConstraints)

        setSourceHidden(isSourceHidden)
    }

    func makeTransitionContent() -> (view: UIView, geometry: HomeThemeCardContentGeometry) {
        layoutIfNeeded()
        actionButton.layoutIfNeeded()

        let containerView = UIView(frame: actionButton.bounds)
        containerView.backgroundColor = .clear
        containerView.isAccessibilityElement = false
        containerView.accessibilityElementsHidden = true
        containerView.isUserInteractionEnabled = false

        let imageCenter = themeImageView.convert(
            CGPoint(x: themeImageView.bounds.midX, y: themeImageView.bounds.midY),
            to: actionButton
        )
        let shadowCenter = themeIconShadowView.convert(
            CGPoint(x: themeIconShadowView.bounds.midX, y: themeIconShadowView.bounds.midY),
            to: actionButton
        )
        let imageView = UIImageView(image: themeImageView.image)
        imageView.bounds = themeImageView.bounds
        imageView.center = imageCenter
        imageView.transform = themeImageView.transform
        imageView.alpha = themeImageView.alpha
        imageView.contentMode = themeImageView.contentMode
        imageView.tintColor = themeImageView.tintColor
        imageView.clipsToBounds = themeImageView.clipsToBounds

        let titleLabel = UILabel()
        titleLabel.bounds = themeTitleLabel.bounds
        titleLabel.center = themeTitleLabel.center
        titleLabel.transform = themeTitleLabel.transform
        titleLabel.alpha = themeTitleLabel.alpha
        titleLabel.text = themeTitleLabel.text
        titleLabel.attributedText = themeTitleLabel.attributedText
        titleLabel.font = themeTitleLabel.font
        titleLabel.textColor = themeTitleLabel.textColor
        titleLabel.textAlignment = themeTitleLabel.textAlignment
        titleLabel.numberOfLines = themeTitleLabel.numberOfLines
        titleLabel.lineBreakMode = themeTitleLabel.lineBreakMode
        titleLabel.allowsDefaultTighteningForTruncation = themeTitleLabel.allowsDefaultTighteningForTruncation

        if themeIconShadowView.image != nil {
            let shadowImageView = UIImageView(image: themeIconShadowView.image)
            shadowImageView.bounds = themeIconShadowView.bounds
            shadowImageView.center = shadowCenter
            shadowImageView.transform = themeIconShadowView.transform
            shadowImageView.alpha = themeIconShadowView.alpha
            shadowImageView.contentMode = themeIconShadowView.contentMode
            shadowImageView.tintColor = themeIconShadowView.tintColor
            shadowImageView.clipsToBounds = themeIconShadowView.clipsToBounds
            containerView.addSubview(shadowImageView)
        }
        containerView.addSubview(imageView)
        containerView.addSubview(titleLabel)
        return (
            view: containerView,
            geometry: HomeThemeCardContentGeometry(
                containerSize: actionButton.bounds.size,
                imageCenter: imageCenter,
                titleCenter: themeTitleLabel.center
            )
        )
    }

    private func configureViewHierarchy() {
        contentView.backgroundColor = .clear
        contentView.clipsToBounds = false
        backgroundColor = .clear
        layer.masksToBounds = false

        actionButton.clipsToBounds = true
        actionButton.translatesAutoresizingMaskIntoConstraints = false

        themeIconSlotView.backgroundColor = .clear
        themeIconSlotView.isAccessibilityElement = false
        themeIconSlotView.isUserInteractionEnabled = false
        themeIconSlotView.translatesAutoresizingMaskIntoConstraints = false

        themeIconShadowView.contentMode = .scaleAspectFit
        themeIconShadowView.isAccessibilityElement = false
        themeIconShadowView.isUserInteractionEnabled = false
        themeIconShadowView.translatesAutoresizingMaskIntoConstraints = false

        themeImageView.contentMode = .scaleAspectFit
        themeImageView.isAccessibilityElement = false
        themeImageView.isUserInteractionEnabled = false
        themeImageView.translatesAutoresizingMaskIntoConstraints = false

        themeTitleLabel.adjustsFontForContentSizeCategory = true
        themeTitleLabel.textAlignment = .left
        themeTitleLabel.numberOfLines = ThemeCardLayoutMetrics.maximumTitleLines
        themeTitleLabel.lineBreakMode = .byWordWrapping
        themeTitleLabel.allowsDefaultTighteningForTruncation = false
        themeTitleLabel.isAccessibilityElement = false
        themeTitleLabel.isUserInteractionEnabled = false
        themeTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(actionButton)
        actionButton.addSubview(themeIconSlotView)
        themeIconSlotView.addSubview(themeIconShadowView)
        themeIconSlotView.addSubview(themeImageView)
        actionButton.addSubview(themeTitleLabel)

        horizontalContentConstraints = [
            themeIconSlotView.leadingAnchor.constraint(
                equalTo: actionButton.leadingAnchor,
                constant: ThemeCardLayoutMetrics.horizontalInset
            ),
            themeTitleLabel.leadingAnchor.constraint(
                equalTo: themeIconSlotView.trailingAnchor,
                constant: ThemeCardLayoutMetrics.iconTitleSpacing
            ),
            themeTitleLabel.centerYAnchor.constraint(equalTo: actionButton.centerYAnchor),
            themeIconSlotView.centerYAnchor.constraint(equalTo: actionButton.centerYAnchor)
        ]
        stackedContentConstraints = [
            themeIconSlotView.leadingAnchor.constraint(
                equalTo: actionButton.leadingAnchor,
                constant: ThemeCardLayoutMetrics.stackedLeadingInset
            ),
            themeTitleLabel.leadingAnchor.constraint(
                equalTo: actionButton.leadingAnchor,
                constant: ThemeCardLayoutMetrics.stackedLeadingInset
            ),
            themeTitleLabel.topAnchor.constraint(
                equalTo: themeIconSlotView.bottomAnchor,
                constant: ThemeCardLayoutMetrics.iconTitleSpacing
            ),
            themeIconSlotView.topAnchor.constraint(
                equalTo: actionButton.topAnchor,
                constant: ThemeCardLayoutMetrics.verticalInset
            )
        ]
        NSLayoutConstraint.activate(horizontalContentConstraints + [
            actionButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            actionButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            actionButton.topAnchor.constraint(equalTo: contentView.topAnchor),
            actionButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            themeTitleLabel.trailingAnchor.constraint(
                equalTo: actionButton.trailingAnchor,
                constant: -ThemeCardLayoutMetrics.horizontalInset
            ),
            themeTitleLabel.topAnchor.constraint(
                greaterThanOrEqualTo: actionButton.topAnchor,
                constant: ThemeCardLayoutMetrics.verticalInset
            ),
            themeTitleLabel.bottomAnchor.constraint(
                lessThanOrEqualTo: actionButton.bottomAnchor,
                constant: -ThemeCardLayoutMetrics.verticalInset
            ),

            themeIconSlotView.widthAnchor.constraint(equalToConstant: ThemeCardLayoutMetrics.iconSize),
            themeIconSlotView.heightAnchor.constraint(equalToConstant: ThemeCardLayoutMetrics.iconSize),

            themeIconShadowView.leadingAnchor.constraint(equalTo: themeIconSlotView.leadingAnchor),
            themeIconShadowView.trailingAnchor.constraint(equalTo: themeIconSlotView.trailingAnchor),
            themeIconShadowView.topAnchor.constraint(equalTo: themeIconSlotView.topAnchor),
            themeIconShadowView.bottomAnchor.constraint(equalTo: themeIconSlotView.bottomAnchor),

            themeImageView.leadingAnchor.constraint(equalTo: themeIconSlotView.leadingAnchor),
            themeImageView.trailingAnchor.constraint(equalTo: themeIconSlotView.trailingAnchor),
            themeImageView.topAnchor.constraint(equalTo: themeIconSlotView.topAnchor),
            themeImageView.bottomAnchor.constraint(equalTo: themeIconSlotView.bottomAnchor)
        ])
    }

    private func setSourceHidden(_ isHidden: Bool) {
        actionButton.isHidden = isHidden
        actionButton.isUserInteractionEnabled = !isHidden
        actionButton.accessibilityElementsHidden = isHidden
        if isHidden {
            layer.shadowOpacity = 0
        }
    }
}
