import Foundation

final class QuizQuestionPresenter: QuizQuestionPresenterProtocol {
    private let session: QuizSessionManaging
    private let statisticsStore: StatisticsStore
    private let analytics: AnalyticsTracking
    private let timerClient: QuizTimerClient
    private let randomizer: QuizQuestionRandomizer
    private let accessibilityClient: AccessibilityModeClient
    private let answerOutbox: QuestionAnswerOutboxing

    weak var view: QuizQuestionViewControllerProtocol?

    private var timerCancellation: QuizTimerCancellation?
    private var roundTheme: ThemeModel?
    private var timerDeadline: TimeInterval?
    private var isTimerPaused = false
    private var hasStartedQuestionTimer = false
    private var hasTrackedStart = false
    private var remainingTime: TimeInterval = 20
    private let totalTime: TimeInterval = 20
    private let tickInterval: TimeInterval = 0.02

    var chosenThemeQuestionsArray: [QuestionModel] = []
    var currentQuestion: QuestionModel?
    var questionsTotalCount: Int?
    var currentQuestionIndex: Int = 0
    var correctAnswers: Int = 0
    var currentProgress: Float = 0.2
    private var hasRecordedCompletedAttempt = false
    private var currentAnswerOptions: [QuizAnswerOption] = []
    private var questionPhase: QuestionPhase = .unavailable
    // Captured once when the quiz starts so mid-session assistive-tech toggling
    // doesn't split a single attempt across two scoring tracks.
    private var isAccessibilityAtStart = false
    private var answerUserID: String?
    private var statisticsUserID: String?
    var themeID: String? {
        (roundTheme ?? session.chosenTheme)?.themeID
    }
    var analyticsTheme: AnalyticsTheme {
        (roundTheme ?? session.chosenTheme)?.analyticsTheme ?? .unknown
    }
#if DEBUG
    var questionOrigin: QuizQuestionOrigin {
        (roundTheme ?? session.chosenTheme)?.questionOrigin ?? .bundled
    }
    var themeSource: QuizThemeSource {
        (roundTheme ?? session.chosenTheme)?.quizTheme.source ?? .catalog
    }
#endif
    
    init(
        session: QuizSessionManaging = QuizSessionStore.shared,
        statisticsStore: StatisticsStore = StatisticsStore(),
        analytics: AnalyticsTracking = AppMetricaAnalyticsTracker.shared,
        timerClient: QuizTimerClient = .live,
        randomizer: QuizQuestionRandomizer = .live,
        accessibilityClient: AccessibilityModeClient = .live,
        answerOutbox: QuestionAnswerOutboxing = PersistentQuestionAnswerOutbox.shared
    ) {
        self.session = session
        self.statisticsStore = statisticsStore
        self.analytics = analytics
        self.timerClient = timerClient
        self.randomizer = randomizer
        self.accessibilityClient = accessibilityClient
        self.answerOutbox = answerOutbox
    }

    deinit {
        timerCancellation?.cancel()
        timerCancellation = nil
    }

    func viewDidLoad() {
        resetGameProgress()
        isAccessibilityAtStart = accessibilityClient.isActive()
        loadQuestions()
        loadQuestion()
        if let questionsTotalCount, questionsTotalCount > 0, !hasTrackedStart {
            hasTrackedStart = true
            analytics.track(.quizStarted(theme: analyticsTheme, questionCount: questionsTotalCount))
        }
        if isAccessibilityAtStart {
            view?.hideTimerBar()
        }
    }
    
    // MARK: - Timer methods
    
    func startTimer() {
        guard !isAccessibilityAtStart else { return }
        guard hasActiveQuestion, questionPhase == .awaitingAnswer else {
            stopTimer()
            view?.updateProgress(0)
            return
        }

        stopTimer()
        remainingTime = totalTime
        hasStartedQuestionTimer = true
        view?.updateProgress(1.0)

        if !isTimerPaused { scheduleTimer() }
    }

    func pauseTimer() {
        isTimerPaused = true
        updateRemainingTime()
        stopTimer()
    }

    func resumeTimer() {
        isTimerPaused = false
        guard !isAccessibilityAtStart, hasStartedQuestionTimer,
              hasActiveQuestion, questionPhase == .awaitingAnswer else { return }
        guard timerCancellation == nil else { return }
        if remainingTime <= 0 {
            timeExpired()
        } else {
            scheduleTimer()
        }
    }

    private func scheduleTimer() {
        timerDeadline = timerClient.now() + remainingTime
        timerCancellation = timerClient.scheduleRepeating(tickInterval) { [weak self] in
            guard let self else { return }
            self.updateRemainingTime()
            if self.remainingTime <= 0 {
                self.timeExpired()
            }
        }
    }

    private func updateRemainingTime() {
        guard let timerDeadline else { return }
        remainingTime = max(0, timerDeadline - timerClient.now())
        view?.updateProgress(Float(remainingTime / totalTime))
    }
    
