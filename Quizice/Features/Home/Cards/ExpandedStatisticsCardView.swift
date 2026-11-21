import UIKit

final class ExpandedStatisticsCardView: UIView {
    private enum AccessibilityID {
        static let root = "expandedStatisticsCardView"
        static let closeButton = "expandedStatisticsCardCloseButton"
        static let title = "expandedStatisticsCardTitle"
        static let subtitle = "expandedStatisticsCardSubtitle"
        static let emptyState = "expandedStatisticsCardEmptyState"
        static let scrollView = "expandedStatisticsCardScrollView"
    }

    fileprivate enum Layout {
        static let edgeInset: CGFloat = 20
        static let controlInset: CGFloat = 16
        static let closeButtonSize: CGFloat = 44
        static let titleTopInset: CGFloat = 20
        static let titleToSubtitleSpacing: CGFloat = 8
        static let subtitleToRowsSpacing: CGFloat = 16
        static let rowSpacing: CGFloat = 12
        static let rowHorizontalInset: CGFloat = 16
        static let rowVerticalInset: CGFloat = 14
        static let rowValueSpacing: CGFloat = 12
        static let rowMinimumHeight: CGFloat = 64
    }

    fileprivate enum Typography {
        static let titleSize: CGFloat = 30
        static let subtitleSize: CGFloat = 16
        static let emptyStateSize: CGFloat = 15
        static let rowTitleSize: CGFloat = 17
        static let rowValueSize: CGFloat = 24
    }

    var onClose: (() -> Void)?
    var onAccessibilityEscape: (() -> Void)?
    var initialFocusView: UIView { titleLabel }

