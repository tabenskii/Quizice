import Foundation

struct AIQuizGenerationConfiguration: Equatable {
    static let supportedQuestionCounts = [5, 10, 15]
    static let maximumThemeLength = 120

    let theme: String
    let questionCount: Int
    let difficulty: AIQuizDifficulty
    let locale: Locale
}

enum QuizThemeSource: String, Codable, Equatable {
    case catalog
    case ai
}

enum QuizQuestionOrigin: String, Codable, Equatable {
    case bundled
    case backend
    case directAI = "direct_ai"
    case mock
}

class QuizTheme {
    static let defaultSFSymbolName = "questionmark.square.dashed"
    static let defaultEmoji = "❓"

    var id: String
    var theme: String
    var themeDescription: String
    var sfSymbolName: String
    var emoji: String
    var colorHex: String?
    var isFavorite: Bool
    var sourceRawValue: String?
    var questions: [QuizQuestion]
    var aiGenerationConfiguration: AIQuizGenerationConfiguration?
    var questionOrigin: QuizQuestionOrigin
    var difficulty: AIQuizDifficulty?
    var countries: [String]
    
    init(
        id: String,
        theme: String,
        themeDescription: String,
        questions: [QuizQuestion],
        sfSymbolName: String = QuizTheme.defaultSFSymbolName,
        emoji: String = QuizTheme.defaultEmoji,
        colorHex: String? = nil,
        isFavorite: Bool = false,
        source: QuizThemeSource = .catalog,
        questionOrigin: QuizQuestionOrigin = .bundled,
        aiGenerationConfiguration: AIQuizGenerationConfiguration? = nil,
        difficulty: AIQuizDifficulty? = nil,
        countries: [String] = []
    ) {
        self.id = id
        self.theme = theme
        self.themeDescription = themeDescription
        self.sfSymbolName = sfSymbolName
        self.emoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? QuizTheme.defaultEmoji
            : emoji
        self.colorHex = QuizThemeColor.normalizedHex(colorHex)
        self.isFavorite = isFavorite
        self.sourceRawValue = source.rawValue
        self.questions = questions
        self.questionOrigin = questionOrigin
        self.aiGenerationConfiguration = aiGenerationConfiguration
        self.difficulty = difficulty
        self.countries = countries
    }

    var source: QuizThemeSource {
        QuizThemeSource(rawValue: sourceRawValue ?? "") ?? .catalog
    }
}

enum RandomQuizSelection {
    static let themeID = "random-selection"
    static let questionCount = 5

    static func makeTheme(
        from themes: [QuizTheme],
        excluding previousQuestions: [QuizQuestion] = [],
        title: String,
        description: String,
        randomizing: ([QuizQuestion]) -> [QuizQuestion]
    ) -> QuizTheme? {
        let usableQuestions = themes
            .flatMap(\.questions)
            .filter { question in
                QuizQuestionCountPolicy.isUsable(QuestionModel(quizQuestion: question))
            }
        let usableQuestionIDs = Set(usableQuestions.map(ObjectIdentifier.init))
        var seenQuestionIDs = Set<ObjectIdentifier>()
        let randomizedQuestions = randomizing(usableQuestions).filter { question in
            let identifier = ObjectIdentifier(question)
            return usableQuestionIDs.contains(identifier) && seenQuestionIDs.insert(identifier).inserted
        }

        let previousSignatures = Set(previousQuestions.map(QuestionSignature.init))
        let unseenQuestions = randomizedQuestions.filter {
            !previousSignatures.contains(QuestionSignature(question: $0))
        }
        let repeatedQuestions = randomizedQuestions.filter {
            previousSignatures.contains(QuestionSignature(question: $0))
        }
        let selectedQuestions = Array((unseenQuestions + repeatedQuestions).prefix(questionCount))
        guard selectedQuestions.count == questionCount else { return nil }

        // Keep round metadata separate from the shared catalog questions.
        let roundQuestions = selectedQuestions.map { question in
            let snapshot = question.roundSnapshot()
            snapshot.sourceThemeName = themes.first { theme in
                theme.questions.contains { $0 === question }
            }?.theme
            return snapshot
        }

        return QuizTheme(
            id: themeID,
            theme: title,
            themeDescription: description,
            questions: roundQuestions
        )
    }

    private struct QuestionSignature: Hashable {
        let question: String
        let answers: [String]
        let correctAnswer: String

        init(question: QuizQuestion) {
            self.question = question.question
            answers = question.answers
            correctAnswer = question.correctAnswer
        }
    }
}

struct QuizThemeDTO: Decodable {
    let id: String
    let theme: String
    let themeDescription: String
    let sfSymbol: String
    let emoji: String
    let colorHex: String?
    let questions: [QuizQuestionDTO]

    func makeModel() -> QuizTheme {
        QuizTheme(
            id: id,
            theme: theme,
            themeDescription: themeDescription,
            questions: questions.map { $0.makeModel() },
            sfSymbolName: sfSymbol,
            emoji: emoji,
            colorHex: colorHex
        )
    }
}

enum QuizThemeColor {
    static func normalizedHex(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        return "#\(digits.uppercased())"
    }
}
