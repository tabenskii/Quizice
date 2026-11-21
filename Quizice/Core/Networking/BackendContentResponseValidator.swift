import Foundation

enum BackendContentResponseValidator {
    static func isValid(
        _ response: BackendQuestionProgressResetResponse,
        requestedThemeID: String,
        requestedResetID: UUID
    ) -> Bool {
        guard response.themeId == requestedThemeID, response.resetId == requestedResetID else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if formatter.date(from: response.resetAt) != nil { return true }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: response.resetAt) != nil
    }

    static func isValid(
        _ response: BackendThemeCatalogResponse,
        requestedLocale: String
    ) -> Bool {
        guard response.locale == requestedLocale, !response.themes.isEmpty else { return false }
        var identifiers = Set<String>()
        return response.themes.allSatisfy { theme in
            let id = theme.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = theme.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let description = theme.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let sfSymbol = theme.sfSymbol.trimmingCharacters(in: .whitespacesAndNewlines)
            let emoji = theme.emoji.trimmingCharacters(in: .whitespacesAndNewlines)
            let colorHex = QuizThemeColor.normalizedHex(theme.colorHex)
            return !id.isEmpty
                && !name.isEmpty
                && !description.isEmpty
                && !sfSymbol.isEmpty
                && !emoji.isEmpty
                && colorHex == theme.colorHex
                && theme.countries.allSatisfy(QuestionCountryStore.supportedCodes.contains)
                && Set(theme.countries).count == theme.countries.count
                && identifiers.insert(id).inserted
        }
    }

    static func isValid(
        _ response: BackendThemePreferencesResponse,
        requestedLocale: String
    ) -> Bool {
        response.locale == requestedLocale
            && normalizedThemeIDs(response.favoriteThemeIds) == response.favoriteThemeIds
    }

    static func normalizedThemeIDs(_ themeIDs: [String]) -> [String] {
        var identifiers = Set<String>()
        return themeIDs.compactMap { themeID in
            let normalizedID = themeID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedID.isEmpty, identifiers.insert(normalizedID).inserted else { return nil }
            return normalizedID
        }
    }

    static func isValid(
        _ response: BackendQuestionBatchResponse,
        requestedCount: Int,
        requestedLocale: String,
        requestedSeed: String,
        requestedCountry: String?
    ) -> Bool {
        guard
            response.locale == requestedLocale,
            response.seed == requestedSeed,
            response.country == requestedCountry,
            response.questions.count <= requestedCount,
            response.availableCount >= response.questions.count
        else { return false }

        guard !response.isExhausted || (
            response.progressMode != nil && response.questions.isEmpty && response.availableCount == 0
        ) else { return false }

        var prompts = Set<String>()
        var questionIDs = Set<String>()
        return response.questions.allSatisfy { question in
            let questionID = question.questionId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let prompt = question.question.trimmingCharacters(in: .whitespacesAndNewlines)
            let answers = question.answers.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let correctAnswer = question.correctAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
            return !questionID.isEmpty
                && questionIDs.insert(questionID).inserted
                && (question.questionVersion ?? 0) > 0
                && !prompt.isEmpty
                && prompt.count <= 500
                && prompts.insert(prompt).inserted
                && answers.count == 4
                && answers.allSatisfy { !$0.isEmpty }
                && answers.allSatisfy { $0.count <= 300 }
                && Set(answers).count == answers.count
                && answers.filter { $0 == correctAnswer }.count == 1
        }
    }
}
