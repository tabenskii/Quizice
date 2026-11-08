import XCTest
@testable import Quizice

@MainActor
class CrossScreenVisualTestCase: XCTestCase {
    override func setUp() {
        super.setUp()
        AppLocalizationStore.shared.languagePreference = .russian
        resetQuestionFactoryState()
        UserDefaults.standard.set(AppDesignStyle.clean.rawValue, forKey: AppAppearanceStore.Keys.designStyle)
        // Pin the clean color scheme so shadow/surface assertions are deterministic
        // regardless of the host simulator's system light/dark appearance.
        UserDefaults.standard.set(CleanColorSchemePreference.light.rawValue, forKey: AppAppearanceStore.Keys.cleanColorScheme)
        UserDefaults.standard.set(AppBackgroundStyle.defaultStyle.rawValue, forKey: AppAppearanceStore.Keys.backgroundStyle)
        UIView.setAnimationsEnabled(false)
    }

    override func tearDown() {
        UIView.setAnimationsEnabled(true)
        resetQuestionFactoryState()
        UserDefaults.standard.removeObject(forKey: AppLocalizationStore.Keys.language)
        super.tearDown()
    }

    func questionAnswerButtons(in viewController: QuizQuestionViewController) -> [UIButton] {
        (1...4).compactMap { index in
            viewController.view.descendant(withAccessibilityIdentifier: "questionAnswerButton\(index)") as? UIButton
        }
    }

    var philosopherQuoteAnswers: [String] {
        [
            "«Поступай так, чтобы максима твоей воли могла бы быть всеобщим законом»",
            "«Бытие определяет сознание»",
            "«Человек — это то, что должно быть преодолено»",
            "«Жизнь — это страдание»"
        ]
    }

    var japanUnificationQuestionFixture: (question: String, answers: [String]) {
        (
            question: "Какое событие положило конец периоду феодальной раздробленности и способствовало объединению Японии в конце XVI века?",
            answers: [
                "Деятельность Оды Нобунаги, Тоётоми Хидэёси и Токугавы Иэясу",
                "Приход к власти Токугавы Иэясу",
                "Восстание крестьян",
                "Битва при Сэкигахаре"
            ]
        )
    }

    func assertAnswerLabelsFit(
        in viewController: QuizQuestionViewController,
        expectedTitles: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let buttons = questionAnswerButtons(in: viewController)
        XCTAssertEqual(buttons.count, expectedTitles.count, file: file, line: line)

        for (button, expectedTitle) in zip(buttons, expectedTitles) {
            let titleLabel = try XCTUnwrap(button.titleLabel, file: file, line: line)
            let requiredBounds = (expectedTitle as NSString).boundingRect(
                with: CGSize(width: titleLabel.bounds.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: titleLabel.font!],
                context: nil
            )
            let titleFrame = titleLabel.convert(titleLabel.bounds, to: button)

            XCTAssertEqual(button.title(for: .normal), expectedTitle, file: file, line: line)
            XCTAssertEqual(titleLabel.numberOfLines, 0, file: file, line: line)
            XCTAssertEqual(titleLabel.lineBreakMode, .byWordWrapping, file: file, line: line)
            XCTAssertGreaterThan(titleLabel.bounds.width, 0, file: file, line: line)
            XCTAssertLessThanOrEqual(
                ceil(requiredBounds.height),
                titleLabel.bounds.height + 0.5,
                "Answer \(expectedTitle) at \(titleLabel.font.pointSize)pt requires \(ceil(requiredBounds.height))pt but has \(titleLabel.bounds.height)pt in button \(button.bounds)",
                file: file,
                line: line
            )
            XCTAssertTrue(
                button.bounds.insetBy(dx: -0.5, dy: -0.5).contains(titleFrame),
                "Answer title frame \(titleFrame) escapes button bounds \(button.bounds)",
                file: file,
                line: line
            )
        }
    }