    func timeExpired() {
        guard beginAnswering() else { return }
        enqueueCurrentAnswer(nil)
        trackAnswer(outcome: .timeout)
        view?.showTimeExpired()
        updateQuizState(isCorrect: false)
    }
    
    func stopTimer() {
        timerCancellation?.cancel()
        timerCancellation = nil
        timerDeadline = nil
    }
    
    // MARK: - Methods
    
    func loadQuestions() {
        answerUserID = answerOutbox.currentUserID
        statisticsUserID = statisticsStore.activeUserID
        roundTheme = session.chosenTheme.map { ThemeModel(quizTheme: $0.quizTheme.roundSnapshot()) }
        guard let chosenTheme = roundTheme else {
            chosenThemeQuestionsArray = []
            questionsTotalCount = 0
            return
        }
        
        let usableQuestions = chosenTheme.questionsAndAnswers.filter { question in
            !question.questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            question.answers.count >= 4 &&
            !question.correctAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            question.answers.filter { $0 == question.correctAnswer }.count == 1
        }
        
        guard !usableQuestions.isEmpty else {
            chosenThemeQuestionsArray = []
            questionsTotalCount = 0
            return
        }
        
        let requestedCount = session.questionsCount > 0 ? session.questionsCount : usableQuestions.count
        let clampedCount = min(requestedCount, usableQuestions.count)
        questionsTotalCount = max(clampedCount, 1)
        chosenThemeQuestionsArray = Array(randomizer.questions(usableQuestions).prefix(questionsTotalCount ?? usableQuestions.count))
        AppLog.quiz.debug("Loaded questions: \(self.chosenThemeQuestionsArray.count)")
    }
    
    func loadQuestion() {
        stopTimer()
        hasStartedQuestionTimer = false
        guard hasActiveQuestion else {
            questionPhase = .unavailable
            currentQuestion = nil
            currentAnswerOptions = []
            stopTimer()
            view?.updateProgress(0)
            view?.showQuestionUnavailable(
                themeName: roundTheme?.themeName, message: L10n.Question.unavailableMessage
            )
            return
        }
        
        let question = chosenThemeQuestionsArray[currentQuestionIndex]
        currentQuestion = question
        questionPhase = .awaitingAnswer
        
        let sourceThemeName = question.quizQuestion.sourceThemeName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let themeName: String
        if roundTheme?.themeID == RandomQuizSelection.themeID,
           let sourceThemeName, !sourceThemeName.isEmpty {
            themeName = sourceThemeName
        } else {
            themeName = roundTheme?.themeName ?? L10n.Question.fallbackTheme
        }
        currentAnswerOptions = makeAnswerOptions(for: question)
        let questionNumberText = L10n.Question.number(currentQuestionIndex + 1)
        
        view?.loadQuestionToView(
            QuizQuestionViewModel(
                themeName: themeName,
                questionText: question.questionText,
                questionNumberText: questionNumberText,
                answers: currentAnswerOptions,
                explanation: question.explanation
            )
        )
    }
    
    private func updateQuizState(isCorrect: Bool) {
        guard hasActiveQuestion else { return }
        
        if isCorrect {
            correctAnswers += 1
        }
        
        currentQuestionIndex += 1
        if let questionsTotalCount, questionsTotalCount > 0 {
            currentProgress = Float(currentQuestionIndex + 1) / Float(questionsTotalCount)
        }
    }
    
    func answerFeedback(for optionID: String) -> QuizAnswerFeedback {
        guard hasActiveQuestion else { return .normal }
        return optionID == correctAnswerOptionID ? .correct : .wrong
    }
    
    private func isCorrectAnswer(optionID: String) -> Bool {
        guard hasActiveQuestion else { return false }
        return optionID == correctAnswerOptionID
    }
    
    func checkAnswer(optionID: String) {
        guard beginAnswering() else { return }
        let selectedAnswer = currentAnswerOptions.first(where: { $0.id == optionID })?.title
        enqueueCurrentAnswer(selectedAnswer)
        let isCorrect = isCorrectAnswer(optionID: optionID)
        trackAnswer(outcome: isCorrect ? .correct : .incorrect)
        view?.correctAnswerTapped(isTrue: isCorrect)
        updateQuizState(isCorrect: isCorrect)
    }
    
    func checkQuestionNumberAndProceed() {
        stopTimer()
        guard questionPhase == .answered else { return }
        guard let questionsTotalCount, questionsTotalCount > 0 else { return }
        
        if currentQuestionIndex >= questionsTotalCount {
            questionPhase = .completed
            recordCompletedAttemptIfNeeded(totalQuestions: questionsTotalCount)
            view?.showResults(QuizResultState(correctAnswers: correctAnswers, totalQuestions: questionsTotalCount))
        } else {
            loadQuestion()
        }
    }
    
