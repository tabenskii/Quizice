import Foundation

struct StatisticsSummary: Codable, Equatable {
    let playedQuizzes: Int
    let correctAnswers: Int
    let totalQuestions: Int
    let bestCorrectAnswers: Int
    let bestTotalQuestions: Int

    var percentage: Int {
        guard totalQuestions > 0 else { return 0 }
        return Int((Double(correctAnswers) / Double(totalQuestions) * 100).rounded())
    }

    static let empty = StatisticsSummary(
        playedQuizzes: 0,
        correctAnswers: 0,
        totalQuestions: 0,
        bestCorrectAnswers: 0,
        bestTotalQuestions: 0
    )
}
