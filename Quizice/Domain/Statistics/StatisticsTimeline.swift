import Foundation

enum StatisticsPeriod: String, Codable, CaseIterable {
    case week
    case month
    case allTime = "all"

    var dayCount: Int? {
        switch self {
        case .week: 7
        case .month: 30
        case .allTime: nil
        }
    }
}

struct StatisticsHistoryResponse: Decodable, Equatable {
    struct Day: Decodable, Equatable {
        let date: String
        let playedQuizzes: Int
        let correctAnswers: Int
        let totalQuestions: Int
    }
    let period: StatisticsPeriod
    let timeZone: String
    let periodStart: String
    let periodEnd: String
    let days: [Day]
    let undatedPlayedQuizzes: Int

    func timeline(requestedPeriod: StatisticsPeriod, timeZone requestedTimeZone: TimeZone) throws -> StatisticsTimeline {
        guard period == requestedPeriod, timeZone == requestedTimeZone.identifier,
              undatedPlayedQuizzes >= 0 else { throw BackendContentError.contractViolation }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = requestedTimeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = requestedTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        func date(_ string: String) -> Date? {
            guard string.count == 10, let value = formatter.date(from: string),
                  formatter.string(from: value) == string else { return nil }
            return value
        }
        guard let start = date(periodStart), let end = date(periodEnd), start < end else {
            throw BackendContentError.contractViolation
        }
        if let expectedDays = period.dayCount,
           calendar.dateComponents([.day], from: start, to: end).day != expectedDays {
            throw BackendContentError.contractViolation
        }
        var previous: Date?
        var series = 0
        let points = try days.map { day -> StatisticsTimeline.Day in
            guard let timestamp = date(day.date), timestamp >= start, timestamp < end,
                  previous.map({ timestamp > $0 }) ?? true,
                  day.playedQuizzes > 0, day.totalQuestions >= day.playedQuizzes,
                  day.correctAnswers >= 0, day.correctAnswers <= day.totalQuestions else {
                throw BackendContentError.contractViolation
            }
            if let previous, calendar.dateComponents([.day], from: previous, to: timestamp).day != 1 {
                series += 1
            }
            previous = timestamp
            return .init(date: timestamp, playedQuizzes: day.playedQuizzes, correctAnswers: day.correctAnswers,
                         totalQuestions: day.totalQuestions, accuracySeries: series)
        }
        return StatisticsTimeline(days: points, interval: DateInterval(start: start, end: end),
                                  timeZone: requestedTimeZone, undatedPlayedQuizzes: undatedPlayedQuizzes)
    }
}

struct StatisticsTimeline: Equatable {
    struct Day: Equatable, Identifiable {
        let date: Date
        let playedQuizzes: Int
        let correctAnswers: Int
        let totalQuestions: Int
        /// Do not interpolate accuracy through days without recorded games.
        let accuracySeries: Int
        var id: Date { date }
        var accuracy: Double { Double(correctAnswers) / Double(totalQuestions) * 100 }
    }
    let days: [Day]
    let interval: DateInterval
    let timeZone: TimeZone
    let undatedPlayedQuizzes: Int
    var playedQuizzes: Int { days.reduce(0) { $0 + $1.playedQuizzes } }
    var correctAnswers: Int { days.reduce(0) { $0 + $1.correctAnswers } }
    var totalQuestions: Int { days.reduce(0) { $0 + $1.totalQuestions } }
    var accuracy: Double? {
        guard totalQuestions > 0 else { return nil }
        return Double(correctAnswers) / Double(totalQuestions) * 100
    }
}
