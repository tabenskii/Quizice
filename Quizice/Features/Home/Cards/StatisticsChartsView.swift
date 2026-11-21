import Charts
import Observation
import SwiftUI
import UIKit

final class StatisticsChartsView: UIView {
    private let sizingController = UIHostingController(rootView: AnyView(EmptyView()))
    private let viewport = StatisticsChartsViewport()
    private var hostedContent: (UIView & UIContentView)?
    private var state = StatisticsHistoryStore.State.idle
    private var appearance: AppAppearance?
    private var measuredWidth: CGFloat?
    private var measuredHeight: CGFloat = 0
    private var minimumHeight: CGFloat = 0
    private var fadeInCharts = false
    private(set) var selectedPeriod = StatisticsPeriod.week
    var onPeriodChange: ((StatisticsPeriod) -> Void)?
    var onRetry: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityIdentifier = "statisticsChartsView"
        isAccessibilityElement = false
        clipsToBounds = true
        sizingController.safeAreaRegions = []

        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (view: StatisticsChartsView, _: UITraitCollection) in
            view.updateContent()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: measuredHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        measureContentHeight()
    }

    func configure(
        state: StatisticsHistoryStore.State,
        period: StatisticsPeriod,
        appearance: AppAppearance,
        minimumHeight: CGFloat = 0
    ) {
        if state != self.state {
            fadeInCharts = window != nil && UIView.areAnimationsEnabled
        }
        self.state = state
        self.selectedPeriod = period
        self.appearance = appearance
        self.minimumHeight = state == .loading ? max(minimumHeight, measuredHeight) : minimumHeight
        updateContent()
    }

    func updateViewport(_ visibleBounds: CGRect, bottomAtTop: CGFloat) {
        guard state.isWaitingForHistory else { return }
        if viewport.visibleBounds != visibleBounds {
            viewport.visibleBounds = visibleBounds
        }

        let height = ceil(bottomAtTop)
        guard measuredHeight > 0, height > measuredHeight else { return }
        minimumHeight = height
        updateContent()
    }

    private func updateContent() {
        guard let appearance else { return }
        var calendar = Calendar(identifier: .gregorian)
        if case let .loaded(timeline) = state { calendar.timeZone = timeline.timeZone }
        let charts = StatisticsChartsContent(
            state: state,
            period: selectedPeriod,
            appearance: appearance,
            fadeInCharts: fadeInCharts,
            minimumHeight: minimumHeight,
            viewport: viewport,
            selectPeriod: { [weak self] in self?.onPeriodChange?($0) },
            retry: { [weak self] in self?.onRetry?() }
        )
        .environment(\.locale, AppLocalizationStore.shared.resolvedLocale)
        .environment(\.calendar, calendar)
        .environment(\.timeZone, calendar.timeZone)
        .preferredColorScheme(appearance.swiftUIColorScheme)

        let configuration = UIHostingConfiguration { charts }.margins(.all, 0)
        if let hostedContent {
            hostedContent.configuration = configuration
        } else {
            let view = configuration.makeContentView()
            view.backgroundColor = .clear
            view.frame = bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(view)
            hostedContent = view
        }

        sizingController.rootView = AnyView(
            charts.environment(\.dynamicTypeSize, DynamicTypeSize(traitCollection.preferredContentSizeCategory) ?? .large)
        )
        measuredWidth = nil
        measureContentHeight()
        setNeedsLayout()
    }

    private func measureContentHeight() {
        let width = bounds.width
        guard width > 0, measuredWidth != width else { return }
        let proposal = CGSize(width: width, height: UIView.layoutFittingExpandedSize.height)
        let height = ceil(sizingController.sizeThatFits(in: proposal).height)
        measuredWidth = width
        guard measuredHeight != height else { return }

        measuredHeight = height
        invalidateIntrinsicContentSize()
    }
}

@Observable
private final class StatisticsChartsViewport {
    var visibleBounds: CGRect?
}

private extension StatisticsHistoryStore.State {
    var isWaitingForHistory: Bool { self == .idle || self == .loading }
}

private struct StatisticsPeriodPickerBounds: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private struct StatisticsChartsContent: View {
    private static let panelPadding: CGFloat = 16

    let state: StatisticsHistoryStore.State
    let period: StatisticsPeriod
    let appearance: AppAppearance
    let fadeInCharts: Bool
    let minimumHeight: CGFloat
    let viewport: StatisticsChartsViewport
    let selectPeriod: (StatisticsPeriod) -> Void
    let retry: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @ScaledMetric(relativeTo: .body) private var chartHeight = 170.0
    @ScaledMetric(relativeTo: .subheadline) private var loadingHeight = 80.0

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
                Color.clear.frame(height: loadingHeight)
            case .failed:
                Text(L10n.Statistics.historyError).fixedSize(horizontal: false, vertical: true)
                retryButton
            case let .loaded(timeline):
                history(timeline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .font(appearance.typography.swiftUIFont(size: 16, weight: .regular))
        .foregroundStyle(foreground)
        .padding(Self.panelPadding)
        .frame(minHeight: minimumHeight, alignment: .topLeading)
        .background(Color(uiColor: appearance.row.backgroundColor), in: RoundedRectangle(cornerRadius: appearance.row.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: appearance.row.cornerRadius)
                .stroke(Color(uiColor: appearance.row.borderColor), lineWidth: appearance.row.borderWidth)
        }
        .overlayPreferenceValue(StatisticsPeriodPickerBounds.self) { picker in
            if state.isWaitingForHistory, let picker {
                loadingIndicator(below: picker)
            }
        }
    }

