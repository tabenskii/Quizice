import Foundation

struct StatisticsPresentation: Equatable {
    enum MetricID: String, Equatable, CaseIterable {
        case playedQuizzes
        case correctAnswers
        case percentage
    }

    struct Metric: Equatable {
        let id: MetricID
        let title: String
        let value: String
    }

    let subtitle: String
    let emptyStateText: String?
    let metrics: [Metric]

    init(summary: StatisticsSummary) {
        subtitle = summary.playedQuizzes > 0
            ? L10n.Statistics.subtitleWithStats
            : L10n.Statistics.subtitleEmpty
        emptyStateText = summary.playedQuizzes > 0
            ? nil
            : L10n.Statistics.emptyStateText
        metrics = [
            Metric(
                id: .playedQuizzes,
                title: L10n.Statistics.playedQuizzes,
                value: "\(summary.playedQuizzes)"
            ),
            Metric(
                id: .correctAnswers,
                title: L10n.Statistics.correctAnswers,
                value: "\(summary.correctAnswers)/\(summary.totalQuestions)"
            ),
            Metric(
                id: .percentage,
                title: L10n.Statistics.percentage,
                value: "\(summary.percentage)%"
            )
        ]
    }

    func metric(_ id: MetricID) -> Metric {
        guard let metric = metrics.first(where: { $0.id == id }) else {
            preconditionFailure("Missing statistics metric: \(id.rawValue)")
        }
        return metric
    }
}
