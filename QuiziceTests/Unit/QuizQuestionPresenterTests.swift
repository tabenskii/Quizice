import XCTest
@testable import Quizice

@MainActor
final class QuizQuestionPresenterTests: XCTestCase {
    private var suiteNames: [String] = []

    override func tearDown() {
        suiteNames.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }
        suiteNames.removeAll()
        super.tearDown()
    }

    func testLoadQuestionsClampsRequestedCountToUsableQuestionCount() {
        let session = QuestionPresenterSession()
        session.questionsCount = 99
        session.chosenTheme = ThemeModel(quizTheme: SnapshotSupport.makeTheme(
            id: "tech",
            name: "Tech",
            questions: [
                makeQuestion("One?", correctAnswer: "A"),
                makeQuestion("Two?", correctAnswer: "B")
            ]
        ))
        let presenter = QuizQuestionPresenter(session: session, statisticsStore: makeStatisticsHarness().store)

        presenter.loadQuestions()

        XCTAssertEqual(presenter.questionsTotalCount, 2)
        XCTAssertEqual(presenter.chosenThemeQuestionsArray.count, 2)
    }

    func testLoadQuestionBuildsViewModelAndStableAnswerFeedback() throws {
        let session = QuestionPresenterSession()
        session.questionsCount = 1
        session.chosenTheme = ThemeModel(quizTheme: SnapshotSupport.makeTheme(
            id: "music",
            name: "Music",
            questions: [makeQuestion(
                "Which answer is correct?",
                correctAnswer: "C",
                explanation: "C is the only correct answer."
            )]
        ))
        let view = QuestionPresenterViewSpy()
        let presenter = QuizQuestionPresenter(session: session, statisticsStore: makeStatisticsHarness().store)
        presenter.view = view

        presenter.loadQuestions()
        presenter.loadQuestion()

        let viewModel = try XCTUnwrap(view.loadedViewModels.first)
        let correctOption = try XCTUnwrap(viewModel.answers.first { $0.title == "C" })
        let wrongOption = try XCTUnwrap(viewModel.answers.first { $0.title != "C" })

        XCTAssertEqual(viewModel.themeName, "Music")
        XCTAssertEqual(viewModel.questionText, "Which answer is correct?")
        XCTAssertEqual(viewModel.questionNumberText, L10n.Question.number(1))
        XCTAssertEqual(viewModel.answers.count, 4)
        XCTAssertEqual(viewModel.explanation, "C is the only correct answer.")
        XCTAssertEqual(presenter.answerFeedback(for: correctOption.id), .correct)
        XCTAssertEqual(presenter.answerFeedback(for: wrongOption.id), .wrong)
    }

    func testRandomRoundShowsEachSourceThemeAfterShufflingAndKeepsSnapshot() throws {
        let music = makeQuestion("Music?", correctAnswer: "A")
        music.sourceThemeName = "Музыка"
        let technology = makeQuestion("Technology?", correctAnswer: "B")
        technology.sourceThemeName = "Технологии"
        let session = QuestionPresenterSession()
        session.chosenTheme = ThemeModel(quizTheme: SnapshotSupport.makeTheme(
            id: RandomQuizSelection.themeID, name: L10n.Home.randomSelection,
            questions: [music, technology]
        ))
        let view = QuestionPresenterViewSpy()
        let presenter = QuizQuestionPresenter(
            session: session, statisticsStore: makeStatisticsHarness().store,
            randomizer: QuizQuestionRandomizer(questions: { Array($0.reversed()) }, answers: { $0 })
        )
        presenter.view = view
        presenter.loadQuestions()
        music.sourceThemeName = "Changed after round started"
        technology.sourceThemeName = nil
        presenter.loadQuestion()

        XCTAssertEqual(view.loadedViewModels.last?.themeName, "Технологии")
        XCTAssertEqual(view.loadedViewModels.last?.questionText, "Technology?")
        presenter.checkAnswer(optionID: try XCTUnwrap(view.loadedViewModels.last?.answers.first?.id))
        presenter.checkQuestionNumberAndProceed()
        XCTAssertEqual(view.loadedViewModels.last?.themeName, "Музыка")
        XCTAssertEqual(view.loadedViewModels.last?.questionText, "Music?")
        XCTAssertEqual(presenter.themeID, RandomQuizSelection.themeID)
    }

    func testRandomRoundWithoutUsableSourceThemeKeepsRoundTitle() {
        for sourceThemeName in [nil, "", " \n "] as [String?] {
            let question = makeQuestion("Question?", correctAnswer: "A")
            question.sourceThemeName = sourceThemeName
            let session = QuestionPresenterSession()
            session.chosenTheme = ThemeModel(quizTheme: SnapshotSupport.makeTheme(
                id: RandomQuizSelection.themeID, name: L10n.Home.randomSelection, questions: [question]
            ))
            let view = QuestionPresenterViewSpy()
            let presenter = QuizQuestionPresenter(session: session, statisticsStore: makeStatisticsHarness().store)
            presenter.view = view
            presenter.viewDidLoad()

            XCTAssertEqual(view.loadedViewModels.last?.themeName, L10n.Home.randomSelection)
        }
    }

    func testRegularRoundKeepsItsTitleWhenQuestionHasSourceTheme() {
        let question = makeQuestion("Question?", correctAnswer: "A")
        question.sourceThemeName = "Other source"
        let session = QuestionPresenterSession()
        session.chosenTheme = ThemeModel(quizTheme: SnapshotSupport.makeTheme(
            id: "music", name: "Музыка", questions: [question]
        ))
        let view = QuestionPresenterViewSpy()
        let presenter = QuizQuestionPresenter(session: session, statisticsStore: makeStatisticsHarness().store)
        presenter.view = view
        presenter.viewDidLoad()

        XCTAssertEqual(view.loadedViewModels.last?.themeName, "Музыка")
    }

    func testCorrectAnswerRecordsSingleCompletedAttemptAndEmitsResult() throws {
        let harness = makeStatisticsHarness()
        let session = QuestionPresenterSession()
        session.questionsCount = 1
        session.chosenTheme = ThemeModel(quizTheme: SnapshotSupport.makeTheme(
            id: "culture",
            name: "Culture",
            questions: [makeQuestion("Question?", correctAnswer: "D")]
        ))
        let view = QuestionPresenterViewSpy()
        let presenter = QuizQuestionPresenter(session: session, statisticsStore: harness.store)
        presenter.view = view

        presenter.loadQuestions()
        presenter.loadQuestion()
        let loadedQuestion = try XCTUnwrap(view.loadedViewModels.first)
        let correctOption = try XCTUnwrap(loadedQuestion.answers.first { $0.title == "D" })

        presenter.checkAnswer(optionID: correctOption.id)
        presenter.checkQuestionNumberAndProceed()
        presenter.checkQuestionNumberAndProceed()

        XCTAssertEqual(view.answerStateUpdates, [true])
        XCTAssertEqual(view.results, [
            QuizResultState(correctAnswers: 1, totalQuestions: 1)
        ])
        XCTAssertEqual(harness.store.loadSummary().playedQuizzes, 1)
        XCTAssertEqual(harness.store.loadSummary().correctAnswers, 1)
    }

    func testWrongAnswerAndTimeExpiredProgressToResultWithoutCorrectCredit() throws {
        let harness = makeStatisticsHarness()
        let session = QuestionPresenterSession()
        session.questionsCount = 1
        session.chosenTheme = ThemeModel(quizTheme: SnapshotSupport.makeTheme(
            id: "politics",
            name: "Politics",
            questions: [makeQuestion("Question?", correctAnswer: "A")]
        ))
        let view = QuestionPresenterViewSpy()
        let presenter = QuizQuestionPresenter(session: session, statisticsStore: harness.store)
        presenter.view = view

        presenter.loadQuestions()
        presenter.loadQuestion()
        let loadedQuestion = try XCTUnwrap(view.loadedViewModels.first)
        let wrongOption = try XCTUnwrap(loadedQuestion.answers.first { $0.title != "A" })

        presenter.checkAnswer(optionID: wrongOption.id)
        presenter.checkQuestionNumberAndProceed()

        XCTAssertEqual(view.answerStateUpdates, [false])
        XCTAssertEqual(view.results, [QuizResultState(correctAnswers: 0, totalQuestions: 1)])
        XCTAssertEqual(harness.store.loadSummary().playedQuizzes, 1)
        XCTAssertEqual(harness.store.loadSummary().correctAnswers, 0)
    }

    func testResetGameProgressClearsTransientState() {
        let presenter = QuizQuestionPresenter(
            session: QuestionPresenterSession(),
            statisticsStore: makeStatisticsHarness().store
        )
        presenter.chosenThemeQuestionsArray = [QuestionModel(quizQuestion: makeQuestion("Question?", correctAnswer: "A"))]
        presenter.currentQuestionIndex = 3
        presenter.correctAnswers = 2
        presenter.currentProgress = 0.8

        presenter.resetGameProgress()

        XCTAssertTrue(presenter.chosenThemeQuestionsArray.isEmpty)
        XCTAssertNil(presenter.currentQuestion)
        XCTAssertEqual(presenter.questionsTotalCount, 0)
        XCTAssertEqual(presenter.currentQuestionIndex, 0)
        XCTAssertEqual(presenter.correctAnswers, 0)
        XCTAssertEqual(presenter.currentProgress, 0.2)
    }

    func testPauseAndResumeContinueFromRemainingTimerProgress() throws {
        let session = QuestionPresenterSession()
        session.questionsCount = 1
        session.chosenTheme = ThemeModel(quizTheme: SnapshotSupport.makeTheme(
            id: "timer",
            name: "Timer",
            questions: [makeQuestion("Question?", correctAnswer: "A")]
        ))
        let view = QuestionPresenterViewSpy()
        let clock = TestQuizTimerClient()
        let presenter = QuizQuestionPresenter(
            session: session,
            statisticsStore: makeStatisticsHarness().store,
            timerClient: clock.client
        )
        presenter.view = view
        presenter.loadQuestions()
        presenter.loadQuestion()

        presenter.startTimer()
        clock.tick()
        let progressBeforePause = try XCTUnwrap(view.progressUpdates.last)

        presenter.pauseTimer()
        let pausedUpdateCount = view.progressUpdates.count
        clock.tick()
        XCTAssertEqual(view.progressUpdates.count, pausedUpdateCount)

        presenter.resumeTimer()
        clock.tick()
        presenter.stopTimer()

        XCTAssertGreaterThan(view.progressUpdates.count, pausedUpdateCount)
        let firstResumedProgress = view.progressUpdates[pausedUpdateCount]
        XCTAssertLessThan(firstResumedProgress, progressBeforePause)
        XCTAssertLessThan(firstResumedProgress, 1)
    }

    func testAccessibilityModeSkipsTimerAndHidesTimerBar() throws {
        let session = QuestionPresenterSession()
        session.questionsCount = 1
        session.chosenTheme = ThemeModel(quizTheme: SnapshotSupport.makeTheme(
            id: "a11y",
            name: "A11y",
            questions: [makeQuestion("Question?", correctAnswer: "A")]
        ))
        let view = QuestionPresenterViewSpy()
        let clock = TestQuizTimerClient()
        let harness = makeStatisticsHarness()
        let presenter = QuizQuestionPresenter(
            session: session,
            statisticsStore: harness.store,
            timerClient: clock.client,
            accessibilityClient: .stub(active: true)
        )
        presenter.view = view

        presenter.viewDidLoad()
        presenter.startTimer()
        presenter.resumeTimer()

        XCTAssertEqual(view.hideTimerBarCallCount, 1, "viewDidLoad should hide the timer bar exactly once when a11y is active")
        XCTAssertFalse(clock.hasScheduledTick, "startTimer must not schedule ticks when a11y is active")
    }

    func testCompletedAttemptRecordsAccessibilityFlagWhenActive() throws {
        let harness = makeStatisticsHarness()
        let session = QuestionPresenterSession()
        session.questionsCount = 5
        session.chosenTheme = ThemeModel(quizTheme: SnapshotSupport.makeTheme(
            id: "a11y-attempt",
            name: "A11y Attempt",
            questions: (0..<5).map { makeQuestion("Question \($0)?", correctAnswer: "A") }
        ))
        let view = QuestionPresenterViewSpy()
        let presenter = QuizQuestionPresenter(
            session: session,
            statisticsStore: harness.store,
            accessibilityClient: .stub(active: true)
        )
        presenter.view = view

        presenter.viewDidLoad()
        for _ in 0..<5 {
            let option = try XCTUnwrap(view.loadedViewModels.last?.answers.first { $0.title == "A" })
            presenter.checkAnswer(optionID: option.id)
            presenter.checkQuestionNumberAndProceed()
        }
        presenter.checkQuestionNumberAndProceed()

        harness.store.activateAuthenticatedUser("a11y-user")
        let request = harness.store.makeSyncRequest(for: "a11y-user")
        XCTAssertEqual(request.attempts.count, 1)
        XCTAssertTrue(try XCTUnwrap(request.attempts.first?.accessibilityMode))
    }

    func testAnswerAndTimeoutRaceIsHandledExactlyOnce() throws {
        let session = QuestionPresenterSession()
        session.questionsCount = 1
        session.chosenTheme = ThemeModel(quizTheme: SnapshotSupport.makeTheme(
            id: "race",
            name: "Race",
            questions: [makeQuestion("Question?", correctAnswer: "A")]
        ))
        let view = QuestionPresenterViewSpy()
        let presenter = QuizQuestionPresenter(session: session, statisticsStore: makeStatisticsHarness().store)
        presenter.view = view
        presenter.loadQuestions()
        presenter.loadQuestion()
        let option = try XCTUnwrap(view.loadedViewModels.first?.answers.first { $0.title == "A" })

        presenter.checkAnswer(optionID: option.id)
        presenter.timeExpired()
        presenter.checkAnswer(optionID: option.id)
        presenter.checkQuestionNumberAndProceed()

        XCTAssertEqual(view.answerStateUpdates, [true])
        XCTAssertEqual(view.timeExpiredCallCount, 0)
        XCTAssertEqual(view.results, [QuizResultState(correctAnswers: 1, totalQuestions: 1)])
    }

