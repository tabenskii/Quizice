import Foundation

enum QuizPreparationError: Error, Equatable {
    case unavailable
    case insufficientQuestions
    case progressComplete(userID: String)

    static func isCancellation(_ error: Error) -> Bool {
        switch error {
        case is CancellationError:
            return true
        case let error as URLError:
            return error.code == .cancelled
        case BackendContentError.transport(.cancelled), BackendAPIError.transport(.cancelled):
            return true
        default:
            return false
        }
    }

    static func message(for error: Error) -> String {
        switch error {
        case QuizPreparationError.unavailable:
            return L10n.Question.unavailableMessage
        case QuizPreparationError.insufficientQuestions:
            return L10n.Question.insufficientQuestionsMessage
        case QuizPreparationError.progressComplete:
            return L10n.Question.unavailableMessage
        case let error as URLError:
            return message(for: error.code)
        case BackendContentError.transport(let code), BackendAPIError.transport(let code):
            return message(for: code)
        default:
            return L10n.Question.loadingFailedMessage
        }
    }

    private static func message(for code: URLError.Code) -> String {
        switch code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return L10n.Question.networkFailureMessage
        default:
            return L10n.Question.loadingFailedMessage
        }
    }
}

enum QuizCatalogOrigin: String, Equatable {
    case bundled
    case backend
}

enum CrossThemeQuestionSelectionMode: String, CaseIterable, Equatable {
    case random
    case randomBalanced = "random_balanced"
}

protocol ThemeRepository: AnyObject {
    var themes: [QuizTheme]? { get }
    var catalogOrigin: QuizCatalogOrigin { get }
    func validateQuestionProgressUser(expectedUserID: String) throws
    func resetQuestionProgress(themeID: String, resetID: UUID, expectedUserID: String) async throws
    func loadData(forceReload: Bool)
    func fetchQuizThemes() -> [QuizTheme]
    @discardableResult
    func refreshBackendCatalog(locale: String) async -> Bool
    @discardableResult
    func synchronizeThemePreferences(locale: String) async -> Bool
    func prepareQuiz(
        themeID: String,
        questionCount: Int,
        locale: String
    ) async throws -> QuizTheme
    func prepareQuiz(
        themeID: String,
        questionCount: Int,
        difficulty: AIQuizDifficulty,
        locale: String
    ) async throws -> QuizTheme
    func prepareRandomQuiz(
        selectionMode: CrossThemeQuestionSelectionMode,
        localFallback: QuizTheme,
        questionCount: Int,
        locale: String
    ) async throws -> QuizTheme
    func prepareRandomQuiz(
        selectionMode: CrossThemeQuestionSelectionMode,
        localFallback: QuizTheme,
        questionCount: Int,
        difficulty: AIQuizDifficulty,
        locale: String
    ) async throws -> QuizTheme
}

extension ThemeRepository {
    func validateQuestionProgressUser(expectedUserID: String) throws {
        throw QuestionAnswerSyncError.accountChanged
    }

    func resetQuestionProgress(themeID: String, resetID: UUID, expectedUserID: String) async throws {
        throw QuizPreparationError.unavailable
    }

    var catalogOrigin: QuizCatalogOrigin { .bundled }

    @discardableResult
    func refreshBackendCatalog(locale: String) async -> Bool { false }

    @discardableResult
    func synchronizeThemePreferences(locale: String) async -> Bool { false }

    func prepareQuiz(
        themeID: String,
        questionCount: Int,
        locale: String
    ) async throws -> QuizTheme {
        let catalog = themes ?? fetchQuizThemes()
        guard
            QuizQuestionCountPolicy.supportedCounts.contains(questionCount),
            let theme = catalog.first(where: { $0.stableID == themeID })
        else {
            throw QuizPreparationError.unavailable
        }

        let questions = theme.questions.filter {
            QuizQuestionCountPolicy.isUsable(QuestionModel(quizQuestion: $0))
        }
        guard questions.count >= questionCount else {
            throw QuizPreparationError.unavailable
        }

        return QuizTheme(
            id: theme.id,
            theme: theme.theme,
            themeDescription: theme.themeDescription,
            questions: Array(questions.shuffled().prefix(questionCount)),
            sfSymbolName: theme.sfSymbolName,
            emoji: theme.emoji,
            colorHex: theme.colorHex,
            isFavorite: theme.isFavorite,
            source: theme.source,
            questionOrigin: theme.questionOrigin
        )
    }

    func prepareQuiz(
        themeID: String,
        questionCount: Int,
        difficulty: AIQuizDifficulty,
        locale: String
    ) async throws -> QuizTheme {
        let theme = try await prepareQuiz(
            themeID: themeID,
            questionCount: questionCount,
            locale: locale
        )
        theme.difficulty = difficulty
        return theme
    }

    func prepareRandomQuiz(
        selectionMode: CrossThemeQuestionSelectionMode,
        localFallback: QuizTheme,
        questionCount: Int,
        locale: String
    ) async throws -> QuizTheme {
        localFallback
    }

    func prepareRandomQuiz(
        selectionMode: CrossThemeQuestionSelectionMode,
        localFallback: QuizTheme,
        questionCount: Int,
        difficulty: AIQuizDifficulty,
        locale: String
    ) async throws -> QuizTheme {
        let theme = try await prepareRandomQuiz(
            selectionMode: selectionMode,
            localFallback: localFallback,
            questionCount: questionCount,
            locale: locale
        )
        theme.difficulty = difficulty
        return theme
    }
}