    func resetGameProgress() {
        stopTimer()
        remainingTime = totalTime
        chosenThemeQuestionsArray = []
        currentQuestion = nil
        currentAnswerOptions = []
        questionsTotalCount = 0
        currentQuestionIndex = 0
        correctAnswers = 0
        currentProgress = 0.2
        hasRecordedCompletedAttempt = false
        questionPhase = .unavailable
        isAccessibilityAtStart = false
        isTimerPaused = false
        hasStartedQuestionTimer = false
        hasTrackedStart = false
        roundTheme = nil
    }

    private func recordCompletedAttemptIfNeeded(totalQuestions: Int) {
        guard hasRecordedCompletedAttempt == false, totalQuestions > 0 else { return }
        hasRecordedCompletedAttempt = true
        statisticsStore.recordAttempt(
            correctAnswers: correctAnswers,
            totalQuestions: totalQuestions,
            accessibilityMode: isAccessibilityAtStart,
            for: statisticsUserID
        )
        analytics.track(
            .quizCompleted(
                theme: analyticsTheme,
                correctAnswers: correctAnswers,
                totalQuestions: totalQuestions
            )
        )
    }

    var analyticsProgress: AnalyticsQuizProgress {
        AnalyticsQuizProgress(
            theme: analyticsTheme,
            answeredQuestions: currentQuestionIndex,
            totalQuestions: questionsTotalCount ?? 0,
            correctAnswers: correctAnswers
        )
    }

    private func trackAnswer(outcome: AnalyticsAnswerOutcome) {
        guard let questionsTotalCount, questionsTotalCount > 0 else { return }
        analytics.track(
            .quizAnswered(
                theme: analyticsTheme,
                questionIndex: currentQuestionIndex + 1,
                totalQuestions: questionsTotalCount,
                outcome: outcome
            )
        )
    }

    private func beginAnswering() -> Bool {
        guard hasActiveQuestion, questionPhase == .awaitingAnswer else { return false }
        questionPhase = .answered
        stopTimer()
        return true
    }

    private func enqueueCurrentAnswer(_ answer: String?) {
        guard
            let question = currentQuestion,
            let questionID = question.questionID,
            let questionVersion = question.questionVersion,
            let locale = question.locale
        else { return }
        answerOutbox.enqueue(
            QuestionAnswerEvent(
                eventId: UUID(),
                questionId: questionID,
                questionVersion: questionVersion,
                locale: locale,
                answer: answer,
                answeredAt: Date(),
                progressGeneration: question.progressGeneration
            ),
            for: answerUserID
        )
    }
    
    private var hasActiveQuestion: Bool {
        guard let questionsTotalCount, questionsTotalCount > 0 else { return false }
        return !chosenThemeQuestionsArray.isEmpty &&
        currentQuestionIndex >= 0 &&
        currentQuestionIndex < questionsTotalCount &&
        currentQuestionIndex < chosenThemeQuestionsArray.count &&
        chosenThemeQuestionsArray[currentQuestionIndex].answers.count >= 4
    }
    
    private func makeAnswerOptions(for question: QuestionModel) -> [QuizAnswerOption] {
        var selectedAnswers = Array(randomizer.answers(question.answers).prefix(4))
        if !selectedAnswers.contains(question.correctAnswer), question.answers.contains(question.correctAnswer), !selectedAnswers.isEmpty {
            selectedAnswers.removeLast()
            selectedAnswers.append(question.correctAnswer)
            selectedAnswers = randomizer.answers(selectedAnswers)
        }
        return selectedAnswers.enumerated().map { index, answer in
            QuizAnswerOption(id: "\(currentQuestionIndex)-\(index)-\(answer.hashValue)", title: answer)
        }
    }
    
    private var correctAnswerOptionID: String? {
        guard hasActiveQuestion else { return nil }
        let correctAnswer = chosenThemeQuestionsArray[currentQuestionIndex].correctAnswer
        let matches = currentAnswerOptions.filter { $0.title == correctAnswer }
        return matches.count == 1 ? matches[0].id : nil
    }
}

private enum QuestionPhase {
    case unavailable
    case awaitingAnswer
    case answered
    case completed
}

struct QuizTimerCancellation {
    let cancel: () -> Void
}

struct QuizTimerClient {
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    var scheduleRepeating: (_ interval: TimeInterval, _ tick: @escaping () -> Void) -> QuizTimerCancellation

    static let live = Self { interval, tick in
        let timer = Timer(timeInterval: interval, repeats: true) { _ in tick() }
        RunLoop.main.add(timer, forMode: .common)
        return QuizTimerCancellation { timer.invalidate() }
    }
}

struct QuizQuestionRandomizer {
    var questions: ([QuestionModel]) -> [QuestionModel]
    var answers: ([String]) -> [String]

    static let live = Self(
        questions: { $0.shuffled() },
        answers: { $0.shuffled() }
    )
}