#if DEBUG
    func testDebugQuestionSourceReflectsPreparedTheme() {
        let session = QuestionPresenterSession()
        session.chosenTheme = ThemeModel(quizTheme: QuizTheme(
            id: "remote",
            theme: "Remote",
            themeDescription: "",
            questions: [],
            source: .catalog,
            questionOrigin: .backend
        ))
        let presenter = QuizQuestionPresenter(
            session: session,
            statisticsStore: makeStatisticsHarness().store
        )

        XCTAssertEqual(presenter.questionOrigin, .backend)
        XCTAssertEqual(presenter.themeSource, .catalog)
    }

    func testDebugQuestionSourceIndicatorDistinguishesBackendFromLocal() {
        let viewController = QuizQuestionViewController()
        viewController.loadViewIfNeeded()

        viewController.configureDebugQuestionSource(origin: .backend, themeSource: .catalog)
        XCTAssertEqual(viewController.debugQuestionSourceLabel.text, "BACKEND")
        XCTAssertEqual(
            viewController.debugQuestionSourceLabel.backgroundColor,
            AppAssetColor.fallbackGreen.uiColor
        )

        viewController.configureDebugQuestionSource(origin: .bundled, themeSource: .catalog)
        XCTAssertEqual(viewController.debugQuestionSourceLabel.text, "LOCAL")
        XCTAssertEqual(
            viewController.debugQuestionSourceLabel.backgroundColor,
            AppAssetColor.fallbackOrange.uiColor
        )
        XCTAssertTrue(viewController.debugQuestionSourceLabel.isHidden)
    }

    func testDebugCatalogSourceIndicatorTitlesAreUnambiguous() {
        XCTAssertEqual(QuizViewController.DebugCatalogSourceState.loading.title, "CATALOG: LOADING")
        XCTAssertEqual(QuizViewController.DebugCatalogSourceState.backend.title, "CATALOG: BACKEND")
        XCTAssertEqual(
            QuizViewController.DebugCatalogSourceState.backendStale.title,
            "CATALOG: BACKEND STALE"
        )
        XCTAssertEqual(QuizViewController.DebugCatalogSourceState.local.title, "CATALOG: LOCAL")
    }
