import UIKit

final class StatisticsCardCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "homeStatisticsCardCell"

    private enum Layout {
        static let horizontalInset: CGFloat = 18
        static let verticalInset: CGFloat = 12
        static let headingSpacing: CGFloat = 6
        static let headingToMetricsSpacing: CGFloat = 12
        static let chevronWidth: CGFloat = 12
        static let columnSpacing: CGFloat = 12
        static let rowSpacing: CGFloat = 8
        static let inlineMetricSpacing: CGFloat = 6
        static let stackedMetricSpacing: CGFloat = 3
    }

    private enum MetricsArrangement {
        case columns
        case rows
        case stacked
    }

    private struct ContentLayout {
        let title: UIFont
        let caption: UIFont
        let value: UIFont
        let metricsArrangement: MetricsArrangement
        let height: CGFloat

        init(appearance: AppAppearance, traits: UITraitCollection, width: CGFloat) {
            let titleFont = appearance.typography.font(size: 22, weight: .bold, compatibleWith: traits)
            let captionFont = appearance.typography.font(size: 16, weight: .semibold, compatibleWith: traits)
            let valueFont = appearance.typography.font(size: 18, weight: .semibold, compatibleWith: traits)
            let played = L10n.Home.statisticsPlayedShort
            let accuracy = L10n.Home.statisticsAccuracyShort
            let contentWidth = max(1, width - 2 * Layout.horizontalInset)
            let titleWidth = max(1, contentWidth - Layout.headingSpacing - Layout.chevronWidth)
            let columnWidth = (contentWidth - Layout.columnSpacing) / 2
            let requiredPairWidth = max(
                Self.textWidth(played, font: captionFont) + Self.textWidth("888", font: valueFont),
                Self.textWidth(accuracy, font: captionFont) + Self.textWidth("100%", font: valueFont)
            ) + Layout.inlineMetricSpacing
            title = Self.fitWords(in: [L10n.Statistics.title], font: titleFont, width: titleWidth)
            caption = Self.fitWords(in: [played, accuracy], font: captionFont, width: contentWidth)
            value = valueFont

            let metricsHeight: CGFloat
            let lineHeight = ceil(max(caption.lineHeight, value.lineHeight))
            if requiredPairWidth <= columnWidth {
                metricsArrangement = .columns
                metricsHeight = lineHeight
            } else if requiredPairWidth <= contentWidth {
                metricsArrangement = .rows
                metricsHeight = 2 * lineHeight + Layout.rowSpacing
            } else {
                metricsArrangement = .stacked
                metricsHeight = Self.textHeight(played, font: caption, width: contentWidth)
                    + Self.textHeight(accuracy, font: caption, width: contentWidth)
                    + 2 * (ceil(value.lineHeight) + Layout.stackedMetricSpacing)
                    + Layout.rowSpacing
            }
            height = Self.textHeight(L10n.Statistics.title, font: title, width: titleWidth)
                + Layout.headingToMetricsSpacing + metricsHeight + 2 * Layout.verticalInset
        }

        private static func textWidth(_ text: String, font: UIFont) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: font]).width)
        }

        private static func textHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
            let rect = (text as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            )
            return ceil(max(font.lineHeight, rect.height))
        }

        private static func fitWords(in labels: [String], font: UIFont, width: CGFloat) -> UIFont {
            let longestWordWidth = labels.flatMap { $0.split(whereSeparator: \.isWhitespace) }
                .map { textWidth(String($0), font: font) }
                .max() ?? 0
            guard longestWordWidth > width else { return font }
            return font.withSize(font.pointSize * max(1, floor(width) - 1) / longestWordWidth)
        }
    }

    let actionButton = UIButton(type: .system)

    private let titleLabel = UILabel()
    private let chevronView = UIImageView(image: UIImage(
        systemName: "chevron.forward",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
    ))
    private let playedTitleLabel = UILabel()
    private let playedValueLabel = UILabel()
    private let accuracyTitleLabel = UILabel()
    private let accuracyValueLabel = UILabel()
    private let headingStackView = UIStackView()
    private let playedMetricView = UIStackView()
    private let accuracyMetricView = UIStackView()
    private let metricsStackView = UIStackView()
    private let contentStackView = UIStackView()
    private lazy var buttonWidthConstraint = actionButton.widthAnchor.constraint(equalToConstant: 0)
    private var buttonBottomConstraint: NSLayoutConstraint!

    static func height(width: CGFloat, appearance: AppAppearance, traits: UITraitCollection) -> CGFloat {
        ContentLayout(appearance: appearance, traits: traits, width: width).height
    }

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
        [titleLabel, playedTitleLabel, playedValueLabel, accuracyTitleLabel, accuracyValueLabel]
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
        traits: UITraitCollection,
        width: CGFloat,
        bottomInset: CGFloat,
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
        buttonWidthConstraint.constant = width
        buttonBottomConstraint.constant = -bottomInset

        let layout = ContentLayout(appearance: appearance, traits: traits, width: width)
        applyMetricsArrangement(layout.metricsArrangement)
        titleLabel.text = L10n.Statistics.title
        titleLabel.textColor = appearance.surfaceTextColor
        titleLabel.font = layout.title
        chevronView.tintColor = appearance.secondarySurfaceTextColor

        playedTitleLabel.text = L10n.Home.statisticsPlayedShort
        playedValueLabel.text = "\(summary.playedQuizzes)"
        accuracyTitleLabel.text = L10n.Home.statisticsAccuracyShort
        accuracyValueLabel.text = accuracyDisplay

        [playedTitleLabel, accuracyTitleLabel].forEach {
            $0.textColor = appearance.secondarySurfaceTextColor
            $0.font = layout.caption
        }
        [playedValueLabel, accuracyValueLabel].forEach {
            $0.textColor = appearance.surfaceTextColor
            $0.font = layout.value
        }

        setSourceHidden(isSourceHidden)
    }

    private func applyMetricsArrangement(_ arrangement: MetricsArrangement) {
        let hasColumns = arrangement == .columns
        let stacksMetrics = arrangement == .stacked
        metricsStackView.axis = hasColumns ? .horizontal : .vertical
        metricsStackView.alignment = hasColumns ? .firstBaseline : .fill
        metricsStackView.distribution = hasColumns ? .fillEqually : .fill
        metricsStackView.spacing = hasColumns ? Layout.columnSpacing : Layout.rowSpacing

        for row in [playedMetricView, accuracyMetricView] {
            row.axis = stacksMetrics ? .vertical : .horizontal
            row.alignment = stacksMetrics ? .fill : .firstBaseline
            row.spacing = stacksMetrics ? Layout.stackedMetricSpacing : Layout.inlineMetricSpacing
        }
        for valueLabel in [playedValueLabel, accuracyValueLabel] {
            valueLabel.textAlignment = arrangement == .rows ? .right : .natural
        }
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
        actionButton.isAccessibilityElement = true
        contentView.addSubview(actionButton)

        configureLabel(
            titleLabel,
            accessibilityIdentifier: ThemesCollectionService.Content.statisticsTitleAccessibilityID,
            numberOfLines: 0
        )

        configureLabel(
            playedTitleLabel,
            accessibilityIdentifier: ThemesCollectionService.Content.statisticsPlayedTitleAccessibilityID,
            numberOfLines: 0
        )
        configureLabel(
            playedValueLabel,
            accessibilityIdentifier: ThemesCollectionService.Content.statisticsPlayedValueAccessibilityID,
            numberOfLines: 1
        )
        configureLabel(
            accuracyTitleLabel,
            accessibilityIdentifier: ThemesCollectionService.Content.statisticsAccuracyTitleAccessibilityID,
            numberOfLines: 0
        )
        configureLabel(
            accuracyValueLabel,
            accessibilityIdentifier: ThemesCollectionService.Content.statisticsAccuracyValueAccessibilityID,
            numberOfLines: 1
        )

        headingStackView.alignment = .center
        headingStackView.spacing = Layout.headingSpacing
        headingStackView.addArrangedSubview(titleLabel)
        headingStackView.addArrangedSubview(chevronView)
        chevronView.contentMode = .scaleAspectFit
        chevronView.widthAnchor.constraint(equalToConstant: Layout.chevronWidth).isActive = true
        chevronView.heightAnchor.constraint(equalToConstant: 14).isActive = true

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
        metricsStackView.addArrangedSubview(playedMetricView)
        metricsStackView.addArrangedSubview(accuracyMetricView)

        contentStackView.axis = .vertical
        contentStackView.spacing = Layout.headingToMetricsSpacing
        contentStackView.isUserInteractionEnabled = false
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.addArrangedSubview(headingStackView)
        contentStackView.addArrangedSubview(metricsStackView)
        actionButton.addSubview(contentStackView)

        buttonBottomConstraint = actionButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        NSLayoutConstraint.activate([
            actionButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            buttonWidthConstraint,
            actionButton.topAnchor.constraint(equalTo: contentView.topAnchor),
            buttonBottomConstraint,

            contentStackView.leadingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: Layout.horizontalInset),
            contentStackView.trailingAnchor.constraint(equalTo: actionButton.trailingAnchor, constant: -Layout.horizontalInset),
            contentStackView.topAnchor.constraint(greaterThanOrEqualTo: actionButton.topAnchor, constant: Layout.verticalInset),
            contentStackView.bottomAnchor.constraint(lessThanOrEqualTo: actionButton.bottomAnchor, constant: -Layout.verticalInset),
            contentStackView.centerYAnchor.constraint(equalTo: actionButton.centerYAnchor)
        ])
    }

    private func configureLabel(
        _ label: UILabel,
        accessibilityIdentifier: String,
        numberOfLines: Int
    ) {
        label.accessibilityIdentifier = accessibilityIdentifier
        label.numberOfLines = numberOfLines
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureMetricStack(
        _ stackView: UIStackView,
        titleLabel: UILabel,
        valueLabel: UILabel
    ) {
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.5
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
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
