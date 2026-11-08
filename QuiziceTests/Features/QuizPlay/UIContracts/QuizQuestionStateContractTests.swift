import XCTest
@testable import Quizice

@MainActor
final class QuizQuestionStateContractTests: CrossScreenVisualTestCase {
    func testQuestionScreenFadesHeaderAndActionButtonsWhenShowingResult() throws {
        QuizFactory.shared.chosenTheme = makeQuestionTheme()
        QuizFactory.shared.questionsCount = 1

        let viewController = QuizQuestionViewController()
        let router = CrossScreenRouterSpy()
        viewController.router = router
        viewController.loadViewIfNeeded()
        defer { viewController.presenter?.stopTimer() }

        let chromeViews = try [
            XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "questionThemeLabel")),
            XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "questionNumberLabel")),
            XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "questionNextButton")),
            XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "questionCloseButton"))
        ]

        XCTAssertTrue(chromeViews.allSatisfy { $0.alpha == 1 })

        viewController.showResults(QuizResultState(correctAnswers: 1, totalQuestions: 1))

        XCTAssertTrue(chromeViews.allSatisfy { $0.alpha == 0 })
        XCTAssertEqual(router.results, [QuizResultState(correctAnswers: 1, totalQuestions: 1)])
    }

    func testPreparingReplayRestoresQuestionScreenWithoutReturningToHome() throws {
        QuizFactory.shared.chosenTheme = makeQuestionTheme()
        QuizFactory.shared.questionsCount = 1

        let viewController = QuizQuestionViewController()
        viewController.loadViewIfNeeded()
#if DEBUG
        XCTAssertEqual(viewController.debugQuestionSourceLabel.text, "LOCAL")
#endif
        viewController.showResults(QuizResultState(correctAnswers: 1, totalQuestions: 1))

        let replayTheme = QuizTheme(
            id: RandomQuizSelection.themeID,
            theme: L10n.Home.randomSelection,
            themeDescription: L10n.Home.feelingLucky,
            questions: [
                QuizQuestion(
                    question: "Новый вопрос после повтора?",
                    answers: ["A", "B", "C", "D"],
                    correctAnswer: "A"
                )
            ],
            questionOrigin: .backend
        )
        QuizFactory.shared.chosenTheme = ThemeModel(quizTheme: replayTheme)
        let replayPresenter = QuizQuestionPresenter()

        viewController.prepareForReplay(replayPresenter)
        defer { replayPresenter.stopTimer() }

        let themeLabel = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "questionThemeLabel") as? UILabel
        )
        let questionLabel = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "questionTextLabel") as? UILabel
        )
        XCTAssertEqual(themeLabel.text, L10n.Home.randomSelection)
        XCTAssertEqual(questionLabel.text, "Новый вопрос после повтора?")
        XCTAssertTrue(viewController.questionChromeViews.allSatisfy { $0.alpha == 1 })
#if DEBUG
        XCTAssertEqual(viewController.debugQuestionSourceLabel.text, "BACKEND")
