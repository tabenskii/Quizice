import Foundation

extension HTTPBackendContentAPI {
    func fetchMusicGenres(locale: String) async throws -> [MusicGenre] {
        guard Self.isSupported(locale: locale) else { throw BackendContentError.invalidRequest }
        let url = try makeURL(
            pathComponents: ["v1", "themes", MusicGenre.themeID, "genres"],
            queryItems: [URLQueryItem(name: "locale", value: locale)]
        )
        let response: MusicGenresResponse = try await get(
            url: url, operation: .musicGenres, accessToken: nil,
            validate: { response in
                Set(response.genres.map(\.id)).count == response.genres.count
                    && response.genres.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty }
            }
        )
        return response.genres
    }

    func fetchQuestions(
        themeID: String, count: Int, locale: String, difficulty: AIQuizDifficulty, seed: String,
        strategy: QuestionRepeatStrategy, country: String?, musicGenreID: String?
    ) async throws -> BackendQuestionBatchResponse {
        try await fetchQuestionBatch(
            themeID: themeID, count: count, locale: locale, difficulty: difficulty,
            seed: seed, strategy: strategy, country: country, musicGenreID: musicGenreID
        )
    }
}

private struct MusicGenresResponse: Decodable {
    let genres: [MusicGenre]
}
