import UIKit

struct TopicsPhysicsDescriptor {
    private static let introductoryThemeIDs = [
        "music", "technology", "history_culture", "politics_business"
    ]

    let theme: OnboardingTheme
    let spawnX: CGFloat
    let initialAngle: CGFloat
    let angularVelocity: CGFloat
    let horizontalVelocity: CGFloat
    let staticCenter: CGPoint
    let staticAngle: CGFloat

    static func make(from themes: [OnboardingTheme]) -> [TopicsPhysicsDescriptor] {
        let introductoryThemes = introductoryThemeIDs.flatMap { id in
            themes.filter { $0.id == id }
        }
        let additionalThemes = themes.filter { !introductoryThemeIDs.contains($0.id) }
        let orderedThemes = introductoryThemes + additionalThemes
        let columnCount = themes.count <= 4 ? 2 : 3
        let rowCount = max(Int(ceil(Double(themes.count) / Double(columnCount))), 1)
        let rowSpacing = min(0.22, 0.72 / CGFloat(max(rowCount - 1, 1)))

        return orderedThemes.enumerated().map { index, theme in
            let hash = stableHash(theme.id)
            let column = index % columnCount
            let row = index / columnCount
            let direction: CGFloat = index.isMultiple(of: 2) ? 1 : -1
            return TopicsPhysicsDescriptor(
                theme: theme,
                spawnX: 0.16 + CGFloat(hash % 69) / 100,
                initialAngle: direction * (0.06 + CGFloat(hash % 9) / 100),
                angularVelocity: direction * (0.14 + CGFloat(hash % 18) / 100),
                horizontalVelocity: -12 + CGFloat(hash % 25),
                staticCenter: CGPoint(
                    x: (CGFloat(column) + 0.5) / CGFloat(columnCount),
                    y: 0.91
                        - CGFloat(row) * rowSpacing
                        - CGFloat(column) * rowSpacing / 2
                ),
                staticAngle: direction * (0.025 + CGFloat(hash % 5) / 100)
            )
        }
    }

    private static func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(14_695_981_039_346_656_037) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}

enum OnboardingTopicSelectionAnimationTiming {
    static let selectionDuration: TimeInterval = 0.38
    static let iconDuration: TimeInterval = selectionDuration * 3
    static let iconSpringDamping: CGFloat = 0.86
}

final class PhysicsTopicCardView: UIControl {
    let theme: OnboardingTheme
    var themeID: String { theme.id }

    private let selectionOverlayView = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private var selectionState: Bool?

    init(theme: OnboardingTheme) {
        self.theme = theme
        super.init(frame: .zero)
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous

        selectionOverlayView.isUserInteractionEnabled = false
        selectionOverlayView.alpha = 0
        selectionOverlayView.accessibilityIdentifier = "onboardingTopicSelectionOverlay-\(theme.id)"
        addSubview(selectionOverlayView)

        iconView.contentMode = .scaleAspectFit
        iconView.isUserInteractionEnabled = false
        iconView.accessibilityIdentifier = "onboardingTopicIcon-\(theme.id)"
        addSubview(iconView)

        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.60
        titleLabel.allowsDefaultTighteningForTruncation = true
        titleLabel.isUserInteractionEnabled = false
        addSubview(titleLabel)

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityIdentifier = "onboardingTopic-\(theme.id)"
        accessibilityHint = L10n.Onboarding.topicsSelectionHint
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.78 : 1 }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        selectionOverlayView.frame = bounds
        selectionOverlayView.layer.cornerRadius = layer.cornerRadius
        selectionOverlayView.layer.cornerCurve = .continuous
        let inset: CGFloat = 13
        let iconSize: CGFloat = 25
        iconView.frame = CGRect(
            x: inset,
            y: (bounds.height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        let labelX = iconView.frame.maxX + 10
        titleLabel.frame = CGRect(
            x: labelX,
            y: 7,
            width: max(0, bounds.width - inset - labelX),
            height: bounds.height - 14
        )
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 22).cgPath
    }

    func preferredSize(maximumWidth: CGFloat) -> CGSize {
        let horizontalChrome: CGFloat = 13 + 25 + 10 + 13
        let titleWidth = titleLabel.sizeThatFits(
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: 68)
        ).width
        return CGSize(
            width: min(max(ceil(titleWidth) + horizontalChrome, 156), maximumWidth),
            height: 68
        )
    }

    func configure(appearance: AppAppearance, isSelected: Bool) {
        let tint = ThemeVisualCatalog.tintColor(for: theme)
        let selectionTint = appearance.designStyle == .radar
            ? appearance.accentColor
            : tint
        let textColor = appearance.themeCardTextColor(baseColor: tint)
        backgroundColor = appearance.themeCardBackground(baseColor: tint)

        iconView.image = ThemeVisualCatalog.logoImage(
            sfSymbolName: theme.sfSymbolName
        ) ?? UIImage(systemName: "questionmark.square.dashed")
        iconView.tintColor = appearance.themeCardIconColor(baseColor: tint)
        iconView.image = iconView.image?.withRenderingMode(.alwaysTemplate)

        titleLabel.text = theme.title
        titleLabel.font = appearance.typography.font(size: 15, weight: .semibold)
        titleLabel.textColor = textColor

        accessibilityLabel = theme.title
        accessibilityValue = isSelected ? L10n.Onboarding.topicsSelected : ""
        accessibilityTraits = isSelected ? [.button, .selected] : .button

        let previousSelection = selectionState
        selectionState = isSelected
        guard previousSelection != isSelected else { return }
        let usesMotionEmphasis = !UIAccessibility.isReduceMotionEnabled
        let applyCardSelection = { [self] in
            selectionOverlayView.backgroundColor = selectionTint.withAlphaComponent(
                appearance.designStyle == .clean ? 0.14 : 0.24
            )
            selectionOverlayView.alpha = isSelected ? 1 : 0
            layer.borderColor = (
                isSelected ? selectionTint : appearance.themeCardBorder(baseColor: tint)
            ).cgColor
            layer.borderWidth = isSelected
                ? max(appearance.themeCardBorderWidth + 1.5, 3)
                : max(appearance.themeCardBorderWidth, 1)
            titleLabel.transform = isSelected && usesMotionEmphasis
                ? CGAffineTransform(translationX: 2, y: 0)
                : .identity
            if isSelected {
                layer.shadowColor = selectionTint.cgColor
                layer.shadowOpacity = 0.52
                layer.shadowRadius = 15
                layer.shadowOffset = .zero
            } else {
                applyShadow(appearance.themeCardShadow)
            }
        }
        let applyIconSelection = { [self] in
            iconView.transform = isSelected && usesMotionEmphasis
                ? CGAffineTransform(scaleX: 1.18, y: 1.18)
                : .identity
        }

        guard
            previousSelection != nil,
            UIView.areAnimationsEnabled
        else {
            applyCardSelection()
            applyIconSelection()
            return
        }

        if UIAccessibility.isReduceMotionEnabled {
            UIView.animate(
                withDuration: 0.18,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState],
                animations: {
                    applyCardSelection()
                    applyIconSelection()
                }
            )
        } else {
            UIView.animate(
                withDuration: OnboardingTopicSelectionAnimationTiming.selectionDuration,
                delay: 0,
                usingSpringWithDamping: isSelected ? 0.72 : 1,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: applyCardSelection
            )
            UIView.animate(
                withDuration: OnboardingTopicSelectionAnimationTiming.iconDuration,
                delay: 0,
                usingSpringWithDamping: OnboardingTopicSelectionAnimationTiming.iconSpringDamping,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: applyIconSelection
            )
        }
    }
}
