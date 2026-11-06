import Charts
import SwiftUI
import UIKit

final class StatisticsChartsView: UIView {
    private var hostedContent: (UIView & UIContentView)?
    private var state = StatisticsHistoryStore.State.idle
    private var appearance: AppAppearance?
    private(set) var selectedPeriod = StatisticsPeriod.week
    var onPeriodChange: ((StatisticsPeriod) -> Void)?
    var onRetry: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityIdentifier = "statisticsChartsView"
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(state: StatisticsHistoryStore.State, period: StatisticsPeriod, appearance: AppAppearance) {
        self.state = state
        self.selectedPeriod = period
        self.appearance = appearance
        updateContent()
    }

    private func updateContent() {
        guard let appearance else { return }
        var calendar = Calendar(identifier: .gregorian)
        if case let .loaded(timeline) = state { calendar.timeZone = timeline.timeZone }
        let configuration = UIHostingConfiguration {
            StatisticsChartsContent(
                state: state,
                period: selectedPeriod,
                appearance: appearance,
                selectPeriod: { [weak self] in self?.onPeriodChange?($0) },
                retry: { [weak self] in self?.onRetry?() }
            )
            .environment(\.locale, AppLocalizationStore.shared.resolvedLocale)
            .environment(\.calendar, calendar)
            .environment(\.timeZone, calendar.timeZone)
            .preferredColorScheme(appearance.swiftUIColorScheme)
        }.margins(.all, 0)

        if let hostedContent {
            hostedContent.configuration = configuration
        } else {
            let content = configuration.makeContentView()
            content.backgroundColor = .clear
            content.translatesAutoresizingMaskIntoConstraints = false
            addSubview(content)
            NSLayoutConstraint.activate([
                content.topAnchor.constraint(equalTo: topAnchor),
                content.leadingAnchor.constraint(equalTo: leadingAnchor),
                content.trailingAnchor.constraint(equalTo: trailingAnchor),
                content.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            hostedContent = content
        }
        invalidateIntrinsicContentSize()
    }
}

private struct StatisticsChartsContent: View {
    let state: StatisticsHistoryStore.State
    let period: StatisticsPeriod
    let appearance: AppAppearance
    let selectPeriod: (StatisticsPeriod) -> Void
    let retry: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @ScaledMetric(relativeTo: .body) private var chartHeight = 170.0

    private var foreground: Color { Color(uiColor: appearance.surfaceTextColor) }
    private var secondary: Color { Color(uiColor: appearance.secondarySurfaceTextColor) }
    private var accent: Color { Color(uiColor: appearance.designStyle == .classic ? appearance.surfaceTextColor : appearance.accentColor) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.Statistics.historyTitle)
                .font(appearance.typography.swiftUIFont(size: 22, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            periodPicker
            switch state {
            case .idle, .loading:
                ProgressView(L10n.Statistics.historyLoading)
                    .tint(accent)
                    .frame(maxWidth: .infinity, minHeight: 80)
            case .failed:
                Text(L10n.Statistics.historyError).fixedSize(horizontal: false, vertical: true)
                Button(L10n.Statistics.historyRetry, action: retry)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("statisticsHistoryRetry")
            case let .loaded(timeline):
                if dynamicTypeSize.isAccessibilitySize {
                    Text(dateRange(timeline))
                        .foregroundStyle(secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if timeline.undatedPlayedQuizzes > 0 {
                    Text(L10n.Statistics.historyUndated)
                        .font(appearance.typography.swiftUIFont(size: 15, weight: .regular))
                        .foregroundStyle(secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if timeline.days.isEmpty {
                    Text(L10n.Statistics.historyEmpty)
                        .foregroundStyle(secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("statisticsChartsEmptyState")
                } else {
                    metricHeader(title: L10n.Statistics.dailyAccuracy,
                                 value: ((timeline.accuracy ?? 0) / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale)))
                    accuracyChart(timeline)
                    metricHeader(title: L10n.Statistics.dailyGames, value: timeline.playedQuizzes.formatted(.number.locale(locale)))
                    gamesChart(timeline)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .font(appearance.typography.swiftUIFont(size: 16, weight: .regular))
        .foregroundStyle(foreground)
        .padding(16)
        .background(Color(uiColor: appearance.row.backgroundColor), in: RoundedRectangle(cornerRadius: appearance.row.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: appearance.row.cornerRadius)
                .stroke(Color(uiColor: appearance.row.borderColor), lineWidth: appearance.row.borderWidth)
        }
    }

    @ViewBuilder
    private var periodPicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            picker.pickerStyle(.menu).frame(minHeight: 44)
        } else {
            picker.pickerStyle(.segmented).frame(minHeight: 44)
        }
    }

    private var picker: some View {
        Picker(L10n.Statistics.period, selection: Binding(get: { period }, set: selectPeriod)) {
            ForEach(StatisticsPeriod.allCases, id: \.self) { period in
                Text(period.title).tag(period)
            }
        }
        .tint(accent)
        .accessibilityIdentifier("statisticsPeriodPicker")
    }

    private func metricHeader(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(appearance.typography.swiftUIFont(size: 17, weight: .medium)).foregroundStyle(secondary)
            Text(value).font(appearance.typography.swiftUIFont(size: 24, weight: .bold)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func accuracyChart(_ timeline: StatisticsTimeline) -> some View {
        Chart(timeline.days) { day in
            LineMark(
                x: .value(L10n.Statistics.day, day.date),
                y: .value(L10n.Statistics.dailyAccuracy, day.accuracy),
                series: .value("series", day.accuracySeries)
            )
            .foregroundStyle(accent)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .accessibilityHidden(true)
            PointMark(x: .value(L10n.Statistics.day, day.date), y: .value(L10n.Statistics.dailyAccuracy, day.accuracy))
                .foregroundStyle(accent)
                .symbolSize(32)
                .accessibilityLabel(day.date.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: locale, calendar: calendar, timeZone: timeline.timeZone)))
                .accessibilityValue((day.accuracy / 100).formatted(.percent.precision(.fractionLength(1)).locale(locale)))
        }
        .chartXScale(domain: timeline.interval.start...timeline.interval.end)
        .chartYScale(domain: 0...100)
        .chartXAxis { dateAxis(timeline) }
        .chartXAxis(dynamicTypeSize.isAccessibilitySize ? .hidden : .visible)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine().foregroundStyle(Color(uiColor: appearance.progressTrackColor))
                AxisValueLabel {
                    if let number = value.as(Int.self) { Text("\(number)%").foregroundStyle(secondary) }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: chartHeight)
        .accessibilityLabel(L10n.Statistics.dailyAccuracy)
        .accessibilityIdentifier("statisticsAccuracyChart")
    }

    private func gamesChart(_ timeline: StatisticsTimeline) -> some View {
        let maximumGames = max(timeline.days.map(\.playedQuizzes).max() ?? 0, 1)
        let gameTicks = Array(Set([0, max(1, maximumGames / 2), maximumGames])).sorted()
        return Chart(timeline.days) { day in
            BarMark(
                x: .value(L10n.Statistics.day, day.date, unit: .day, calendar: calendar),
                y: .value(L10n.Statistics.dailyGames, day.playedQuizzes)
            )
                .foregroundStyle(accent)
                .cornerRadius(3)
                .accessibilityLabel(day.date.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: locale, calendar: calendar, timeZone: timeline.timeZone)))
                .accessibilityValue(day.playedQuizzes.formatted(.number.locale(locale)))
        }
        .chartXScale(domain: timeline.interval.start...timeline.interval.end)
        .chartYScale(domain: 0...maximumGames)
        .chartXAxis { dateAxis(timeline) }
        .chartXAxis(dynamicTypeSize.isAccessibilitySize ? .hidden : .visible)
        .chartYAxis {
            AxisMarks(position: .leading, values: gameTicks) { _ in
                AxisGridLine().foregroundStyle(Color(uiColor: appearance.progressTrackColor))
                AxisValueLabel().foregroundStyle(secondary)
            }
        }
        .frame(height: chartHeight)
        .accessibilityLabel(L10n.Statistics.dailyGames)
        .accessibilityIdentifier("statisticsGamesChart")
    }

    private func dateRange(_ timeline: StatisticsTimeline) -> String {
        let end = calendar.date(byAdding: .day, value: -1, to: timeline.interval.end) ?? timeline.interval.start
        let format = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: calendar, timeZone: timeline.timeZone)
        return "\(timeline.interval.start.formatted(format)) – \(end.formatted(format))"
    }

    private func dateAxis(_ timeline: StatisticsTimeline) -> some AxisContent {
        let format = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeline.timeZone)
        return AxisMarks(values: .automatic(desiredCount: 3)) { value in
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    if timeline.interval.duration > 366 * 24 * 60 * 60 {
                        Text(date, format: format.month(.abbreviated).year()).foregroundStyle(secondary)
                    } else {
                        Text(date, format: format.day().month(.abbreviated)).foregroundStyle(secondary)
                    }
                }
            }
        }
    }
}

private extension StatisticsPeriod {
    var title: String {
        switch self {
        case .week: L10n.Statistics.periodWeek
        case .month: L10n.Statistics.periodMonth
        case .allTime: L10n.Statistics.periodAllTime
        }
    }
}
