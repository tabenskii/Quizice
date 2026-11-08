import UIKit
import XCTest
@testable import Quizice

@MainActor
final class HomeCardSnapshotTests: XCTestCase {
    private let themes = [
        SnapshotSupport.makeTheme(id: "music", name: "Музыка"),
        SnapshotSupport.makeTheme(id: "technology", name: "Технологии")
    ]

    override func setUp() {
        super.setUp()
        SnapshotSupport.setUp(designStyle: .clean, cleanColorScheme: .light)
    }

    override func tearDown() {
        SnapshotSupport.tearDown()
        super.tearDown()
    }

    func testStatisticsChartsAcrossAppearances() throws {
        try withSystemTimeZones {
            for style in [AppDesignStyle.classic, .clean, .radar] {
                let view = StatisticsChartsView(frame: CGRect(x: 0, y: 0, width: 375, height: 0))
                let appearance = SnapshotSupport.appearance(designStyle: style)
                view.configure(state: .loaded(try chartTimeline()), period: .week, appearance: appearance)
                SnapshotSupport.assertComponent(view, named: "statistics-charts-\(style.rawValue)",
                                                size: CGSize(width: 375, height: 760), backgroundAppearance: appearance)
            }
        }
    }

    func testStatisticsChartsEmptyAndErrorStates() throws {
        let appearance = SnapshotSupport.appearance(designStyle: .clean)
        for (name, state) in [("empty", StatisticsHistoryStore.State.loaded(try chartTimeline(empty: true))), ("error", .failed)] {
            let view = StatisticsChartsView(frame: CGRect(x: 0, y: 0, width: 375, height: 340))
            view.configure(state: state, period: .week, appearance: appearance)
            let host = UIViewController()
            host.view.backgroundColor = appearance.backgroundColor
            host.view.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
                view.topAnchor.constraint(equalTo: host.view.topAnchor)
            ])
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 420))
            window.rootViewController = host
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            SnapshotSupport.assertScreen(host, named: "statistics-charts-\(name)", size: CGSize(width: 375, height: 420))
            window.isHidden = true
        }
    }

    func testStatisticsChartsAccessibilityExtraExtraExtraLarge() throws {
        try withSystemTimeZones {
            let appearance = SnapshotSupport.appearance(designStyle: .clean)
            let charts = StatisticsChartsView()
            charts.configure(state: .loaded(try chartTimeline()), period: .week, appearance: appearance)
            let host = UIViewController()
            host.view.backgroundColor = appearance.backgroundColor
            host.view.addSubview(charts)
            NSLayoutConstraint.activate([
                charts.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
                charts.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
                charts.topAnchor.constraint(equalTo: host.view.topAnchor)
            ])
            SnapshotSupport.assertScreen(host, named: "statistics-charts-accessibility-xxxl",
                                         size: CGSize(width: 375, height: 2300), contentSizeCategory: .accessibilityExtraExtraExtraLarge)
        }
    }

    private func withSystemTimeZones(_ body: () throws -> Void) rethrows {
        let previousDefault = NSTimeZone.default
        let previousEnvironment = getenv("TZ").map { String(cString: $0) }
        defer {
            if let previousEnvironment { setenv("TZ", previousEnvironment, 1) } else { unsetenv("TZ") }
            tzset()
            NSTimeZone.resetSystemTimeZone()
            NSTimeZone.default = previousDefault
        }
        // The same Moscow history must render identically on a UTC CI runner and locally.
        for zone in [TimeZone(secondsFromGMT: 0)!, TimeZone(identifier: "Europe/Moscow")!] {
            setenv("TZ", zone.identifier, 1)
            tzset()
            NSTimeZone.resetSystemTimeZone()
            NSTimeZone.default = zone
            XCTAssertEqual(TimeZone.current, zone)
            XCTAssertEqual(Calendar.current.timeZone, zone)
            try body()
        }
    }

    private func chartTimeline(empty: Bool = false) throws -> StatisticsTimeline {
        let days: [StatisticsHistoryResponse.Day] = empty ? [] : [
            .init(date: "2026-11-01", playedQuizzes: 2, correctAnswers: 5, totalQuestions: 20),
            .init(date: "2026-11-02", playedQuizzes: 3, correctAnswers: 10, totalQuestions: 15),
            .init(date: "2026-11-04", playedQuizzes: 1, correctAnswers: 0, totalQuestions: 5),
            .init(date: "2026-11-05", playedQuizzes: 1, correctAnswers: 5, totalQuestions: 5)
        ]
        return try StatisticsHistoryResponse(period: .week, timeZone: "Europe/Moscow", periodStart: "2026-10-31",
            periodEnd: "2026-11-07", days: days, undatedPlayedQuizzes: 53).timeline(requestedPeriod: .week, timeZone: TimeZone(identifier: "Europe/Moscow")!)
    }

    func testThemeCardSnapshot() {
        let cell = SnapshotSupport.makeCollectionCell(item: 0, themes: themes, designStyle: .clean)

        SnapshotSupport.assertComponent(
            cell.contentView,
            named: "clean-theme-card",
            size: CGSize(width: 220, height: 220)
        )
    }

    func testRadarLongThemeCompactCardSnapshot() throws {
        let longTheme = SnapshotSupport.makeTheme(id: "history_culture", name: "История и культура")
        let cell = SnapshotSupport.makeCollectionCell(
            item: 0,
            themes: [longTheme],
            designStyle: .radar,
            collectionWidth: 375
        )
        let title = try XCTUnwrap(
            cell.contentView.snapshotDescendant(
                withAccessibilityIdentifier: "homeThemeTitleLabel-history_culture"
            ) as? UILabel
        )
        func assertTitleFits(stage: String) {
            XCTAssertEqual(title.numberOfLines, 0)
            XCTAssertGreaterThan(title.bounds.width, 0)
            let requiredTitleHeight = title.sizeThatFits(
                CGSize(width: title.bounds.width, height: .greatestFiniteMagnitude)
            ).height
            XCTAssertLessThanOrEqual(
                ceil(requiredTitleHeight),
                title.bounds.height + 0.5,
                "The full Radar title must fit \(stage), including UIKit word wrapping"
            )
        }
        assertTitleFits(stage: "before snapshot hosting")

        SnapshotSupport.assertComponent(
            cell.contentView,
            named: "radar-long-theme-iphone-se",
            size: CGSize(width: 220, height: 220),
            backgroundAppearance: SnapshotSupport.appearance(designStyle: .radar)
        )
        assertTitleFits(stage: "after snapshot hosting")
    }

    func testSubscriptionPromoBannerSnapshot() {
        let cell = makeSubscriptionPromoCell(designStyle: .clean)

        SnapshotSupport.assertComponent(
            cell,
            named: "clean-subscription-promo-banner",
            size: CGSize(width: 390, height: 126)
        )
    }

    func testClassicSubscriptionPromoBannerSnapshot() {
        let cell = makeSubscriptionPromoCell(designStyle: .classic)

        SnapshotSupport.assertComponent(
            cell,
            named: "classic-subscription-promo-banner",
            size: CGSize(width: 390, height: 126),
            backgroundAppearance: SnapshotSupport.appearance(designStyle: .classic)
        )
    }

    func testRadarSubscriptionPromoBannerSnapshot() {
        let cell = makeSubscriptionPromoCell(designStyle: .radar)

        SnapshotSupport.assertComponent(
            cell,
            named: "radar-subscription-promo-banner",
            size: CGSize(width: 390, height: 126),
            backgroundAppearance: SnapshotSupport.appearance(designStyle: .radar)
        )
    }

    func testAIThemeActionCardSnapshot() {
        let cell = SnapshotSupport.makeCollectionCell(item: 2, themes: themes, designStyle: .clean)

        SnapshotSupport.assertComponent(
            cell,
            named: "clean-ai-theme-card",
            size: CGSize(width: 390, height: 140)
        )
    }

    func testClassicAIThemeActionCardSnapshot() {
        let cell = SnapshotSupport.makeCollectionCell(item: 2, themes: themes, designStyle: .classic)

        SnapshotSupport.assertComponent(
            cell,
            named: "classic-ai-theme-card",
            size: CGSize(width: 390, height: 140),
            backgroundAppearance: SnapshotSupport.appearance(designStyle: .classic)
        )
    }

    func testRadarAIThemeActionCardSnapshot() {
        let cell = SnapshotSupport.makeCollectionCell(item: 2, themes: themes, designStyle: .radar)

        SnapshotSupport.assertComponent(
            cell,
            named: "radar-ai-theme-card",
            size: CGSize(width: 390, height: 140),
            backgroundAppearance: SnapshotSupport.appearance(designStyle: .radar)
        )
    }

    func testFeelingLuckyActionCardSnapshot() {
        let cell = SnapshotSupport.makeCollectionCell(item: 3, themes: themes, designStyle: .radar)

        SnapshotSupport.assertComponent(
            cell.contentView,
            named: "radar-feeling-lucky-card",
            size: CGSize(width: 390, height: 140),
            backgroundAppearance: SnapshotSupport.appearance(designStyle: .radar)
        )
    }

    func testFeelingLuckyLoadingActionCardSnapshot() {
        let cell = SnapshotSupport.makeCollectionCell(
            item: 3,
            themes: themes,
            designStyle: .radar,
            feelingLuckyLoading: true
        )
        let progressView = cell.contentView.subviews
            .compactMap { $0 as? UIButton }
            .flatMap(\.subviews)
            .flatMap(\.subviews)
            .first { $0.accessibilityIdentifier == "homeFeelingLuckyProgressView" }
        progressView?.layer.speed = 0
        progressView?.layer.timeOffset = 0

        SnapshotSupport.assertComponent(
            cell.contentView,
            named: "radar-feeling-lucky-card-loading",
            size: CGSize(width: 390, height: 140),
            backgroundAppearance: SnapshotSupport.appearance(designStyle: .radar)
        )
    }

    func testStatisticsCardSnapshot() {
        let cell = SnapshotSupport.makeCollectionCell(item: 4, themes: themes, designStyle: .classic)

        SnapshotSupport.assertComponent(
            cell.contentView,
            named: "classic-statistics-card",
            size: CGSize(width: 390, height: 180),
            backgroundAppearance: SnapshotSupport.appearance(designStyle: .classic)
        )
    }

    func testCompactStatisticsCardSnapshot() {
        let cell = SnapshotSupport.makeCollectionCell(
            item: 4,
            themes: themes,
            designStyle: .clean,
            collectionWidth: 375
        )

        SnapshotSupport.assertComponent(
            cell.contentView,
            named: "clean-statistics-iphone-se",
            size: CGSize(width: 375, height: 180),
            backgroundAppearance: SnapshotSupport.appearance(designStyle: .clean)
        )
    }

    private func makeSubscriptionPromoCell(
        designStyle: AppDesignStyle
    ) -> UIView {
        SnapshotSupport.setUp(designStyle: designStyle)
        let cell = SubscriptionPromoBannerCollectionViewCell(
            frame: CGRect(x: 0, y: 0, width: 342, height: 90)
        )
        cell.contentView.frame = cell.bounds
        cell.configure(appearance: SnapshotSupport.appearance(designStyle: designStyle))
        cell.contentView.setNeedsLayout()
        cell.contentView.layoutIfNeeded()
        cell.setNeedsLayout()
        cell.layoutIfNeeded()

        let snapshotView = UIView(frame: cell.bounds)
        snapshotView.backgroundColor = .clear
        snapshotView.addSubview(cell.contentView)
        cell.contentView.frame = snapshotView.bounds
        cell.contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cell.contentView.layoutIfNeeded()
        return snapshotView
    }
}
