import XCTest
@testable import Quizice

final class StatisticsSummaryTests: XCTestCase {
    func testEmptySummaryHasZeroTotalsAndDisplayValues() {
        let summary = StatisticsSummary.empty

        XCTAssertEqual(summary.playedQuizzes, 0)
        XCTAssertEqual(summary.correctAnswers, 0)
        XCTAssertEqual(summary.totalQuestions, 0)
        XCTAssertEqual(summary.percentage, 0)
        XCTAssertEqual(summary.bestCorrectAnswers, 0)
        XCTAssertEqual(summary.bestTotalQuestions, 0)
    }

    func testSummaryAggregatesPlayedQuizzesCorrectAnswersAndTotalQuestions() {
        let summary = StatisticsStore.summary(from: [
            .init(correctAnswers: 4, totalQuestions: 5),
            .init(correctAnswers: 7, totalQuestions: 10),
            .init(correctAnswers: 1, totalQuestions: 2)
        ])

        XCTAssertEqual(summary.playedQuizzes, 3)
        XCTAssertEqual(summary.correctAnswers, 12)
        XCTAssertEqual(summary.totalQuestions, 17)
    }

    func testPercentageIsRoundedToNearestWholeNumber() {
        let summary = StatisticsStore.summary(from: [
            .init(correctAnswers: 2, totalQuestions: 3)
        ])

        XCTAssertEqual(summary.percentage, 67)
    }

    func testSummaryUsesBestAttempt() {
        let summary = StatisticsStore.summary(from: [
            .init(correctAnswers: 2, totalQuestions: 5),
            .init(correctAnswers: 8, totalQuestions: 10),
            .init(correctAnswers: 3, totalQuestions: 4)
        ])

        XCTAssertEqual(summary.bestCorrectAnswers, 8)
        XCTAssertEqual(summary.bestTotalQuestions, 10)
    }

    func testBestResultSelectsMoreCorrectAnswersOverHigherPercentage() {
        let summary = StatisticsStore.summary(from: [
            .init(correctAnswers: 8, totalQuestions: 10),
            .init(correctAnswers: 5, totalQuestions: 5)
        ])

        XCTAssertEqual(summary.bestCorrectAnswers, 8)
        XCTAssertEqual(summary.bestTotalQuestions, 10)
    }

    func testBestResultTieUsesMoreCorrectAnswers() {
        let summary = StatisticsStore.summary(from: [
            .init(correctAnswers: 1, totalQuestions: 2),
            .init(correctAnswers: 3, totalQuestions: 6)
        ])

        XCTAssertEqual(summary.bestCorrectAnswers, 3)
        XCTAssertEqual(summary.bestTotalQuestions, 6)
    }

    func testEqualCorrectAnswersKeepFirstAttempt() {
        let summary = StatisticsStore.summary(from: [
            .init(correctAnswers: 2, totalQuestions: 10),
            .init(correctAnswers: 2, totalQuestions: 5)
        ])

        XCTAssertEqual(summary.bestCorrectAnswers, 2)
        XCTAssertEqual(summary.bestTotalQuestions, 10)
    }
}