    func textHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        ceil(
            (text as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            ).height
        )
    }

    func makeExitConfirmationHarness() -> (
        viewController: QuizQuestionViewController,
        presenter: ExitConfirmationPresenterSpy,
        router: CrossScreenRouterSpy,
        analytics: ExitConfirmationAnalyticsSpy,
        window: UIWindow
    ) {
        QuizFactory.shared.chosenTheme = makeQuestionTheme()
        QuizFactory.shared.questionsCount = 1

        let viewController = QuizQuestionViewController()
        let router = CrossScreenRouterSpy()
        let analytics = ExitConfirmationAnalyticsSpy()
        viewController.router = router
        viewController.analytics = analytics
        viewController.loadViewIfNeeded()
        viewController.presenter?.stopTimer()

        let presenter = ExitConfirmationPresenterSpy()
        presenter.view = viewController
        viewController.presenter = presenter

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        viewController.view.frame = window.bounds
        viewController.view.layoutIfNeeded()
        return (viewController, presenter, router, analytics, window)
    }

    func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for cross-screen state")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func assertColor(_ actual: UIColor?, equals expected: UIColor, file: StaticString = #filePath, line: UInt = #line) {
        guard let actual else {
            XCTFail("Expected color, got nil", file: file, line: line)
            return
        }

        let traitCollection = UITraitCollection(userInterfaceStyle: .light)
        let actualColor = actual.resolvedColor(with: traitCollection)
        let expectedColor = expected.resolvedColor(with: traitCollection)
        var actualRed: CGFloat = 0
        var actualGreen: CGFloat = 0
        var actualBlue: CGFloat = 0
        var actualAlpha: CGFloat = 0
        var expectedRed: CGFloat = 0
        var expectedGreen: CGFloat = 0
        var expectedBlue: CGFloat = 0
        var expectedAlpha: CGFloat = 0

        XCTAssertTrue(actualColor.getRed(&actualRed, green: &actualGreen, blue: &actualBlue, alpha: &actualAlpha), file: file, line: line)
        XCTAssertTrue(expectedColor.getRed(&expectedRed, green: &expectedGreen, blue: &expectedBlue, alpha: &expectedAlpha), file: file, line: line)
        XCTAssertEqual(actualRed, expectedRed, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualGreen, expectedGreen, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualBlue, expectedBlue, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualAlpha, expectedAlpha, accuracy: 0.001, file: file, line: line)
    }

    func resetQuestionFactoryState() {
        QuizFactory.shared.themes = []
        QuizFactory.shared.chosenTheme = nil
        QuizFactory.shared.questionsCount = 0
        UserDefaults.standard.removeObject(forKey: AppAppearanceStore.Keys.designStyle)
        UserDefaults.standard.removeObject(forKey: AppAppearanceStore.Keys.cleanColorScheme)
        UserDefaults.standard.removeObject(forKey: AppAppearanceStore.Keys.backgroundStyle)
    }

    func currentAppearance() -> AppAppearance {
        AppAppearanceStore.shared.appearance(compatibleWith: UITraitCollection(userInterfaceStyle: .light))
    }

    func makeQuestionTheme() -> ThemeModel {
        let question = QuizQuestion(
            question: "Какой ответ должен подсветиться как верный?",
            answers: ["Правильный ответ", "Ошибочный ответ 1", "Ошибочный ответ 2", "Ошибочный ответ 3"],
            correctAnswer: "Правильный ответ",
            explanation: "Правильный ответ отмечен в данных вопроса как correctAnswer."
        )

        return ThemeModel(
            quizTheme: QuizTheme(
                id: "visual_test",
                theme: "Визуальный тест",
                themeDescription: "Тема для проверки вопросного экрана",
                questions: [question]
            )
        )
    }

    func makeQuestionTheme(
        id: String,
        themeName: String,
        questionText: String,
        answers: [String]
    ) -> ThemeModel {
        ThemeModel(
            quizTheme: QuizTheme(
                id: id,
                theme: themeName,
                themeDescription: "Тема для проверки адаптивной типографики",
                questions: [
                    QuizQuestion(
                        question: questionText,
                        answers: answers,
                        correctAnswer: answers[0]
                    )
                ]
            )
        )
    }

}

final class StatisticsCellTargetSpy: NSObject {
    @objc func tapped() {}
}

final class CrossScreenRouterSpy: QuizRouting {
    private(set) var results: [QuizResultState] = []
    private(set) var showQuestionCallCount = 0
    private(set) var closeQuestionCallCount = 0
    private(set) var replayQuizCallCount = 0
    private(set) var returnToThemesCallCount = 0

    func showQuestion() { showQuestionCallCount += 1 }
    func showResult(_ result: QuizResultState) { results.append(result) }
    func showSettings() {}
    func showSubscription() {}
    func closeQuestion() { closeQuestionCallCount += 1 }
    func replayQuiz() { replayQuizCallCount += 1 }
    func returnToThemes() { returnToThemesCallCount += 1 }
}

final class ExitConfirmationPresenterSpy: QuizQuestionPresenterProtocol {
    var view: QuizQuestionViewControllerProtocol?
    var correctAnswers = 0
    var questionsTotalCount: Int? = 1
    var currentProgress: Float = 0.6
    private(set) var pauseTimerCallCount = 0
    private(set) var resumeTimerCallCount = 0
    private(set) var resetGameProgressCallCount = 0

    func viewDidLoad() {}
    private(set) var startTimerCallCount = 0
    func startTimer() { startTimerCallCount += 1 }
    func pauseTimer() { pauseTimerCallCount += 1 }
    func resumeTimer() { resumeTimerCallCount += 1 }
    func stopTimer() {}
    func loadQuestion() {}
    func checkQuestionNumberAndProceed() {}
    func answerFeedback(for optionID: String) -> QuizAnswerFeedback { .normal }
    func checkAnswer(optionID: String) {}
    func updateQuizState(isCorrect: Bool) {}
    func resetGameProgress() { resetGameProgressCallCount += 1 }
}

final class ExitConfirmationAnalyticsSpy: AnalyticsTracking {
    private(set) var events: [AnalyticsEvent] = []

    var exitEventNames: [String] {
        events.map(\.name).filter {
            $0 == "quiz_exit_requested" || $0 == "quiz_exit_cancelled" || $0 == "quiz_abandoned"
        }
    }

    func track(_ event: AnalyticsEvent) {
        events.append(event)
    }

    func reportOperationalError(_ error: Error, context: AnalyticsErrorContext) {}
}
