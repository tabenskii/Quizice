import Foundation

struct QuizAnswerOption: Equatable, Identifiable {
    let id: String
    let title: String
}

enum QuizAnswerFeedback: Equatable {
    case normal
    case correct
    case wrong
}

struct QuizQuestionViewModel: Equatable {
    let themeName: String
    let questionText: String
    let questionNumberText: String
    let answers: [QuizAnswerOption]
    let explanation: String?

    init(
        themeName: String,
        questionText: String,
        questionNumberText: String,
        answers: [QuizAnswerOption],
        explanation: String? = nil
    ) {
        self.themeName = themeName
        self.questionText = questionText
        self.questionNumberText = questionNumberText
        self.answers = answers
        self.explanation = explanation
    }
}

struct QuizResultState: Equatable {
    let correctAnswers: Int
    let totalQuestions: Int
}

struct QuestionModel {
    let quizQuestion: QuizQuestion

    var questionText: String {
        quizQuestion.question
    }

    var answers: [String] {
        quizQuestion.answers
    }

    var correctAnswer: String {
        quizQuestion.correctAnswer
    }

    var explanation: String? {
        quizQuestion.explanation
    }

    var questionID: String? { quizQuestion.questionID }
    var questionVersion: Int? { quizQuestion.questionVersion }
    var progressGeneration: UUID? { quizQuestion.progressGeneration }
    var locale: String? { quizQuestion.locale }
}