#endif
    }

    func testReplayRestoresTimerAfterAccessibilityRoundEnds() {
        QuizFactory.shared.chosenTheme = makeQuestionTheme()
        QuizFactory.shared.questionsCount = 1
        let controller = QuizQuestionViewController()
        controller.configurePresenter(QuizQuestionPresenter(accessibilityClient: .stub(active: true)))
        controller.loadViewIfNeeded()
        XCTAssertTrue(controller.timerContainerView.isHidden)
        XCTAssertTrue(controller.timerContainerView.accessibilityElementsHidden)

        let replay = QuizQuestionPresenter(accessibilityClient: .stub(active: false))
        controller.prepareForReplay(replay)
        defer { replay.stopTimer() }
        XCTAssertFalse(controller.timerContainerView.isHidden)
        XCTAssertFalse(controller.timerContainerView.accessibilityElementsHidden)
        XCTAssertEqual(controller.timerBar.progress, 1)
    }

    func testAppearanceRefreshPreservesAnswerFeedbackAndDisabledButtons() throws {
        QuizFactory.shared.chosenTheme = makeQuestionTheme()
        QuizFactory.shared.questionsCount = 1
        let controller = QuizQuestionViewController()
        controller.loadViewIfNeeded()
        defer { controller.presenter?.stopTimer() }
        let buttons = questionAnswerButtons(in: controller)
        let correct = try XCTUnwrap(buttons.first { $0.title(for: .normal) == "Правильный ответ" })
        correct.sendActions(for: .touchUpInside)
        controller.applyAppearance()
        XCTAssertTrue(buttons.allSatisfy { !$0.isEnabled })
        assertColor(UIColor(cgColor: try XCTUnwrap(correct.layer.borderColor)),
                    equals: currentAppearance().correctAnswerColor)
        for button in buttons where button !== correct {
            assertColor(UIColor(cgColor: try XCTUnwrap(button.layer.borderColor)),
                        equals: currentAppearance().wrongAnswerColor)
        }
        assertColor(controller.timerBar.progressTintColor,
                    equals: controller.timerFeedbackColor(isCorrect: true, appearance: currentAppearance()))
        XCTAssertTrue(controller.nextButton.isEnabled)
    }

    func testApplicationInterruptionsPauseAndResumeTheQuestionPresenter() {
        let (controller, presenter, _, _, window) = makeExitConfirmationHarness()
        defer { window.isHidden = true }
        let originalPauses = presenter.pauseTimerCallCount
        let originalResumes = presenter.resumeTimerCallCount
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertEqual(presenter.pauseTimerCallCount, originalPauses + 1)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(presenter.resumeTimerCallCount, originalResumes + 1)
        XCTAssertTrue(controller.isViewLoaded)
    }

    func testReplayPreparedDuringInterruptionStaysPausedUntilActivation() {
        let (controller, _, _, _, window) = makeExitConfirmationHarness()
        defer { window.isHidden = true }
        controller.pauseForApplicationInterruption()
        let replay = ExitConfirmationPresenterSpy()
        controller.prepareForReplay(replay)
        XCTAssertEqual(replay.pauseTimerCallCount, 1)
        XCTAssertEqual(replay.resumeTimerCallCount, 0)
        controller.resumeAfterApplicationInterruption()
        XCTAssertEqual(replay.resumeTimerCallCount, 1)
    }

    func testQuestionScreenUpdatesExistingCardWhenNextQuestionViewModelIsLoaded() throws {
        QuizFactory.shared.chosenTheme = makeQuestionTheme()
        QuizFactory.shared.questionsCount = 1

        let viewController = QuizQuestionViewController()
        viewController.loadViewIfNeeded()
        defer { viewController.presenter?.stopTimer() }

        let nextViewModel = QuizQuestionViewModel(
            themeName: "Визуальный тест",
            questionText: "Какой город называют Северной столицей?",
            questionNumberText: "Вопрос №2",
            answers: [
                QuizAnswerOption(id: "2-0", title: "Санкт-Петербург"),
                QuizAnswerOption(id: "2-1", title: "Москва"),
                QuizAnswerOption(id: "2-2", title: "Казань"),
                QuizAnswerOption(id: "2-3", title: "Новосибирск")
            ]
        )

        viewController.loadQuestionToView(nextViewModel)

        let questionLabel = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "questionTextLabel") as? UILabel)
        let questionNumberLabel = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "questionNumberLabel") as? UILabel)
        let nextButton = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "questionNextButton") as? UIButton)
        let answerButtons = questionAnswerButtons(in: viewController)

        XCTAssertNotNil(viewController.view.descendant(withAccessibilityIdentifier: "questionCardView"))
        XCTAssertNotNil(viewController.view.descendant(withAccessibilityIdentifier: "questionAnswersStackView"))
        XCTAssertEqual(questionLabel.text, nextViewModel.questionText)
        XCTAssertEqual(questionNumberLabel.text, nextViewModel.questionNumberText)
        XCTAssertEqual(answerButtons.map { $0.title(for: .normal) }, nextViewModel.answers.map(\.title))
        XCTAssertFalse(nextButton.isEnabled)
    }

    func testExtremeAnswerFitsWithoutGrowingCardOrMovingNextButton() throws {
        QuizFactory.shared.chosenTheme = makeQuestionTheme()
        QuizFactory.shared.questionsCount = 1

        let viewController = QuizQuestionViewController()
        viewController.loadViewIfNeeded()
        defer { viewController.presenter?.stopTimer() }
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)

        viewController.loadQuestionToView(
            QuizQuestionViewModel(
                themeName: "Музыка",
                questionText: "Кто исполнитель?",
                questionNumberText: "Вопрос №1",
                answers: [
                    QuizAnswerOption(id: "short-0", title: "A"),
                    QuizAnswerOption(id: "short-1", title: "B"),
                    QuizAnswerOption(id: "short-2", title: "C"),
                    QuizAnswerOption(id: "short-3", title: "D")
                ]
            )
        )
        viewController.view.layoutIfNeeded()

        let nextButton = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "questionNextButton") as? UIButton)
        let container = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "questionCardContainerView"))
        let cardView = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "questionCardView"))
        let pinnedButtonY = nextButton.frame.minY
        let shortCardHeight = cardView.frame.height
        let extremeAnswer = String(
            repeating: "Это экстремально длинный вариант ответа, который должен полностью оставаться внутри кнопки. ",
            count: 8
        )

        viewController.loadQuestionToView(
            QuizQuestionViewModel(
                themeName: "Музыка",
                questionText: "Какой вариант верный?",
                questionNumberText: "Вопрос №2",
                answers: [
                    QuizAnswerOption(id: "long-0", title: extremeAnswer),
                    QuizAnswerOption(id: "long-1", title: "B"),
                    QuizAnswerOption(id: "long-2", title: "C"),
                    QuizAnswerOption(id: "long-3", title: "D")
                ]
            )
        )
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()
        viewController.view.layoutIfNeeded()

        let longAnswerButton = try XCTUnwrap(questionAnswerButtons(in: viewController).first)
        let longAnswerLabel = try XCTUnwrap(longAnswerButton.titleLabel)
        let baseFont = currentAppearance().typography.font(size: 18, weight: .semibold)

        XCTAssertEqual(cardView.frame.height, shortCardHeight, accuracy: 0.5)
        XCTAssertGreaterThan(longAnswerButton.bounds.height, 52)
        XCTAssertLessThan(longAnswerLabel.font.pointSize, baseFont.pointSize)
        try assertAnswerLabelsFit(in: viewController, expectedTitles: [extremeAnswer, "B", "C", "D"])
        XCTAssertEqual(nextButton.frame.minY, pinnedButtonY, accuracy: 0.5)
        XCTAssertFalse(container is UIScrollView)
        XCTAssertFalse(nextButton.isDescendant(of: container))
        XCTAssertLessThanOrEqual(container.frame.maxY, nextButton.frame.minY)
        XCTAssertTrue(container.bounds.contains(cardView.frame))
    }

    func testQuestionAdvanceKeepsCardFrameStableAfterLongAnswer() throws {
        QuizFactory.shared.chosenTheme = makeQuestionTheme()
        QuizFactory.shared.questionsCount = 1

        let viewController = QuizQuestionViewController()
        viewController.loadViewIfNeeded()
        defer { viewController.presenter?.stopTimer() }
        viewController.view.frame = CGRect(x: 0, y: 0, width: 375, height: 667)
        let extremeAnswer = String(
            repeating: "Это экстремально длинный вариант ответа, который делает карточку прокручиваемой. ",
            count: 8
        )
        viewController.loadQuestionToView(
            QuizQuestionViewModel(
                themeName: "Цитаты философов",
                questionText: "Какой вариант верный?",
                questionNumberText: "Вопрос №2",
                answers: [
                    QuizAnswerOption(id: "scroll-answer-0", title: extremeAnswer),
                    QuizAnswerOption(id: "scroll-answer-1", title: "B"),
                    QuizAnswerOption(id: "scroll-answer-2", title: "C"),
                    QuizAnswerOption(id: "scroll-answer-3", title: "D")
                ]
            )
        )
        viewController.view.layoutIfNeeded()

        let container = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "questionCardContainerView")
        )
        let cardFrame = viewController.questionCardView.frame
        XCTAssertFalse(container is UIScrollView)
        XCTAssertTrue(container.bounds.contains(cardFrame))

        viewController.loadQuestionToView(
            QuizQuestionViewModel(
                themeName: "Следующая тема",
                questionText: "Следующий короткий вопрос?",
                questionNumberText: "Вопрос №3",
                answers: [
                    QuizAnswerOption(id: "next-0", title: "A"),
                    QuizAnswerOption(id: "next-1", title: "B"),
                    QuizAnswerOption(id: "next-2", title: "C"),
                    QuizAnswerOption(id: "next-3", title: "D")
                ]
            )
        )
        viewController.view.layoutIfNeeded()

        XCTAssertEqual(viewController.questionCardView.frame, cardFrame)
    }

    func testQuestionScreenPreservesPresenterDrivenAnswerFeedbackState() throws {
        QuizFactory.shared.chosenTheme = makeQuestionTheme()
        QuizFactory.shared.questionsCount = 1

        let viewController = QuizQuestionViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()

        let timerContainer = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "questionTimerContainerView"
            )
        )
        let initialTimerFrame = timerContainer.frame

        let answerButtons = questionAnswerButtons(in: viewController)
        let correctButton = try XCTUnwrap(answerButtons.first { $0.title(for: .normal) == "Правильный ответ" })
        let wrongButtons = answerButtons.filter { $0 !== correctButton }

        correctButton.sendActions(for: .touchUpInside)

        XCTAssertTrue(answerButtons.allSatisfy { !$0.isEnabled })
        XCTAssertEqual(correctButton.backgroundColor, currentAppearance().answerDefaultColor)
        XCTAssertEqual(correctButton.layer.borderWidth, 4)
        assertColor(UIColor(cgColor: correctButton.layer.borderColor ?? UIColor.clear.cgColor), equals: currentAppearance().correctAnswerColor)
        XCTAssertTrue(wrongButtons.allSatisfy { $0.backgroundColor == currentAppearance().answerDefaultColor })
        XCTAssertTrue(wrongButtons.allSatisfy { $0.layer.borderWidth == 4 })
        for wrongButton in wrongButtons {
            assertColor(UIColor(cgColor: wrongButton.layer.borderColor ?? UIColor.clear.cgColor), equals: currentAppearance().wrongAnswerColor)
        }

        let timerBar = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "questionTimerProgressView") as? UIProgressView)
        assertColor(timerBar.progressTintColor, equals: currentAppearance().correctAnswerColor)
        assertColor(timerBar.tintColor, equals: currentAppearance().correctAnswerColor)

        let nextButton = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "questionNextButton") as? UIButton)
        XCTAssertTrue(nextButton.isEnabled)

        let infoButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "questionInfoButton") as? UIButton
        )
        XCTAssertTrue(infoButton.isHidden)
        XCTAssertTrue(viewController.isQuestionExplanationVisible)
        viewController.view.layoutIfNeeded()

        XCTAssertEqual(timerContainer.frame, initialTimerFrame)
        XCTAssertEqual(
            timerContainer.frame.minX,
            viewController.questionCardContentView.bounds.maxX - timerContainer.frame.maxX,
            accuracy: 0.001
        )
        XCTAssertLessThanOrEqual(infoButton.frame.maxX, timerContainer.frame.minX)
        XCTAssertEqual(
            infoButton.layer.cornerRadius,
            infoButton.bounds.height / 2,
            accuracy: 0.001
        )

        let expectedInfoImage = UIImage(
            systemName: "info",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        )
        XCTAssertEqual(infoButton.image(for: .normal)?.pngData(), expectedInfoImage?.pngData())
    }

    func testQuestionExplanationReplacesQuestionTextWithoutMovingAnswersAfterAnswer() throws {
        QuizFactory.shared.chosenTheme = makeQuestionTheme()
        QuizFactory.shared.questionsCount = 1

        let viewController = QuizQuestionViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        defer { viewController.presenter?.stopTimer() }

        let infoButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "questionInfoButton") as? UIButton
        )
        XCTAssertTrue(infoButton.isHidden)

        let questionLabel = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "questionTextLabel"
            ) as? UILabel
        )
        let explanationText = "Первая строка объяснения.\nВторая строка объяснения.\nТретья строка объяснения."
        viewController.questionExplanationLabel.text = explanationText

        let correctButton = try XCTUnwrap(
            questionAnswerButtons(in: viewController).first {
                $0.title(for: .normal) == "Правильный ответ"
            }
        )
        viewController.view.layoutIfNeeded()
        let questionFrame = questionLabel.frame
        let answerFrames = questionAnswerButtons(in: viewController).map(\.frame)

        correctButton.sendActions(for: .touchUpInside)
        viewController.view.layoutIfNeeded()

        let explanationLabel = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "questionExplanationLabel"
            ) as? UILabel
        )
        let explanationScrollView = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "questionExplanationScrollView"
            ) as? UIScrollView
        )
        XCTAssertEqual(
            explanationLabel.text,
            explanationText
        )
        XCTAssertEqual(explanationLabel.textAlignment, .center)
        XCTAssertTrue(viewController.isQuestionExplanationVisible)
        XCTAssertTrue(questionLabel.isHidden)
        XCTAssertFalse(explanationScrollView.isHidden)
        XCTAssertLessThanOrEqual(explanationScrollView.frame.minY, questionFrame.minY)
        XCTAssertGreaterThanOrEqual(explanationScrollView.frame.maxY, questionFrame.maxY)
        XCTAssertGreaterThan(explanationScrollView.bounds.height, questionFrame.height)
        XCTAssertGreaterThanOrEqual(explanationLabel.frame.minY, 0)
        XCTAssertLessThanOrEqual(
            explanationLabel.frame.maxY,
            explanationScrollView.contentSize.height
        )
        XCTAssertLessThanOrEqual(
            explanationLabel.bounds.height,
            explanationScrollView.bounds.height
        )
        XCTAssertEqual(questionAnswerButtons(in: viewController).map(\.frame), answerFrames)
        XCTAssertTrue(infoButton.isHidden)

        let backButton = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "questionExplanationBackButton"
            ) as? UIButton
        )
        XCTAssertFalse(backButton.isHidden)
        XCTAssertEqual(
            backButton.layer.cornerRadius,
            backButton.bounds.height / 2,
            accuracy: 0.001
        )

        backButton.sendActions(for: .touchUpInside)

        XCTAssertFalse(viewController.isQuestionExplanationVisible)
        XCTAssertFalse(questionLabel.isHidden)
        XCTAssertTrue(explanationScrollView.isHidden)
        XCTAssertFalse(infoButton.isHidden)
        XCTAssertTrue(backButton.isHidden)

        infoButton.sendActions(for: .touchUpInside)
        XCTAssertTrue(viewController.isQuestionExplanationVisible)
        XCTAssertFalse(explanationScrollView.isHidden)
        XCTAssertTrue(infoButton.isHidden)
    }

    func testAutomaticExplanationCrossFadesWithoutFlashingInfoButton() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Cross-fade requires motion enabled")
        let (controller, _, _, _, window) = makeExitConfirmationHarness()
        defer {
            UIView.setAnimationsEnabled(false)
            window.isHidden = true
        }
        CATransaction.flush()
        UIView.setAnimationsEnabled(true)

        controller.answerButtons[0].sendActions(for: .touchUpInside)
        CATransaction.flush()

        XCTAssertTrue(controller.isQuestionExplanationVisible)
        XCTAssertFalse(controller.questionLabel.isHidden)
        XCTAssertFalse(controller.questionExplanationScrollView.isHidden)
        XCTAssertTrue(controller.questionInfoButton.isHidden)
        XCTAssertEqual(controller.questionLabel.alpha, 0)
        XCTAssertEqual(controller.questionExplanationScrollView.alpha, 1)

        try await waitUntil { controller.questionLabel.isHidden }
        XCTAssertFalse(controller.questionExplanationScrollView.isHidden)
        XCTAssertEqual(controller.questionExplanationScrollView.alpha, 1)
        XCTAssertTrue(controller.questionInfoButton.isHidden)
    }

    func testWrongAnswerAutomaticallyShowsExplanation() throws {
        QuizFactory.shared.chosenTheme = makeQuestionTheme()
        QuizFactory.shared.questionsCount = 1
        let controller = QuizQuestionViewController()
        controller.loadViewIfNeeded()
        defer { controller.presenter?.stopTimer() }

        let wrongButton = try XCTUnwrap(
            controller.answerButtons.first { $0.title(for: .normal) == "Ошибочный ответ 1" }
        )
        wrongButton.sendActions(for: .touchUpInside)

        XCTAssertTrue(controller.isQuestionExplanationVisible)
        XCTAssertFalse(controller.questionExplanationScrollView.isHidden)
        XCTAssertTrue(controller.questionLabel.isHidden)
        XCTAssertTrue(controller.questionInfoButton.isHidden)
        XCTAssertTrue(controller.nextButton.isEnabled)
        XCTAssertTrue(controller.answerButtons.allSatisfy { !$0.isEnabled })
    }

    func testAnswerWithoutExplanationKeepsQuestionVisible() throws {
        for explanation: String? in [nil, "", " \n\t "] {
            QuizFactory.shared.chosenTheme = makeQuestionTheme()
            QuizFactory.shared.questionsCount = 1
            let controller = QuizQuestionViewController()
            controller.loadViewIfNeeded()
            defer { controller.presenter?.stopTimer() }
            controller.questionExplanationLabel.text = explanation

            let correctButton = try XCTUnwrap(
                controller.answerButtons.first { $0.title(for: .normal) == "Правильный ответ" }
            )
            correctButton.sendActions(for: .touchUpInside)

            XCTAssertFalse(controller.isQuestionExplanationVisible)
            XCTAssertFalse(controller.questionLabel.isHidden)
            XCTAssertTrue(controller.questionExplanationScrollView.isHidden)
            XCTAssertTrue(controller.questionInfoButton.isHidden)
            XCTAssertTrue(controller.questionExplanationBackButton.isHidden)
            XCTAssertTrue(controller.nextButton.isEnabled)
        }
    }

    func testLoadingNextQuestionHidesExplanationAndResetsScrollPosition() throws {
        QuizFactory.shared.chosenTheme = makeQuestionTheme()
        QuizFactory.shared.questionsCount = 1
        let controller = QuizQuestionViewController()
        controller.loadViewIfNeeded()
        defer { controller.presenter?.stopTimer() }
        let correctButton = try XCTUnwrap(
            controller.answerButtons.first { $0.title(for: .normal) == "Правильный ответ" }
        )
        correctButton.sendActions(for: .touchUpInside)
        XCTAssertTrue(controller.isQuestionExplanationVisible)
        controller.questionExplanationScrollView.contentOffset.y = 80

        controller.loadQuestionToView(QuizQuestionViewModel(
            themeName: "Визуальный тест",
            questionText: "Следующий вопрос",
            questionNumberText: "Вопрос №2",
            answers: (0..<4).map { QuizAnswerOption(id: "next-\($0)", title: "Ответ \($0)") },
            explanation: "Объяснение следующего вопроса"
        ))

        XCTAssertFalse(controller.isQuestionExplanationVisible)
        XCTAssertFalse(controller.isQuestionInfoAvailable)
        XCTAssertFalse(controller.questionLabel.isHidden)
        XCTAssertEqual(controller.questionLabel.text, "Следующий вопрос")
        XCTAssertTrue(controller.questionExplanationScrollView.isHidden)
        XCTAssertEqual(controller.questionExplanationScrollView.contentOffset, .zero)
        XCTAssertTrue(controller.questionInfoButton.isHidden)
        XCTAssertTrue(controller.questionExplanationBackButton.isHidden)
        XCTAssertFalse(controller.nextButton.isEnabled)
        XCTAssertTrue(controller.answerButtons.allSatisfy(\.isEnabled))
    }

    func testQuestionScreenTimeExpiredStateDisablesAnswersAndKeepsNextActionAvailable() throws {
        QuizFactory.shared.chosenTheme = makeQuestionTheme()
        QuizFactory.shared.questionsCount = 1

        let viewController = QuizQuestionViewController()
        viewController.loadViewIfNeeded()

        viewController.showTimeExpired()

        XCTAssertTrue(viewController.isQuestionExplanationVisible)
        XCTAssertFalse(viewController.questionExplanationScrollView.isHidden)
        XCTAssertTrue(viewController.questionLabel.isHidden)
        XCTAssertTrue(viewController.questionInfoButton.isHidden)

        let answerButtons = questionAnswerButtons(in: viewController)
        XCTAssertTrue(answerButtons.allSatisfy { !$0.isEnabled })

        let correctButton = try XCTUnwrap(answerButtons.first { $0.title(for: .normal) == "Правильный ответ" })
        XCTAssertEqual(correctButton.backgroundColor, currentAppearance().answerDefaultColor)
        XCTAssertEqual(correctButton.layer.borderWidth, 4)
        assertColor(UIColor(cgColor: correctButton.layer.borderColor ?? UIColor.clear.cgColor), equals: currentAppearance().correctAnswerColor)
        let wrongButtons = answerButtons.filter { $0 !== correctButton }
        XCTAssertTrue(wrongButtons.allSatisfy { $0.backgroundColor == currentAppearance().answerDefaultColor })
        XCTAssertTrue(wrongButtons.allSatisfy { $0.layer.borderWidth == 4 })
        for wrongButton in wrongButtons {
            assertColor(UIColor(cgColor: wrongButton.layer.borderColor ?? UIColor.clear.cgColor), equals: currentAppearance().wrongAnswerColor)
        }

        let timerBar = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "questionTimerProgressView") as? UIProgressView)
        assertColor(timerBar.progressTintColor, equals: currentAppearance().wrongAnswerColor)
        assertColor(timerBar.tintColor, equals: currentAppearance().wrongAnswerColor)

        let nextButton = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "questionNextButton") as? UIButton)
        XCTAssertTrue(nextButton.isEnabled)
    }

    func testQuestionExitCancellationKeepsQuizAndLeavesTimerRunning() async throws {
        let (viewController, presenter, router, analytics, window) = makeExitConfirmationHarness()
        defer { window.isHidden = true }

        let closeButton = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "questionCloseButton") as? UIButton)
        closeButton.sendActions(for: .touchUpInside)
        closeButton.sendActions(for: .touchUpInside)
        let overlay = viewController.makeExitConfirmationAlertOverlay()

        let alert = try XCTUnwrap(viewController.presentedViewController)
        XCTAssertFalse(alert is UIAlertController)
        XCTAssertEqual(alert.modalPresentationStyle, .overFullScreen)
        XCTAssertTrue(alert.isModalInPresentation)
        XCTAssertTrue(alert.view.accessibilityViewIsModal)
        XCTAssertEqual(overlay.title, L10n.Question.exitAlertTitle)
        XCTAssertEqual(overlay.message, L10n.Question.exitAlertMessage)
        XCTAssertEqual(overlay.primaryAction.title, L10n.Common.exit)
        XCTAssertEqual(overlay.primaryAction.emphasis, .destructive)
        XCTAssertEqual(overlay.secondaryAction?.title, L10n.Common.no)
        XCTAssertEqual(overlay.secondaryAction?.emphasis, .secondary)
        XCTAssertEqual(presenter.pauseTimerCallCount, 0)

        try XCTUnwrap(overlay.secondaryAction).action()

        try await waitUntil { viewController.presentedViewController == nil }
        XCTAssertNil(viewController.presentedViewController)
        XCTAssertEqual(presenter.resumeTimerCallCount, 0)
        XCTAssertEqual(presenter.resetGameProgressCallCount, 0)
        XCTAssertEqual(router.closeQuestionCallCount, 0)
        XCTAssertEqual(analytics.exitEventNames, ["quiz_exit_requested", "quiz_exit_cancelled"])
    }

    func testQuestionExitConfirmationResetsProgressAndReturnsHome() async throws {
        let (viewController, presenter, router, analytics, window) = makeExitConfirmationHarness()
        defer { window.isHidden = true }

        let closeButton = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "questionCloseButton") as? UIButton)
        closeButton.sendActions(for: .touchUpInside)
        let overlay = viewController.makeExitConfirmationAlertOverlay()
        XCTAssertNotNil(viewController.presentedViewController)

        overlay.primaryAction.action()
        overlay.primaryAction.action()

        try await waitUntil { viewController.presentedViewController == nil }
        XCTAssertNil(viewController.presentedViewController)
        XCTAssertEqual(presenter.pauseTimerCallCount, 0)
        XCTAssertEqual(presenter.resumeTimerCallCount, 0)
        XCTAssertEqual(presenter.resetGameProgressCallCount, 1)
        XCTAssertEqual(router.closeQuestionCallCount, 1)
        XCTAssertEqual(analytics.exitEventNames, ["quiz_exit_requested", "quiz_abandoned"])
    }

    func testQuestionExitAccessibilityEscapeCancelsInsteadOfAbandoning() async throws {
        let (viewController, presenter, router, analytics, window) = makeExitConfirmationHarness()
        defer { window.isHidden = true }

        let closeButton = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "questionCloseButton") as? UIButton)
        closeButton.sendActions(for: .touchUpInside)
        let overlay = viewController.makeExitConfirmationAlertOverlay()

        overlay.onEscape()

        try await waitUntil { viewController.presentedViewController == nil }
        XCTAssertNil(viewController.presentedViewController)
        XCTAssertEqual(presenter.resumeTimerCallCount, 0)
        XCTAssertEqual(presenter.resetGameProgressCallCount, 0)
        XCTAssertEqual(router.closeQuestionCallCount, 0)
        XCTAssertEqual(analytics.exitEventNames, ["quiz_exit_requested", "quiz_exit_cancelled"])
    }

    func testRadarExitAlertUsesOnlyRadarAccentForDestructiveStyling() {
        UserDefaults.standard.set(AppDesignStyle.radar.rawValue, forKey: AppAppearanceStore.Keys.designStyle)
        let viewController = QuizQuestionViewController()
        viewController.loadViewIfNeeded()
        let appearance = currentAppearance()

        let overlay = viewController.makeExitConfirmationAlertOverlay()
        let destructive = overlay.primaryAction.emphasis

        assertColor(overlay.iconColor, equals: appearance.accentColor)
        assertColor(destructive.tintColor(in: appearance), equals: appearance.accentColor)
        assertColor(destructive.textColor(in: appearance), equals: appearance.accentColor)
        assertColor(destructive.surfaceStyle(in: appearance).borderColor, equals: appearance.accentColor)
    }

    func testPreparingIncomingQuestionCardResetsTimerBeforeSlideAnimationStarts() throws {
        let presenter = ExitConfirmationPresenterSpy()
        presenter.currentProgress = 0.24
        let viewController = QuizQuestionViewController()
        viewController.configurePresenter(presenter)
        viewController.loadViewIfNeeded()
        viewController.view.layoutIfNeeded()

        let makeViewModel: (Int) -> QuizQuestionViewModel = { number in
            QuizQuestionViewModel(
                themeName: "Тест",
                questionText: "Вопрос \(number)?",
                questionNumberText: "Вопрос №\(number)",
                answers: [
                    QuizAnswerOption(id: "\(number)-a", title: "A"),
                    QuizAnswerOption(id: "\(number)-b", title: "B"),
                    QuizAnswerOption(id: "\(number)-c", title: "C"),
                    QuizAnswerOption(id: "\(number)-d", title: "D")
                ]
            )
        }
        viewController.loadQuestionToView(makeViewModel(1))
        viewController.updateProgress(0.24)

        viewController.applyQuestion(makeViewModel(2), updatesQuestionNumber: false)

        let timer = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "questionTimerProgressView"
            ) as? UIProgressView
        )
        XCTAssertEqual(timer.progress, 1, accuracy: 0.001)
    }

    func testRadarQuestionFeedbackKeepsCorrectAnswerBrightAndDimsOtherAnswers() throws {
        UserDefaults.standard.set(AppDesignStyle.radar.rawValue, forKey: AppAppearanceStore.Keys.designStyle)
        QuizFactory.shared.chosenTheme = makeQuestionTheme()
        QuizFactory.shared.questionsCount = 1

        let viewController = QuizQuestionViewController()
        viewController.loadViewIfNeeded()

        let appearance = currentAppearance()
        let answerButtons = questionAnswerButtons(in: viewController)
        let correctButton = try XCTUnwrap(answerButtons.first { $0.title(for: .normal) == "Правильный ответ" })
        let wrongButtons = answerButtons.filter { $0 !== correctButton }

        correctButton.sendActions(for: .touchUpInside)

        XCTAssertEqual(correctButton.alpha, 1)
        XCTAssertEqual(correctButton.backgroundColor, appearance.answerDefaultColor)
        XCTAssertEqual(correctButton.layer.borderWidth, 4)
        assertColor(UIColor(cgColor: correctButton.layer.borderColor ?? UIColor.clear.cgColor), equals: appearance.accentColor)
        XCTAssertTrue(wrongButtons.allSatisfy { $0.alpha < 0.5 })
        XCTAssertTrue(wrongButtons.allSatisfy { $0.backgroundColor == appearance.answerDefaultColor })

        let timerBar = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "questionTimerProgressView") as? UIProgressView)
        assertColor(timerBar.progressTintColor, equals: appearance.accentColor)
        assertColor(timerBar.tintColor, equals: appearance.accentColor)
    }
}
