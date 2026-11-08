import UIKit

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

final class InsetLabel: UILabel {
    private let contentInsets: UIEdgeInsets

    init(contentInsets: UIEdgeInsets) {
        self.contentInsets = contentInsets
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + contentInsets.left + contentInsets.right,
            height: size.height + contentInsets.top + contentInsets.bottom
        )
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: contentInsets))
    }
}

final class GradientBorderView: UIView {
    private let gradientLayer = CAGradientLayer()
    private let borderMaskLayer = CAShapeLayer()
    private let lineWidth: CGFloat
    private let cornerRadius: CGFloat?

    init(colors: [UIColor], lineWidth: CGFloat, cornerRadius: CGFloat? = nil) {
        self.lineWidth = lineWidth
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        gradientLayer.colors = colors.map(\.cgColor)
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.mask = borderMaskLayer
        layer.addSublayer(gradientLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds

        let cornerRadius = cornerRadius ?? superview?.layer.cornerRadius ?? layer.cornerRadius
        let innerBounds = bounds.insetBy(dx: lineWidth, dy: lineWidth)
        let borderPath = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius)
        borderPath.append(
            UIBezierPath(
                roundedRect: innerBounds,
                cornerRadius: max(cornerRadius - lineWidth, 0)
            )
        )

        borderMaskLayer.frame = bounds
        borderMaskLayer.fillColor = AppAssetColor.black.uiColor.cgColor
        borderMaskLayer.fillRule = .evenOdd
        borderMaskLayer.strokeColor = nil
        borderMaskLayer.lineWidth = 0
        borderMaskLayer.path = borderPath.cgPath
    }
}

final class MoreThemesFadeButton: UIControl {
    private enum Layout {
        static let chevronSize: CGFloat = 18
        static let chevronSpacing: CGFloat = 8
        static let titleCenterOffset: CGFloat = -11
        static let contentBottomInset: CGFloat = 18
    }

    private enum Animation {
        static let visibilityDuration: TimeInterval = 0.20
    }

    private let titleLabel = UILabel()
    private let chevronView = UIImageView()
    private var visibilityAnimator: UIViewPropertyAnimator?
    private var isVisibilityTargetVisible = true

    override init(frame: CGRect) {
        super.init(frame: frame)

        isAccessibilityElement = true
        clipsToBounds = true
        isOpaque = false
        layer.isOpaque = false
        layer.zPosition = 1_000

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.adjustsFontForContentSizeCategory = true
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        chevronView.contentMode = .scaleAspectFit

        addSubview(titleLabel)
        addSubview(chevronView)
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(
                equalTo: centerXAnchor,
                constant: Layout.titleCenterOffset
            ),
            titleLabel.centerYAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -Layout.contentBottomInset
            ),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            chevronView.leadingAnchor.constraint(
                equalTo: titleLabel.trailingAnchor,
                constant: Layout.chevronSpacing
            ),
            chevronView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            chevronView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            chevronView.widthAnchor.constraint(equalToConstant: Layout.chevronSize),
            chevronView.heightAnchor.constraint(equalToConstant: Layout.chevronSize)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(
                withDuration: 0.16,
                delay: 0,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.titleLabel.alpha = self.isHighlighted ? 0.62 : 1
                self.chevronView.alpha = self.isHighlighted ? 0.62 : 1
            }
        }
    }

    override func accessibilityActivate() -> Bool {
        guard isVisibilityTargetVisible else { return false }
        sendActions(for: .touchUpInside)
        return true
    }

    func configure(appearance: AppAppearance) {
        accessibilityIdentifier = ThemesCollectionService.Content.moreThemesAccessibilityID
        accessibilityLabel = L10n.Home.moreThemes
        accessibilityHint = L10n.Home.moreThemesAccessibilityHint
        accessibilityTraits = .button

        titleLabel.text = L10n.Home.moreThemes
        titleLabel.textColor = appearance.screenTextColor
        titleLabel.font = appearance.typography.font(size: 17, weight: .semibold)
        chevronView.image = UIImage(
            systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: Layout.chevronSize,
                weight: .bold
            )
        )
        chevronView.tintColor = appearance.screenTextColor
    }

    func setVisible(_ isVisible: Bool, animated: Bool) {
        guard isVisibilityTargetVisible != isVisible else { return }
        isVisibilityTargetVisible = isVisible

        visibilityAnimator?.stopAnimation(false)
        visibilityAnimator?.finishAnimation(at: .current)

        if isVisible {
            isHidden = false
        }

        guard animated else {
            alpha = isVisible ? 1 : 0
            isHidden = !isVisible
            return
        }

        let animator = UIViewPropertyAnimator(
            duration: Animation.visibilityDuration,
            curve: .easeInOut
        ) {
            self.alpha = isVisible ? 1 : 0
        }
        animator.addCompletion { [weak self] _ in
            guard
                let self,
                self.isVisibilityTargetVisible == isVisible
            else { return }
            self.isHidden = !isVisible
            self.visibilityAnimator = nil
        }
        visibilityAnimator = animator
        animator.startAnimation()
    }
}