    private func loadingIndicator(below picker: Anchor<CGRect>) -> some View {
        GeometryReader { geometry in
            let visibleBounds = viewport.visibleBounds ?? CGRect(origin: .zero, size: geometry.size)
            let top = max(geometry[picker].maxY, visibleBounds.minY)
            let bottom = min(geometry.size.height, visibleBounds.maxY)
            ViewThatFits(in: .vertical) {
                ProgressView {
                    Text(L10n.Statistics.historyLoading)
                        .foregroundStyle(secondary)
                        .multilineTextAlignment(.center)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 10)

                ProgressView()
                    .accessibilityLabel(L10n.Statistics.historyLoading)
            }
            .tint(accent)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Self.panelPadding)
            .frame(height: max(0, bottom - top))
            .clipped()
            .offset(y: top)
            .accessibilityIdentifier("statisticsHistoryLoading")
        }
        .allowsHitTesting(false)
    }

    private var retryButton: some View {
        let style = appearance.primaryButton
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius)
        return Button(action: retry) {
            Text(L10n.Statistics.historyRetry)
                .font(appearance.typography.swiftUIFont(size: 17, weight: .semibold))
                .foregroundStyle(Color(uiColor: QuizThemeAccentStyle.primaryButtonTextColor(themeID: nil, appearance: appearance)))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Self.panelPadding)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color(uiColor: style.backgroundColor), in: shape)
                .overlay {
                    shape.strokeBorder(Color(uiColor: style.borderColor), lineWidth: style.borderWidth)
                        .clipShape(shape)
                }
        }
        .buttonStyle(QuizPressButtonStyle())
        .accessibilityIdentifier("statisticsHistoryRetry")
    }

    @ViewBuilder
    private var periodPicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            picker.pickerStyle(.menu).frame(minHeight: 44)
        } else {
            picker.pickerStyle(.segmented).frame(maxWidth: .infinity, minHeight: 44)
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
        .anchorPreference(key: StatisticsPeriodPickerBounds.self, value: .bounds) { $0 }
    }

    private func history(_ timeline: StatisticsTimeline) -> some View {
        VStack(alignment: .leading, spacing: 20) {
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
                VStack(alignment: .leading, spacing: 20) {
                    metricHeader(title: L10n.Statistics.dailyAccuracy,
                                 value: ((timeline.accuracy ?? 0) / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale)))
                    accuracyChart(timeline)
                    metricHeader(title: L10n.Statistics.dailyGames, value: timeline.playedQuizzes.formatted(.number.locale(locale)))
                    gamesChart(timeline)
                }
                .modifier(StatisticsChartsFadeIn(enabled: fadeInCharts))
            }
        }
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
        let barTop = UnevenRoundedRectangle(
            topLeadingRadius: appearance.row.cornerRadius,
            topTrailingRadius: appearance.row.cornerRadius,
            style: .continuous
        )
        return Chart(timeline.days) { day in
            BarMark(
                x: .value(L10n.Statistics.day, day.date, unit: .day, calendar: calendar),
                y: .value(L10n.Statistics.dailyGames, day.playedQuizzes)
            )
                .foregroundStyle(accent)
                .clipShape(barTop)
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

    @AxisContentBuilder
    private func dateAxis(_ timeline: StatisticsTimeline) -> some AxisContent {
        if timeline.interval.duration > 366 * 24 * 60 * 60 {
            let format = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeline.timeZone)
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(format.month(.abbreviated).year())).foregroundStyle(secondary)
                    }
                }
            }
        } else {
            let dayMonth = Date.VerbatimFormatStyle(
                format: "\(day: .twoDigits).\(month: .twoDigits)",
                locale: locale,
                timeZone: timeline.timeZone,
                calendar: calendar
            )
            let dayCount = max(1, calendar.dateComponents([.day], from: timeline.interval.start, to: timeline.interval.end).day ?? 1)
            let labelCount = min(6, dayCount)
            let dates = (0..<labelCount).compactMap { index in
                let dayOffset = (2 * index + 1) * dayCount / (2 * labelCount)
                return calendar.date(byAdding: .day, value: dayOffset, to: timeline.interval.start)
            }
            AxisMarks(values: dates) { value in
                AxisValueLabel(centered: false) {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(dayMonth))
                            .foregroundStyle(secondary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
    }
}

private struct StatisticsChartsFadeIn: ViewModifier {
    let enabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content
            .opacity(enabled && !reduceMotion && !hasAppeared ? 0 : 1)
            .onAppear {
                guard !hasAppeared else { return }
                withAnimation(enabled && !reduceMotion ? .easeInOut(duration: 0.25) : nil) {
                    hasAppeared = true
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