#endif

    func testDelayedTimerCallbackChargesElapsedTimeAndExpiresOnlyOnce() throws {
        let (presenter, view, clock) = makeTimerHarness()
        presenter.startTimer()
        clock.advance(by: 5)
        XCTAssertEqual(try XCTUnwrap(view.progressUpdates.last), 0.75, accuracy: 0.0001)
        clock.advance(by: 30)
        clock.advance(by: 1)
        presenter.timeExpired()
        presenter.checkQuestionNumberAndProceed()
        XCTAssertEqual(view.timeExpiredCallCount, 1)
        XCTAssertEqual(view.results, [QuizResultState(correctAnswers: 0, totalQuestions: 1)])
        XCTAssertFalse(clock.hasScheduledTick)
    }

    func testBackgroundPauseExcludesElapsedTimeAndKeepsNewQuestionPaused() throws {
        let (presenter, view, clock) = makeTimerHarness()
        presenter.startTimer()
        clock.advance(by: 5)
        presenter.pauseTimer()
        clock.advance(by: 60)
        presenter.resumeTimer()
        clock.advance(by: 5)
        XCTAssertEqual(try XCTUnwrap(view.progressUpdates.last), 0.5, accuracy: 0.0001)
        presenter.pauseTimer()
        presenter.startTimer() // An incoming card's animation may finish during an interruption.
        XCTAssertFalse(clock.hasScheduledTick)
        clock.advance(by: 60)
        presenter.resumeTimer()
        clock.advance(by: 5)
        XCTAssertEqual(try XCTUnwrap(view.progressUpdates.last), 0.75, accuracy: 0.0001)
        presenter.stopTimer()
    }

    func testActivationDuringNextQuestionTransitionDoesNotReuseExpiredTimer() {
        let (presenter, view, clock) = makeTimerHarness(questionCount: 2)
        presenter.startTimer()
        clock.advance(by: 20)
        XCTAssertEqual(view.timeExpiredCallCount, 1)
        presenter.checkQuestionNumberAndProceed()
        XCTAssertEqual(view.loadedViewModels.count, 2)
        // The second card is entering; its animation has not called startTimer yet.
        presenter.pauseTimer()
        presenter.resumeTimer()
        clock.advance(by: 30)
        XCTAssertEqual(view.timeExpiredCallCount, 1)
        XCTAssertFalse(clock.hasScheduledTick)
        presenter.startTimer()
        clock.advance(by: 19)
        XCTAssertEqual(view.timeExpiredCallCount, 1)
        clock.advance(by: 1)
        XCTAssertEqual(view.timeExpiredCallCount, 2)
    }

    func testCatalogMutationDoesNotChangeLoadedRoundOrCompletedStatistics() throws {
        let statistics = makeStatisticsHarness().store
        let original = SnapshotSupport.makeTheme(id: "music", name: "Music", questions: [
            QuizQuestion(questionID: "music:1", questionVersion: 1, locale: "en",
                         question: "Original?", answers: ["A", "B", "C", "D"], correctAnswer: "A")
        ])
        let session = QuestionPresenterSession()
        session.chosenTheme = ThemeModel(quizTheme: original)
        let view = QuestionPresenterViewSpy()
        let outbox = QuestionPresenterAnswerOutbox()
        let presenter = QuizQuestionPresenter(session: session, statisticsStore: statistics, answerOutbox: outbox)
        presenter.view = view
        presenter.viewDidLoad()
        original.theme = "Refreshed"
        original.questions[0].question = "Changed?"
        original.questions[0].correctAnswer = "B"
        original.questions[0].questionVersion = 2
        session.chosenTheme = nil
        let answer = try XCTUnwrap(view.loadedViewModels.last?.answers.first { $0.title == "A" })
        XCTAssertEqual(presenter.themeID, "music")
        XCTAssertEqual(presenter.currentQuestion?.questionText, "Original?")
        XCTAssertEqual(presenter.currentQuestion?.questionVersion, 1)
        XCTAssertEqual(presenter.answerFeedback(for: answer.id), .correct)
        presenter.checkAnswer(optionID: answer.id)
        presenter.checkQuestionNumberAndProceed()
        XCTAssertEqual(view.results, [QuizResultState(correctAnswers: 1, totalQuestions: 1)])
        XCTAssertEqual(statistics.loadSummary().correctAnswers, 1)
        let event = try XCTUnwrap(outbox.events.first)
        XCTAssertEqual(event.questionId, "music:1")
        XCTAssertEqual(event.questionVersion, 1)
        XCTAssertEqual(event.answer, "A")
    }

    func testEachPlayableRoundTracksItsActualCountAndEmptyRoundDoesNotStart() {
        let session = QuestionPresenterSession()
        session.questionsCount = 15
        session.chosenTheme = ThemeModel(quizTheme: SnapshotSupport.makeTheme(
            id: "partial", name: "Partial", questions: (0..<3).map { makeQuestion("Q\($0)?", correctAnswer: "A") }
        ))
        let analytics = InlineAIAnalyticsSpy()
        for _ in 0..<2 { // Replay creates a fresh presenter even when reusing the question screen.
            let presenter = QuizQuestionPresenter(session: session, statisticsStore: makeStatisticsHarness().store,
                                                  analytics: analytics)
            presenter.viewDidLoad()
        }
        session.chosenTheme = nil
        QuizQuestionPresenter(session: session, statisticsStore: makeStatisticsHarness().store,
                              analytics: analytics).viewDidLoad()
        XCTAssertEqual(analytics.quizStartedCount, 2)
        let counts = analytics.events.compactMap { event -> Int? in
            if case let .quizStarted(_, count) = event { return count }
            return nil
        }
        XCTAssertEqual(counts, [3, 3])
        XCTAssertEqual(session.questionsCount, 15, "The next request must preserve the selected round size")
    }

    private func makeTimerHarness(questionCount: Int = 1) -> (QuizQuestionPresenter, QuestionPresenterViewSpy, TestQuizTimerClient) {
        let session = QuestionPresenterSession()
        session.questionsCount = questionCount
        session.chosenTheme = ThemeModel(quizTheme: SnapshotSupport.makeTheme(
            id: "timer", name: "Timer",
            questions: (0..<questionCount).map { makeQuestion("Question \($0)?", correctAnswer: "A") }
        ))
        let view = QuestionPresenterViewSpy()
        let clock = TestQuizTimerClient()
        let presenter = QuizQuestionPresenter(session: session, statisticsStore: makeStatisticsHarness().store,
                                              timerClient: clock.client, accessibilityClient: .stub(active: false))
        presenter.view = view
        presenter.viewDidLoad()
        return (presenter, view, clock)
    }

    private func makeQuestion(
        _ text: String,
        correctAnswer: String,
        explanation: String? = nil
    ) -> QuizQuestion {
        QuizQuestion(
            question: text,
            answers: ["A", "B", "C", "D"],
            correctAnswer: correctAnswer,
            explanation: explanation
        )
    }

    func testSwitchingAccountsMidQuizKeepsAnswersAndStatisticsWithOriginalUser() async throws {
        let harness = makeStatisticsHarness()
        harness.store.activateAuthenticatedUser("A")
        let provider = ProgressSessionProvider()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let api = QuestionAnswerBackendContentAPI(submitResults: [])
        api.onSubmit = { QuestionAnswerBatchResponse(processedEventIds: $0.map(\.eventId)) }
        let outbox = PersistentQuestionAnswerOutbox(api: api, fileURL: url,
            automaticallySynchronizesOnEnqueue: false, sessionProvider: { provider.session })
        let session = QuestionPresenterSession()
        session.questionsCount = 1
        session.chosenTheme = ThemeModel(quizTheme: SnapshotSupport.makeTheme(
            id: "music", name: "Music", questions: [QuizQuestion(
                questionID: "music:1", questionVersion: 1, locale: "ru",
                question: "Question?", answers: ["A", "B", "C", "D"], correctAnswer: "A")]))
        let presenter = QuizQuestionPresenter(session: session, statisticsStore: harness.store, answerOutbox: outbox)
        let view = QuestionPresenterViewSpy()
        presenter.view = view
        presenter.viewDidLoad()
        provider.session = ProgressSessionProvider.session("B")
        harness.store.activateAuthenticatedUser("B")
        let answer = try XCTUnwrap(view.loadedViewModels.last?.answers.first { $0.title == "A" })
        presenter.checkAnswer(optionID: answer.id)
        presenter.checkQuestionNumberAndProceed()
        await outbox.synchronize()
        XCTAssertTrue(api.submittedBatches.isEmpty)
        XCTAssertEqual(harness.store.loadSummary(), .empty)
        provider.session = ProgressSessionProvider.session("A")
        harness.store.activateAuthenticatedUser("A")
        await outbox.synchronize()
        XCTAssertEqual(api.submittedSessions.map(\.userID), ["A"])
        XCTAssertEqual(harness.store.loadSummary().playedQuizzes, 1)
    }

    private func makeStatisticsHarness() -> (store: StatisticsStore, defaults: UserDefaults) {
        let suiteName = "QuizQuestionPresenterTests.\(UUID().uuidString)"
        suiteNames.append(suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (StatisticsStore(userDefaults: defaults, key: "attempts"), defaults)
    }
}

