import Foundation

struct ThemeModel {
    let quizTheme: QuizTheme

    var themeID: String {
        quizTheme.stableID
    }

    var isAIGenerated: Bool {
        quizTheme.source == .ai
    }

    var aiGenerationConfiguration: AIQuizGenerationConfiguration? {
        quizTheme.aiGenerationConfiguration
    }

    var questionOrigin: QuizQuestionOrigin {
        quizTheme.questionOrigin
    }

    var difficulty: AIQuizDifficulty? {
        quizTheme.difficulty
    }

    var themeName: String {
        quizTheme.theme
    }
    
    var description: String {
        quizTheme.themeDescription
    }
    
    var questionsAndAnswers: [QuestionModel] {
        quizTheme.questions.map { QuestionModel(quizQuestion: $0) }
    }
}

extension QuizTheme {
    var stableID: String {
        id
    }

    /// A round must outlive catalog refreshes and mutations of cached model objects.
    func roundSnapshot() -> QuizTheme {
        QuizTheme(
            id: id, theme: theme, themeDescription: themeDescription,
            questions: questions.map { $0.roundSnapshot() },
            sfSymbolName: sfSymbolName, emoji: emoji, colorHex: colorHex,
            isFavorite: isFavorite, source: source, questionOrigin: questionOrigin,
            aiGenerationConfiguration: aiGenerationConfiguration, difficulty: difficulty,
            countries: countries
        )
    }
}
