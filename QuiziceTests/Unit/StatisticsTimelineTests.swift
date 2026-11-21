import XCTest
@testable import Quizice

final class StatisticsTimelineTests: XCTestCase {
    func testDailyAndPeriodAccuracyUseAnswerCountsInsteadOfAveragingPercentages() throws {
        let timeline = try response(days: [day("2026-11-01", games: 2, correct: 5, total: 20),
                                           day("2026-11-02", games: 1, correct: 5, total: 5)]).timeline(requestedPeriod: .week, timeZone: zone)
        XCTAssertEqual(timeline.days[0].accuracy, 25)
        XCTAssertEqual(timeline.accuracy, 40)
        XCTAssertEqual(timeline.playedQuizzes, 3)
    }

    func testDatesUseRequestedLocalCalendarAndEndIsExclusive() throws {
        let timeline = try response(days: [day("2026-11-01")]).timeline(requestedPeriod: .week, timeZone: zone)
        XCTAssertEqual(timeline.days[0].date, ISO8601DateFormatter().date(from: "2026-10-31T21:00:00Z"))
        XCTAssertThrowsError(try response(days: [day("2026-11-07")]).timeline(requestedPeriod: .week, timeZone: zone))
        XCTAssertThrowsError(try response(days: [day("2026-10-30")]).timeline(requestedPeriod: .week, timeZone: zone))
    }

    func testDSTWeekHasSevenCalendarDaysRatherThan168Hours() throws {
        let zone = TimeZone(identifier: "America/New_York")!
        let timeline = try response(timeZone: zone.identifier).timeline(requestedPeriod: .week, timeZone: zone)
        XCTAssertEqual(timeline.interval.duration, 169 * 3600)
    }

    func testAllTimeIsSparseAndDoesNotInventDaysOrInterpolateGaps() throws {
        let timeline = try response(period: .allTime, start: "1900-01-01", days: [day("1900-01-01"), day("2026-11-01"), day("2026-11-02")]).timeline(requestedPeriod: .allTime, timeZone: zone)
        XCTAssertEqual(timeline.days.count, 3)
        XCTAssertEqual(timeline.days.map(\.accuracySeries), [0, 1, 1])
    }

    func testEmptyHistoryPreservesUndatedMetadataWithoutFabricatingAccuracy() throws {
        let timeline = try response(undated: 53).timeline(requestedPeriod: .week, timeZone: zone)
        XCTAssertTrue(timeline.days.isEmpty)
        XCTAssertNil(timeline.accuracy)
        XCTAssertEqual(timeline.undatedPlayedQuizzes, 53)
    }

    func testRejectsInvalidDatesDuplicateDaysAndInvalidCounters() {
        for days in [[day("2026-11-01"), day("2026-11-01")], [day("2026-11-02"), day("2026-11-01")],
                     [day("2026-11-31")], [day("2026-11-01", games: 0)], [day("2026-11-01", correct: 6)],
                     [day("2026-11-01", correct: -1)], [day("2026-11-01", total: 0)]] {
            XCTAssertThrowsError(try response(days: days).timeline(requestedPeriod: .week, timeZone: zone))
        }
    }

    func testValidatesPeriodLengthAndResponseScope() throws {
        XCTAssertThrowsError(try response().timeline(requestedPeriod: .month, timeZone: zone))
        XCTAssertThrowsError(try response(timeZone: "UTC").timeline(requestedPeriod: .week, timeZone: zone))
        XCTAssertThrowsError(try response(start: "2026-11-01").timeline(requestedPeriod: .week, timeZone: zone))
        XCTAssertThrowsError(try response(undated: -1).timeline(requestedPeriod: .week, timeZone: zone))
        let month = try response(period: .month, start: "2026-10-08").timeline(requestedPeriod: .month, timeZone: zone)
        XCTAssertEqual(month.interval.duration, 30 * 86400)
    }

    private let zone = TimeZone(identifier: "Europe/Moscow")!
    private func day(_ date: String, games: Int = 1, correct: Int = 3, total: Int = 5) -> StatisticsHistoryResponse.Day {
        .init(date: date, playedQuizzes: games, correctAnswers: correct, totalQuestions: total)
    }
    private func response(period: StatisticsPeriod = .week, timeZone: String = "Europe/Moscow", start: String = "2026-10-31", days: [StatisticsHistoryResponse.Day] = [], undated: Int = 0) -> StatisticsHistoryResponse {
        .init(period: period, timeZone: timeZone, periodStart: start, periodEnd: "2026-11-07", days: days, undatedPlayedQuizzes: undated)
    }
}
