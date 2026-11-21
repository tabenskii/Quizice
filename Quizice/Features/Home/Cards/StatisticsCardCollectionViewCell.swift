import UIKit

final class StatisticsCardCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "homeStatisticsCardCell"

    private enum Layout {
        static let bottomInset: CGFloat = 24
        static let horizontalInset: CGFloat = 24
        static let contentSpacing: CGFloat = 12
        static let textSpacing: CGFloat = 6
        static let metricsSpacing: CGFloat = 8
        static let metricSpacing: CGFloat = 6
    }

    private enum Typography {
        static let titleSize: CGFloat = 24
        static let descriptionSize: CGFloat = 15
        static let metricTitleSize: CGFloat = 14
        static let metricValueSize: CGFloat = 18
        static let titleMinimumScaleFactor: CGFloat = 0.72
    }

    let actionButton = UIButton(type: .system)

    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let playedTitleLabel = UILabel()
    private let playedValueLabel = UILabel()
    private let accuracyTitleLabel = UILabel()
    private let accuracyValueLabel = UILabel()
    private let textStackView = UIStackView()
    private let playedMetricView = UIStackView()
    private let accuracyMetricView = UIStackView()
    private let metricsStackView = UIStackView()
    private let contentStackView = UIStackView()
    private var descriptionMinimumHeightConstraint: NSLayoutConstraint?

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
        actionButton.isHidden = false
        actionButton.isEnabled = true
        actionButton.isUserInteractionEnabled = true
        actionButton.accessibilityElementsHidden = false
        actionButton.alpha = 1
        actionButton.transform = .identity
        actionButton.backgroundColor = .clear
        actionButton.layer.borderColor = nil
        actionButton.layer.borderWidth = 0
        actionButton.layer.cornerRadius = 0
        actionButton.layer.cornerCurve = .circular
        actionButton.accessibilityIdentifier = nil
        actionButton.accessibilityLabel = nil
        actionButton.accessibilityHint = nil
        actionButton.accessibilityValue = nil
        [titleLabel, descriptionLabel, playedTitleLabel, playedValueLabel, accuracyTitleLabel, accuracyValueLabel]
            .forEach { label in
                label.text = nil
                label.textColor = nil
            }
        contentView.backgroundColor = .clear
        backgroundColor = .clear
        applyShadow(.none)
    }

    func configure(
        summary: StatisticsSummary,
        appearance: AppAppearance,
        isSourceHidden: Bool
    ) {
        let accuracyDisplay = "\(summary.percentage)%"

        contentView.backgroundColor = .clear
        contentView.clipsToBounds = false
        backgroundColor = .clear
        layer.masksToBounds = false
        applyShadow(.none)

        actionButton.accessibilityIdentifier = ThemesCollectionService.Content.statisticsAccessibilityID
        actionButton.accessibilityLabel = L10n.Home.statisticsAccessibilityLabel
        actionButton.accessibilityHint = L10n.Home.statisticsAccessibilityHint
        actionButton.accessibilityValue = L10n.Home.statisticsAccessibilityValue(
            playedQuizzes: summary.playedQuizzes,
            percentage: summary.percentage
        )
        actionButton.applyActionAppearance(
            appearance.row,
            appearance: appearance,
            textColor: appearance.surfaceTextColor
        )
        if appearance.designStyle == .clean {
            actionButton.backgroundColor = appearance.card.backgroundColor
            actionButton.layer.borderColor = appearance.screenTextColor.withAlphaComponent(0.18).cgColor
            actionButton.layer.borderWidth = max(actionButton.layer.borderWidth, 1)
        } else if appearance.designStyle == .radar {
            actionButton.backgroundColor = .clear
        }
        actionButton.clipsToBounds = true

        titleLabel.text = L10n.Statistics.title
        titleLabel.textColor = appearance.surfaceTextColor
        titleLabel.font = appearance.typography.font(size: Typography.titleSize, weight: .bold)

        descriptionLabel.text = L10n.Home.statisticsDescription
        descriptionLabel.textColor = appearance.secondarySurfaceTextColor
        descriptionLabel.font = appearance.typography.font(size: Typography.descriptionSize, weight: .semibold)
        descriptionMinimumHeightConstraint?.constant = ceil(descriptionLabel.font.lineHeight * 2)

        playedTitleLabel.text = L10n.Home.statisticsPlayedShort
        playedValueLabel.text = "\(summary.playedQuizzes)"
        accuracyTitleLabel.text = L10n.Home.statisticsAccuracyShort
        accuracyValueLabel.text = accuracyDisplay

        [playedTitleLabel, accuracyTitleLabel].forEach {
            $0.textColor = appearance.secondarySurfaceTextColor
            $0.font = appearance.typography.font(size: Typography.metricTitleSize, weight: .semibold)
        }
        [playedValueLabel, accuracyValueLabel].forEach {
            $0.textColor = appearance.surfaceTextColor
            $0.font = appearance.typography.font(size: Typography.metricValueSize, weight: .bold)
        }

        setSourceHidden(isSourceHidden)
    }

    func makeTransitionContent() -> UIView {
        let wasHidden = actionButton.isHidden
        actionButton.isHidden = false
        defer { actionButton.isHidden = wasHidden }
        layoutIfNeeded()
        actionButton.layoutIfNeeded()

        let containerView = UIView(frame: actionButton.bounds)
        containerView.backgroundColor = .clear
        containerView.isUserInteractionEnabled = false
        containerView.accessibilityElementsHidden = true

        if let snapshot = contentStackView.snapshotView(afterScreenUpdates: false) {
            snapshot.frame = contentStackView.convert(contentStackView.bounds, to: actionButton)
            containerView.addSubview(snapshot)
        }
        return containerView
    }

    private func configureHierarchy() {
        contentView.backgroundColor = .clear
        contentView.clipsToBounds = false
        backgroundColor = .clear
        layer.masksToBounds = false

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(actionButton)

        configureLabel(
            titleLabel,
            accessibilityIdentifier: ThemesCollectionService.Content.statisticsTitleAccessibilityID,
            numberOfLines: 1,
            textAlignment: .left
        )
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = Typography.titleMinimumScaleFactor
        titleLabel.allowsDefaultTighteningForTruncation = true
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        configureLabel(
            descriptionLabel,
            accessibilityIdentifier: ThemesCollectionService.Content.statisticsDescriptionAccessibilityID,
            numberOfLines: 2,
            textAlignment: .left
        )
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        descriptionLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        let descriptionMinimumHeightConstraint = descriptionLabel.heightAnchor.constraint(
            greaterThanOrEqualToConstant: ceil(descriptionLabel.font.lineHeight * 2)
        )
        descriptionMinimumHeightConstraint.isActive = true
        self.descriptionMinimumHeightConstraint = descriptionMinimumHeightConstraint

        configureLabel(
            playedTitleLabel,
            accessibilityIdentifier: ThemesCollectionService.Content.statisticsPlayedTitleAccessibilityID,
            numberOfLines: 1,
            textAlignment: .left
        )
        configureLabel(
            playedValueLabel,
            accessibilityIdentifier: ThemesCollectionService.Content.statisticsPlayedValueAccessibilityID,
            numberOfLines: 0,
            textAlignment: .right
        )
        configureLabel(
            accuracyTitleLabel,
            accessibilityIdentifier: ThemesCollectionService.Content.statisticsAccuracyTitleAccessibilityID,
            numberOfLines: 1,
            textAlignment: .left
        )
        configureLabel(
            accuracyValueLabel,
            accessibilityIdentifier: ThemesCollectionService.Content.statisticsAccuracyValueAccessibilityID,
            numberOfLines: 0,
            textAlignment: .right
        )

        textStackView.axis = .vertical
        textStackView.alignment = .fill
        textStackView.spacing = Layout.textSpacing
        textStackView.isUserInteractionEnabled = false
        textStackView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textStackView.addArrangedSubview(titleLabel)
        textStackView.addArrangedSubview(descriptionLabel)

        configureMetricStack(
            playedMetricView,
            titleLabel: playedTitleLabel,
            valueLabel: playedValueLabel
        )
        configureMetricStack(
            accuracyMetricView,
            titleLabel: accuracyTitleLabel,
            valueLabel: accuracyValueLabel
        )
        metricsStackView.axis = .vertical
        metricsStackView.alignment = .fill
        metricsStackView.spacing = Layout.metricsSpacing
        metricsStackView.isUserInteractionEnabled = false
        metricsStackView.setContentCompressionResistancePriority(.required, for: .horizontal)
        metricsStackView.addArrangedSubview(playedMetricView)
        metricsStackView.addArrangedSubview(accuracyMetricView)

        contentStackView.axis = .horizontal
        contentStackView.alignment = .center
        contentStackView.distribution = .fill
        contentStackView.spacing = Layout.contentSpacing
        contentStackView.isUserInteractionEnabled = false
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.addArrangedSubview(textStackView)
        contentStackView.addArrangedSubview(metricsStackView)
        actionButton.addSubview(contentStackView)

        actionButton.constrainHomeActionWidth(in: contentView)
        NSLayoutConstraint.activate([
            actionButton.topAnchor.constraint(equalTo: contentView.topAnchor),
            actionButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Layout.bottomInset),

            contentStackView.leadingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: Layout.horizontalInset),
            contentStackView.trailingAnchor.constraint(equalTo: actionButton.trailingAnchor, constant: -Layout.horizontalInset),
            contentStackView.centerYAnchor.constraint(equalTo: actionButton.centerYAnchor)
        ])
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

    private func configureMetricStack(
        _ stackView: UIStackView,
        titleLabel: UILabel,
        valueLabel: UILabel
    ) {
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = Layout.metricSpacing
        stackView.isUserInteractionEnabled = false
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(valueLabel)
    }

    private func setSourceHidden(_ isHidden: Bool) {
        actionButton.isHidden = isHidden
        actionButton.isUserInteractionEnabled = !isHidden
        actionButton.accessibilityElementsHidden = isHidden
    }
}