final class ThemesViewportCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "homeThemesViewportCell"

    let themesCollectionView: HomeThemesCollectionView
    private var lastCatalogWidth: CGFloat = 0

    override init(frame: CGRect) {
        let layout = HomeThemesCollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 16
        layout.minimumInteritemSpacing = 16
        layout.sectionInset = .zero

        themesCollectionView = HomeThemesCollectionView(
            frame: .zero,
            collectionViewLayout: layout
        )
        super.init(frame: frame)

        backgroundColor = .clear
        isOpaque = false
        layer.isOpaque = false
        contentView.backgroundColor = .clear
        contentView.isOpaque = false
        contentView.layer.isOpaque = false
        contentView.clipsToBounds = true

        themesCollectionView.backgroundColor = .clear
        themesCollectionView.backgroundView = nil
        themesCollectionView.isOpaque = false
        themesCollectionView.layer.isOpaque = false
        themesCollectionView.accessibilityIdentifier =
            ThemesCollectionService.Content.themeCatalogAccessibilityID
        themesCollectionView.accessibilityLabel = L10n.Home.themesCollectionAccessibilityLabel
        themesCollectionView.alwaysBounceVertical = true
        themesCollectionView.bounces = true
        themesCollectionView.canCancelContentTouches = true
        themesCollectionView.contentInsetAdjustmentBehavior = .never
        themesCollectionView.delaysContentTouches = true
        themesCollectionView.isDirectionalLockEnabled = true
        themesCollectionView.showsVerticalScrollIndicator = false
        themesCollectionView.translatesAutoresizingMaskIntoConstraints = false
        themesCollectionView.register(
            ThemeCardCollectionViewCell.self,
            forCellWithReuseIdentifier: ThemeCardCollectionViewCell.reuseIdentifier
        )

        contentView.addSubview(themesCollectionView)
        NSLayoutConstraint.activate([
            themesCollectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            themesCollectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            themesCollectionView.topAnchor.constraint(equalTo: contentView.topAnchor),
            themesCollectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = themesCollectionView.bounds.width
        guard width > 0, width != lastCatalogWidth else { return }
        lastCatalogWidth = width
        themesCollectionView.reloadData()
    }

    func configure(
        dataSource: UICollectionViewDataSource,
        delegate: UICollectionViewDelegate,
        canScroll: Bool
    ) {
        themesCollectionView.dataSource = dataSource
        themesCollectionView.delegate = delegate
        themesCollectionView.isScrollEnabled = canScroll
        themesCollectionView.alwaysBounceVertical = canScroll
        themesCollectionView.bounces = canScroll
        themesCollectionView.reloadData()
    }
}

// Keep the row full-width so the outer flow layout never places actions side by side.
extension UIView {
    func constrainHomeActionWidth(in container: UIView) {
        let preferredWidth = widthAnchor.constraint(equalTo: container.widthAnchor)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            centerXAnchor.constraint(equalTo: container.centerXAnchor),
            widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor),
            widthAnchor.constraint(lessThanOrEqualToConstant: 640),
            preferredWidth
        ])
    }
}
