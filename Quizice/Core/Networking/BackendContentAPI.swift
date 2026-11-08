import Foundation

protocol BackendContentAPI {
    func fetchFavorites() async throws -> BackendFavoritesSnapshot
    func patchFavorites(_ mutation: FavoriteMutation, session: AuthSession) async throws -> BackendFavoritesSnapshot

    func fetchRandomQuestions(
        selectionMode: CrossThemeQuestionSelectionMode, count: Int, locale: String,
        difficulty: AIQuizDifficulty, seed: String,
        strategy: QuestionRepeatStrategy, country: String?
    ) async throws -> BackendQuestionBatchResponse

    func fetchQuestions(
        themeID: String, count: Int, locale: String,
        difficulty: AIQuizDifficulty, seed: String,
        strategy: QuestionRepeatStrategy, country: String?
    ) async throws -> BackendQuestionBatchResponse

    func fetchThemes(locale: String) async throws -> BackendThemeCatalogResponse
    func fetchThemePreferences(locale: String) async throws -> BackendThemePreferencesResponse
    func replaceThemePreferences(
        locale: String,
        favoriteThemeIDs: [String]
    ) async throws -> BackendThemePreferencesResponse
    func fetchQuestions(
        themeID: String,
        count: Int,
        locale: String,
        seed: String
    ) async throws -> BackendQuestionBatchResponse
    func fetchQuestions(
        themeID: String,
        count: Int,
        locale: String,
        difficulty: AIQuizDifficulty,
        seed: String
    ) async throws -> BackendQuestionBatchResponse
    func fetchRandomQuestions(
        selectionMode: CrossThemeQuestionSelectionMode,
        count: Int,
        locale: String,
        seed: String
    ) async throws -> BackendQuestionBatchResponse
    func submitQuestionAnswers(_ events: [QuestionAnswerEvent], session: AuthSession) async throws -> QuestionAnswerBatchResponse
    func submitQuestionAnswers(_ events: [QuestionAnswerEvent]) async throws -> QuestionAnswerBatchResponse
    func fetchRandomQuestions(
        selectionMode: CrossThemeQuestionSelectionMode,
        count: Int,
        locale: String,
        difficulty: AIQuizDifficulty,
        seed: String
    ) async throws -> BackendQuestionBatchResponse
    func fetchQuestions(
        themeID: String,
        count: Int,
        locale: String,
        difficulty: AIQuizDifficulty,
        seed: String,
        strategy: QuestionRepeatStrategy
    ) async throws -> BackendQuestionBatchResponse
    func fetchRandomQuestions(
        selectionMode: CrossThemeQuestionSelectionMode,
        count: Int,
        locale: String,
        difficulty: AIQuizDifficulty,
        seed: String,
        strategy: QuestionRepeatStrategy
    ) async throws -> BackendQuestionBatchResponse
}

extension BackendContentAPI {
    func fetchFavorites() async throws -> BackendFavoritesSnapshot { throw BackendContentError.unauthenticated }
    func patchFavorites(_ mutation: FavoriteMutation, session: AuthSession) async throws -> BackendFavoritesSnapshot {
        throw BackendContentError.unauthenticated
    }

    func fetchQuestions(
        themeID: String, count: Int, locale: String,
        difficulty: AIQuizDifficulty, seed: String,
        strategy: QuestionRepeatStrategy, country: String?
    ) async throws -> BackendQuestionBatchResponse {
        guard country == nil else { throw BackendContentError.invalidRequest }
        return try await fetchQuestions(
            themeID: themeID, count: count, locale: locale,
            difficulty: difficulty, seed: seed, strategy: strategy
        )
    }

    func fetchRandomQuestions(
        selectionMode: CrossThemeQuestionSelectionMode, count: Int, locale: String,
        difficulty: AIQuizDifficulty, seed: String,
        strategy: QuestionRepeatStrategy, country: String?
    ) async throws -> BackendQuestionBatchResponse {
        guard country == nil else { throw BackendContentError.invalidRequest }
        return try await fetchRandomQuestions(
            selectionMode: selectionMode, count: count, locale: locale,
            difficulty: difficulty, seed: seed, strategy: strategy
        )
    }

    func submitQuestionAnswers(_ events: [QuestionAnswerEvent], session: AuthSession) async throws -> QuestionAnswerBatchResponse {
        try await submitQuestionAnswers(events)
    }
    func submitQuestionAnswers(_ events: [QuestionAnswerEvent]) async throws -> QuestionAnswerBatchResponse {
        throw BackendContentError.unauthenticated
    }
    func fetchQuestions(
        themeID: String,
        count: Int,
        locale: String,
        difficulty: AIQuizDifficulty,
        seed: String,
        strategy: QuestionRepeatStrategy
    ) async throws -> BackendQuestionBatchResponse {
        try await fetchQuestions(
            themeID: themeID,
            count: count,
            locale: locale,
            difficulty: difficulty,
            seed: seed
        )
    }

    func fetchRandomQuestions(
        selectionMode: CrossThemeQuestionSelectionMode,
        count: Int,
        locale: String,
        difficulty: AIQuizDifficulty,
        seed: String,
        strategy: QuestionRepeatStrategy
    ) async throws -> BackendQuestionBatchResponse {
        try await fetchRandomQuestions(
            selectionMode: selectionMode,
            count: count,
            locale: locale,
            difficulty: difficulty,
            seed: seed
        )
    }
    func fetchThemePreferences(locale: String) async throws -> BackendThemePreferencesResponse {
        throw BackendContentError.unauthenticated
    }

    func replaceThemePreferences(
        locale: String,
        favoriteThemeIDs: [String]
    ) async throws -> BackendThemePreferencesResponse {
        throw BackendContentError.unauthenticated
    }

    func fetchQuestions(
        themeID: String,
        count: Int,
        locale: String,
        difficulty: AIQuizDifficulty,
        seed: String
    ) async throws -> BackendQuestionBatchResponse {
        try await fetchQuestions(
            themeID: themeID,
            count: count,
            locale: locale,
            seed: seed
        )
    }

    func fetchRandomQuestions(
        selectionMode: CrossThemeQuestionSelectionMode,
        count: Int,
        locale: String,
        difficulty: AIQuizDifficulty,
        seed: String
    ) async throws -> BackendQuestionBatchResponse {
        try await fetchRandomQuestions(
            selectionMode: selectionMode,
            count: count,
            locale: locale,
            seed: seed
        )
    }
}