private final class TestQuizTimerClient {
    private var scheduledTick: (() -> Void)?

    var hasScheduledTick: Bool { scheduledTick != nil }

    private var now: TimeInterval = 0
    lazy var client = QuizTimerClient(
        now: { [weak self] in self?.now ?? 0 },
        scheduleRepeating: { [weak self] _, tick in
            self?.scheduledTick = tick
            return QuizTimerCancellation { [weak self] in self?.scheduledTick = nil }
        }
    )

    func tick() { advance(by: 0.02) }

    func advance(by duration: TimeInterval) {
        now += duration
        scheduledTick?()
    }
}

private final class QuestionPresenterSession: QuizSessionManaging {
    var themes: [QuizTheme]?
    var chosenTheme: ThemeModel?
    var questionsCount = 5
    var startup1st = false

    func loadTheme(themeID: String) -> Bool {
        guard let theme = themes?.first(where: { $0.stableID == themeID }) else {
            return false
        }
        chosenTheme = ThemeModel(quizTheme: theme)
        return true
    }
}

private final class QuestionPresenterViewSpy: QuizQuestionViewControllerProtocol {
    var presenter: QuizQuestionPresenterProtocol?
    private(set) var progressUpdates: [Float] = []
    private(set) var loadedViewModels: [QuizQuestionViewModel] = []
    private(set) var unavailableMessages: [(String?, String)] = []
    private(set) var answerStateUpdates: [Bool] = []
    private(set) var results: [QuizResultState] = []
    private(set) var timeExpiredCallCount = 0

    private(set) var hideTimerBarCallCount = 0

    func updateProgress(_ progress: Float) {
        progressUpdates.append(progress)
    }

    func showTimeExpired() {
        timeExpiredCallCount += 1
    }

    func hideTimerBar() {
        hideTimerBarCallCount += 1
    }

    func loadQuestionToView(_ viewModel: QuizQuestionViewModel) {
        loadedViewModels.append(viewModel)
    }

    func showQuestionUnavailable(themeName: String?, message: String) {
        unavailableMessages.append((themeName, message))
    }

    func correctAnswerTapped(isTrue: Bool) {
        answerStateUpdates.append(isTrue)
    }

    func showResults(_ result: QuizResultState) {
        results.append(result)
    }
}

private final class QuestionPresenterAnswerOutbox: QuestionAnswerOutboxing {
    private(set) var events: [QuestionAnswerEvent] = []
    func enqueue(_ event: QuestionAnswerEvent) { events.append(event) }
    func synchronize() async {}
}