    private let surfaceView = UIView()
    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let scrollView = UIScrollView()
    private let contentStackView = UIStackView()
    private let emptyStateLabel = UILabel()
    let chartsView = StatisticsChartsView()
    private var metricRows: [StatisticsPresentation.MetricID: StatisticsMetricRowView] = [:]
    private var configuredShadow = AppShadowStyle.none
    private var surfaceStyle: AppSurfaceStyle?
    private var isTransitionSurfaceHidden = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureHierarchy()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let cornerRadius = surfaceStyle?.cornerRadius ?? 0
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: cornerRadius
        ).cgPath
    }

    func configure(summary: StatisticsSummary, appearance: AppAppearance) {
        let presentation = StatisticsPresentation(summary: summary)
        surfaceStyle = appearance.card
        configuredShadow = appearance.card.shadow
        applyConfiguredSurfaceStyle(appearance.card)

        titleLabel.text = L10n.Statistics.title
        titleLabel.textColor = appearance.surfaceTextColor
        titleLabel.font = appearance.typography.font(size: Typography.titleSize, weight: .bold)
        subtitleLabel.text = presentation.subtitle
        subtitleLabel.textColor = appearance.secondarySurfaceTextColor
        subtitleLabel.font = appearance.typography.font(size: Typography.subtitleSize, weight: .medium)
        emptyStateLabel.text = presentation.emptyStateText ?? L10n.Statistics.emptyStateText
        emptyStateLabel.textColor = appearance.secondarySurfaceTextColor
        emptyStateLabel.font = appearance.typography.font(size: Typography.emptyStateSize, weight: .regular)
        emptyStateLabel.isHidden = presentation.emptyStateText == nil

        for metric in presentation.metrics {
            metricRows[metric.id]?.configure(metric: metric, appearance: appearance)
        }

        closeButton.applyActionAppearance(appearance.iconButton, appearance: appearance)
        closeButton.tintColor = appearance.surfaceTextColor
        accessibilityLabel = L10n.Statistics.accessibilityLabel
        var accessibilityItems: [Any] = [
            titleLabel,
            subtitleLabel,
            emptyStateLabel
        ]
        accessibilityItems.append(contentsOf: presentation.metrics.compactMap { metricRows[$0.id] })
        accessibilityItems.append(chartsView)
        accessibilityItems.append(closeButton)
        accessibilityElements = accessibilityItems
        setTransitionSurfaceHidden(false)
        setTransitionShadowHidden(false)
    }

    func setTransitionShadowHidden(_ isHidden: Bool) {
        applyShadow(isHidden ? .none : configuredShadow)
    }

    func setTransitionSurfaceHidden(_ isHidden: Bool) {
        isTransitionSurfaceHidden = isHidden
        applyConfiguredSurfaceStyle()
    }

    override func accessibilityPerformEscape() -> Bool {
        if let onAccessibilityEscape {
            onAccessibilityEscape()
            return true
        }
        guard let onClose else { return false }
        onClose()
        return true
    }

    private func configureHierarchy() {
        backgroundColor = .clear
        accessibilityIdentifier = AccessibilityID.root
        accessibilityViewIsModal = true
        isAccessibilityElement = false
        clipsToBounds = false

        surfaceView.translatesAutoresizingMaskIntoConstraints = false
        surfaceView.layer.masksToBounds = true
        addSubview(surfaceView)

        closeButton.accessibilityIdentifier = AccessibilityID.closeButton
        closeButton.accessibilityLabel = L10n.ThemeCard.closeAccessibilityLabel
        closeButton.setImage(
            UIImage(
                systemName: "xmark",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
            ),
            for: .normal
        )
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.installPressFeedback()

        configureLabel(
            titleLabel,
            accessibilityIdentifier: AccessibilityID.title,
            numberOfLines: 2,
            textAlignment: .left
        )
        configureLabel(
            subtitleLabel,
            accessibilityIdentifier: AccessibilityID.subtitle,
            numberOfLines: 0,
            textAlignment: .left
        )
        configureLabel(
            emptyStateLabel,
            accessibilityIdentifier: AccessibilityID.emptyState,
            numberOfLines: 0,
            textAlignment: .center
        )

        scrollView.accessibilityIdentifier = AccessibilityID.scrollView
        scrollView.alwaysBounceVertical = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        contentStackView.axis = .vertical
        contentStackView.spacing = Layout.rowSpacing
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.addArrangedSubview(emptyStateLabel)

        for id in [
            StatisticsPresentation.MetricID.playedQuizzes,
            .correctAnswers,
            .percentage,
            .bestResult
        ] {
            let row = StatisticsMetricRowView()
            metricRows[id] = row
            contentStackView.addArrangedSubview(row)
        }

        contentStackView.addArrangedSubview(chartsView)

        surfaceView.addSubview(titleLabel)
        surfaceView.addSubview(subtitleLabel)
        surfaceView.addSubview(scrollView)
        surfaceView.addSubview(closeButton)
        scrollView.addSubview(contentStackView)

        NSLayoutConstraint.activate([
            surfaceView.leadingAnchor.constraint(equalTo: leadingAnchor),
            surfaceView.trailingAnchor.constraint(equalTo: trailingAnchor),
            surfaceView.topAnchor.constraint(equalTo: topAnchor),
            surfaceView.bottomAnchor.constraint(equalTo: bottomAnchor),

            closeButton.topAnchor.constraint(equalTo: surfaceView.topAnchor, constant: Layout.controlInset),
            closeButton.trailingAnchor.constraint(equalTo: surfaceView.trailingAnchor, constant: -Layout.controlInset),
            closeButton.widthAnchor.constraint(equalToConstant: Layout.closeButtonSize),
            closeButton.heightAnchor.constraint(equalToConstant: Layout.closeButtonSize),

            titleLabel.topAnchor.constraint(equalTo: surfaceView.topAnchor, constant: Layout.titleTopInset),
            titleLabel.leadingAnchor.constraint(equalTo: surfaceView.leadingAnchor, constant: Layout.edgeInset),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -8),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Layout.titleToSubtitleSpacing),
            subtitleLabel.leadingAnchor.constraint(equalTo: surfaceView.leadingAnchor, constant: Layout.edgeInset),
            subtitleLabel.trailingAnchor.constraint(equalTo: surfaceView.trailingAnchor, constant: -Layout.edgeInset),

            scrollView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: Layout.subtitleToRowsSpacing),
            scrollView.leadingAnchor.constraint(equalTo: surfaceView.leadingAnchor, constant: Layout.edgeInset),
            scrollView.trailingAnchor.constraint(equalTo: surfaceView.trailingAnchor, constant: -Layout.edgeInset),
            scrollView.bottomAnchor.constraint(equalTo: surfaceView.bottomAnchor, constant: -Layout.edgeInset),

            contentStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    private func applyConfiguredSurfaceStyle(_ style: AppSurfaceStyle) {
        surfaceStyle = style
        applyConfiguredSurfaceStyle()
    }

    private func applyConfiguredSurfaceStyle() {
        guard let style = surfaceStyle else { return }
        surfaceView.backgroundColor = isTransitionSurfaceHidden ? .clear : style.backgroundColor
        surfaceView.layer.cornerRadius = style.cornerRadius
        surfaceView.layer.cornerCurve = .continuous
        surfaceView.layer.borderWidth = isTransitionSurfaceHidden ? 0 : style.borderWidth
        surfaceView.layer.borderColor = isTransitionSurfaceHidden
            ? UIColor.clear.cgColor
            : style.borderColor.cgColor
        setNeedsLayout()
    }

    private func configureLabel(
        _ label: UILabel,
        accessibilityIdentifier: String,
        numberOfLines: Int,
        textAlignment: NSTextAlignment
    ) {
        label.accessibilityIdentifier = accessibilityIdentifier
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = numberOfLines
        label.textAlignment = textAlignment
        label.translatesAutoresizingMaskIntoConstraints = false
    }

    @objc private func closeTapped() {
        onClose?()
    }
}

private final class StatisticsMetricRowView: UIView {
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureHierarchy()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(metric: StatisticsPresentation.Metric, appearance: AppAppearance) {
        accessibilityIdentifier = "expandedStatisticsMetric-\(metric.id.rawValue)"
        accessibilityLabel = metric.title
        accessibilityValue = metric.value
        titleLabel.text = metric.title
        titleLabel.textColor = appearance.secondarySurfaceTextColor
        titleLabel.font = appearance.typography.font(
            size: ExpandedStatisticsCardView.Typography.rowTitleSize,
            weight: .medium
        )
        valueLabel.text = metric.value
        valueLabel.textColor = appearance.surfaceTextColor
        valueLabel.font = appearance.typography.font(
            size: ExpandedStatisticsCardView.Typography.rowValueSize,
            weight: .bold
        )
        applySurfaceStyle(appearance.row)
    }

    private func configureHierarchy() {
        isAccessibilityElement = true
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.75
        valueLabel.numberOfLines = 1
        valueLabel.textAlignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(valueLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: ExpandedStatisticsCardView.Layout.rowMinimumHeight),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ExpandedStatisticsCardView.Layout.rowHorizontalInset),
            titleLabel.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: ExpandedStatisticsCardView.Layout.rowVerticalInset),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -ExpandedStatisticsCardView.Layout.rowVerticalInset),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: valueLabel.leadingAnchor, constant: -ExpandedStatisticsCardView.Layout.rowValueSpacing),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ExpandedStatisticsCardView.Layout.rowHorizontalInset),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}
