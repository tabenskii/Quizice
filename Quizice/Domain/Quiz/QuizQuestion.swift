import Foundation

class QuizQuestion {
    var questionID: String?
    var questionVersion: Int?
    var locale: String?
    var question: String
    var answers: [String]
    var correctAnswer: String
    var explanation: String?
    var sourceThemeName: String?
    
    init(
        questionID: String? = nil,
        questionVersion: Int? = nil,
        locale: String? = nil,
        question: String,
        answers: [String],
        correctAnswer: String,
        explanation: String? = nil,
        sourceThemeName: String? = nil
    ) {
        self.questionID = questionID
        self.questionVersion = questionVersion
        self.locale = locale
        self.question = question
        self.answers = answers
        self.correctAnswer = correctAnswer
        self.explanation = explanation
        self.sourceThemeName = sourceThemeName
    }

    func roundSnapshot() -> QuizQuestion {
        QuizQuestion(
            questionID: questionID, questionVersion: questionVersion,
            locale: locale, question: question, answers: answers,
            correctAnswer: correctAnswer, explanation: explanation,
            sourceThemeName: sourceThemeName
        )
    }
}

struct QuizQuestionDTO: Decodable {
    let question: String
    let answers: [String]
    let correctAnswer: String
    let explanation: String?

    enum CodingKeys: String, CodingKey {
        case question
        case answers
        case correctAnswer
        case explanation
    }

    func makeModel() -> QuizQuestion {
        QuizQuestion(
            question: question,
            answers: answers,
            correctAnswer: correctAnswer,
            explanation: explanation
        )
    }
}
