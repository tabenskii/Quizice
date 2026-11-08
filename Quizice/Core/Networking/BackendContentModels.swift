import Foundation

enum BackendOperation: String, Equatable {
    case authentication
    case accountDeletion = "account_deletion"
    case statisticsSync = "statistics_sync"
    case themes
    case themePreferences = "theme_preferences"
    case questions
    case questionAnswers = "question_answers"
    case aiGeneration = "ai_generation"
}

enum QuestionProgressMode: String, Codable, Equatable {
    case allAnswered = "all_answered"
    case correctOnly = "correct_only"
}

enum QuestionRepeatStrategy: String, Codable, CaseIterable {
    case showAll
    case hideAnswered
    case retryIncorrect

    var progressMode: QuestionProgressMode? {
        switch self {
        case .showAll: nil
        case .hideAnswered: .allAnswered
        case .retryIncorrect: .correctOnly
        }
    }

    func effective(hasValidBackendSession: Bool) -> QuestionRepeatStrategy {
        hasValidBackendSession ? self : .showAll
    }
}

final class QuestionRepeatStrategyStore {
    static let shared = QuestionRepeatStrategyStore()
    static let defaultsKey = "quizice.question-repeat-strategy"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var strategy: QuestionRepeatStrategy {
        get { QuestionRepeatStrategy(rawValue: defaults.string(forKey: Self.defaultsKey) ?? "") ?? .showAll }
        set { defaults.set(newValue.rawValue, forKey: Self.defaultsKey) }
    }
}

enum BackendRequestResult: String, Equatable {
    case success
    case cancelled
    case transportError = "transport_error"
    case httpError = "http_error"
    case decodingError = "decoding_error"
    case contractError = "contract_error"
}

struct BackendRequestMetric: Equatable {
    let operation: BackendOperation
    let result: BackendRequestResult
    let durationMilliseconds: Int
    let statusCode: Int?
    let responseBytes: Int
}

protocol BackendRequestMetricRecording {
    func record(_ metric: BackendRequestMetric)
}

struct NoopBackendRequestMetricRecorder: BackendRequestMetricRecording {
    func record(_ metric: BackendRequestMetric) {}
}

enum BackendContentError: Error, Equatable {
    case invalidRequest
    case invalidResponse
    case unauthenticated
    case transport(URLError.Code)
    case httpStatus(Int, BackendErrorEnvelope?)
    case encoding
    case decoding
    case contractViolation
    case timedOut
}

struct BackendThemeDTO: Decodable, Equatable {
    let id: String
    let name: String
    let description: String
    let sfSymbol: String
    let emoji: String
    let colorHex: String
    let isFavorite: Bool
    let countries: [String]

    init(
        id: String, name: String, description: String, sfSymbol: String,
        emoji: String, colorHex: String, isFavorite: Bool, countries: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.sfSymbol = sfSymbol
        self.emoji = emoji
        self.colorHex = colorHex
        self.isFavorite = isFavorite
        self.countries = countries
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, sfSymbol, emoji, colorHex, isFavorite, countries
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        description = try values.decode(String.self, forKey: .description)
        sfSymbol = try values.decode(String.self, forKey: .sfSymbol)
        emoji = try values.decode(String.self, forKey: .emoji)
        colorHex = try values.decode(String.self, forKey: .colorHex)
        isFavorite = try values.decode(Bool.self, forKey: .isFavorite)
        countries = try values.decodeIfPresent([String].self, forKey: .countries) ?? []
    }
}

struct BackendThemeCatalogResponse: Decodable, Equatable {
    let locale: String
    let themes: [BackendThemeDTO]
}

struct BackendThemePreferencesUpdate: Encodable, Equatable {
    let locale: String
    let favoriteThemeIds: [String]
}

struct BackendThemePreferencesResponse: Decodable, Equatable {
    let locale: String
    let favoriteThemeIds: [String]
}

protocol BackendAccessTokenProviding {
    func validAccessToken() -> String?
    func currentSession() -> AuthSession?
}

extension BackendAccessTokenProviding {
    func currentSession() -> AuthSession? { nil }
}

protocol BackendAuthenticationRecovering {
    func reauthenticate(afterRejectedAccessToken accessToken: String) async throws -> String
}

struct NotificationBackendAuthenticationRecoverer: BackendAuthenticationRecovering {
    private let sessionStore: SessionStoring
    private let notificationCenter: NotificationCenter
    private let now: () -> Date
    private let timeoutNanoseconds: UInt64

    init(
        sessionStore: SessionStoring = KeychainSessionStore(),
        notificationCenter: NotificationCenter = .default,
        now: @escaping () -> Date = Date.init,
        timeoutNanoseconds: UInt64 = 15_000_000_000
    ) {
        self.sessionStore = sessionStore
        self.notificationCenter = notificationCenter
        self.now = now
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    func reauthenticate(afterRejectedAccessToken accessToken: String) async throws -> String {
        guard let rejectedSession = try sessionStore.load(), rejectedSession.accessToken == accessToken else {
            throw BackendContentError.unauthenticated
        }
        notificationCenter.post(name: .backendAuthenticationInvalidated, object: nil)

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .nanoseconds(Int64(timeoutNanoseconds)))
        while clock.now < deadline {
            try Task.checkCancellation()
            if let session = try? sessionStore.load(),
               session.expiresAt > now(),
               !session.accessToken.isEmpty,
               session.accessToken != accessToken {
                guard session.userID == rejectedSession.userID else { throw BackendContentError.unauthenticated }
                return session.accessToken
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw BackendContentError.unauthenticated
    }
}

struct NoopBackendAccessTokenProvider: BackendAccessTokenProviding {
    func validAccessToken() -> String? { nil }
}

struct StoredBackendAccessTokenProvider: BackendAccessTokenProviding {
    private let sessionStore: SessionStoring
    private let now: () -> Date

    init(
        sessionStore: SessionStoring = KeychainSessionStore(),
        now: @escaping () -> Date = Date.init
    ) {
        self.sessionStore = sessionStore
        self.now = now
    }

    func currentSession() -> AuthSession? { try? sessionStore.load() }

    func validAccessToken() -> String? {
        do {
            guard
                let session = try sessionStore.load(),
                session.expiresAt > now()
            else { return nil }
            let token = session.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
            return token.isEmpty ? nil : token
        } catch {
            return nil
        }
    }
}

struct BackendQuestionDTO: Decodable, Equatable {
    let questionId: String?
    let questionVersion: Int?
    let question: String
    let answers: [String]
    let correctAnswer: String
    let explanation: String?
    let themeName: String?

    init(
        questionId: String? = nil,
        questionVersion: Int? = nil,
        question: String,
        answers: [String],
        correctAnswer: String,
        explanation: String?,
        themeName: String? = nil
    ) {
        self.questionId = questionId
        self.questionVersion = questionVersion
        self.question = question
        self.answers = answers
        self.correctAnswer = correctAnswer
        self.explanation = explanation
        self.themeName = themeName
    }

    func makeModel(locale: String? = nil) -> QuizQuestion {
        QuizQuestion(
            questionID: questionId,
            questionVersion: questionVersion,
            locale: locale,
            question: question,
            answers: answers,
            correctAnswer: correctAnswer,
            explanation: explanation,
            sourceThemeName: themeName
        )
    }
}

struct BackendQuestionBatchResponse: Decodable, Equatable {
    let locale: String
    let seed: String
    let progressMode: QuestionProgressMode?
    let country: String?
    let availableCount: Int
    let questions: [BackendQuestionDTO]

    enum CodingKeys: String, CodingKey {
        case locale, seed, progressMode, country, availableCount, questions
    }

    init(
        locale: String,
        seed: String,
        progressMode: QuestionProgressMode? = nil,
        country: String? = nil,
        availableCount: Int? = nil,
        questions: [BackendQuestionDTO]
    ) {
        self.locale = locale
        self.seed = seed
        self.progressMode = progressMode
        self.country = country
        self.availableCount = availableCount ?? questions.count
        self.questions = questions
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        locale = try values.decode(String.self, forKey: .locale)
        seed = try values.decode(String.self, forKey: .seed)
        progressMode = try values.decodeIfPresent(QuestionProgressMode.self, forKey: .progressMode)
        country = try values.decodeIfPresent(String.self, forKey: .country)
        questions = try values.decode([BackendQuestionDTO].self, forKey: .questions)
        availableCount = try values.decodeIfPresent(Int.self, forKey: .availableCount) ?? questions.count
    }
}

struct QuestionAnswerEvent: Codable, Equatable, Identifiable {
    let eventId: UUID
    let questionId: String
    let questionVersion: Int
    let locale: String
    let answer: String?
    let answeredAt: Date

    var id: UUID { eventId }

    enum CodingKeys: String, CodingKey {
        case eventId, questionId, questionVersion, locale, answer, answeredAt
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(eventId, forKey: .eventId)
        try values.encode(questionId, forKey: .questionId)
        try values.encode(questionVersion, forKey: .questionVersion)
        try values.encode(locale, forKey: .locale)
        if let answer {
            try values.encode(answer, forKey: .answer)
        } else {
            try values.encodeNil(forKey: .answer)
        }
        try values.encode(answeredAt, forKey: .answeredAt)
    }
}

struct QuestionAnswerBatchRequest: Encodable, Equatable {
    let events: [QuestionAnswerEvent]
}

struct QuestionAnswerBatchResponse: Decodable, Equatable {
    let processedEventIds: [UUID]
}

final class QuestionCountryStore {
    static let shared = QuestionCountryStore()
    static let defaultsKey = "quizice.question-country"
    static let supportedCodes: Set<String> = ["DE", "US", "ES", "FR", "IT", "RU"]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var country: String? {
        get {
            guard let code = defaults.string(forKey: Self.defaultsKey),
                  Self.supportedCodes.contains(code) else { return nil }
            return code
        }
        set {
            if let newValue, Self.supportedCodes.contains(newValue) {
                defaults.set(newValue, forKey: Self.defaultsKey)
            } else {
                defaults.removeObject(forKey: Self.defaultsKey)
            }
        }
    }
}
