import XCTest
@testable import Quizice

@MainActor
final class QuizQuestionTypographyContractTests: CrossScreenVisualTestCase {
    func testLongSourceThemeHeaderStaysAboveQuestionAtLargeTextSizes() {
        let title = "История науки, технологий и великих географических открытий"
        for style in [AppDesignStyle.classic, .radar, .clean] {
            UserDefaults.standard.set(style.rawValue, forKey: AppAppearanceStore.Keys.designStyle)
            for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
                let controller = QuizQuestionViewController()
                controller.configurePresenter(ExitConfirmationPresenterSpy())
                controller.traitOverrides.preferredContentSizeCategory = category
                controller.loadViewIfNeeded()
                controller.view.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
                controller.loadQuestionToView(QuizQuestionViewModel(
                    themeName: title, questionText: "Короткий вопрос?", questionNumberText: "Вопрос №1",
                    answers: ["A", "B", "C", "D"].enumerated().map {
                        QuizAnswerOption(id: String($0.offset), title: $0.element)
                    }
                ))
                controller.view.layoutIfNeeded()
                XCTAssertEqual(controller.themeNameLabel.text, title)
                XCTAssertGreaterThan(controller.themeNameLabel.bounds.height, 0)
                XCTAssertLessThanOrEqual(controller.themeNameLabel.frame.maxY, controller.questionNumberLabel.frame.minY)
                XCTAssertLessThanOrEqual(controller.questionNumberLabel.frame.maxY, controller.cardContainerView.frame.minY)
                XCTAssertLessThanOrEqual(controller.themeNameLabel.frame.maxX, controller.closeButton.frame.minX)
            }
        }
    }

    func testReportedBundeswehrQuestionFitsFixedCardAcrossStylesAndScreenSizes() throws {
        let question = "Чьё согласие по общему правилу требуется федеральному правительству для вооружённой операции Бундесвера за рубежом?"
        let answers = [
            "Бундестаг", "Правительства федеральных земель совместно",
            "Федеральный президент единолично", "Федеральный конституционный суд"
        ]
        for style in [AppDesignStyle.classic, .radar, .clean] {
            UserDefaults.standard.set(style.rawValue, forKey: AppAppearanceStore.Keys.designStyle)
            for size in [CGSize(width: 375, height: 812), CGSize(width: 402, height: 874), CGSize(width: 320, height: 568)] {
                let controller = QuizQuestionViewController()
                controller.configurePresenter(ExitConfirmationPresenterSpy())
                controller.loadViewIfNeeded()
                controller.view.frame = CGRect(origin: .zero, size: size)
                let window = QuestionLayoutTestWindow(frame: CGRect(origin: .zero, size: size))
                window.testSafeAreaInsets = size.height > 568
                    ? UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
                    : UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
                controller.loadQuestionToView(QuizQuestionViewModel(
                    themeName: "Политика и бизнес", questionText: question, questionNumberText: "Вопрос №3",
                    answers: answers.enumerated().map { QuizAnswerOption(id: String($0.offset), title: $0.element) }
                ))
                window.isHidden = false
                let host = UIViewController()
                host.view.frame = window.bounds
                host.addChild(controller)
                host.view.addSubview(controller.view)
                controller.didMove(toParent: host)
                window.rootViewController = host
                defer { window.isHidden = true; window.rootViewController = nil }
                window.layoutIfNeeded()
                controller.view.layoutIfNeeded()

                let label = try XCTUnwrap(controller.questionLabel)
                let card = try XCTUnwrap(controller.questionCardView)
                // UIKit may reserve a taller status bar on the host simulator
                // even for a compact canvas, which only tightens this check.
                XCTAssertGreaterThanOrEqual(controller.view.safeAreaInsets.top, window.testSafeAreaInsets.top)
                XCTAssertEqual(controller.view.safeAreaInsets.bottom, window.testSafeAreaInsets.bottom, accuracy: 0.5)
                XCTAssertFalse(controller.cardContainerView is UIScrollView)
                XCTAssertTrue(controller.cardContainerView.bounds.contains(card.frame))
                XCTAssertLessThanOrEqual(textHeight(question, font: label.font, width: label.bounds.width), label.bounds.height + 1)
                XCTAssertLessThanOrEqual(label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)).height, label.bounds.height + 1)
                XCTAssertGreaterThanOrEqual(label.convert(label.bounds, to: controller.questionCardContentView).minY, controller.timerContainerView.frame.maxY)
                XCTAssertLessThanOrEqual(label.frame.maxY, controller.answersStackView.frame.minY - 8)
                try assertAnswerLabelsFit(in: controller, expectedTitles: answers)
                XCTAssertLessThanOrEqual(card.convert(card.bounds, to: controller.view).maxY, controller.nextButton.frame.minY)
                if size.height >= 812 {
                    // Keep the real-world regression comfortably readable.
                    XCTAssertGreaterThanOrEqual(label.font.pointSize, 18)
                } else {
                    XCTAssertGreaterThanOrEqual(label.font.pointSize, 12)
                }
                let rendered = UIGraphicsImageRenderer(size: size).image { context in
                    controller.view.layer.render(in: context.cgContext)
                }
                let attachment = XCTAttachment(image: rendered)
                attachment.name = "Bundeswehr-\(style.rawValue)-\(Int(size.width))x\(Int(size.height))"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testQuestionContentDefersLayoutUntilRootReceivesNonZeroBounds() {
        let presenter = ExitConfirmationPresenterSpy()
        let viewController = QuizQuestionViewController()
        viewController.configurePresenter(presenter)
        viewController.loadViewIfNeeded()

        XCTAssertTrue(viewController.view.bounds.isEmpty)

        viewController.loadQuestionToView(
            QuizQuestionViewModel(
                themeName: "История",
                questionText: "Какой город был столицей?",
                questionNumberText: "Вопрос №1",
                answers: [
                    QuizAnswerOption(id: "0", title: "A"),
                    QuizAnswerOption(id: "1", title: "B"),
                    QuizAnswerOption(id: "2", title: "C"),
                    QuizAnswerOption(id: "3", title: "D")
                ]
            )
        )

        XCTAssertTrue(viewController.view.layer.needsLayout())
        XCTAssertTrue(viewController.questionCardView.bounds.isEmpty)

        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()

        XCTAssertFalse(viewController.view.layer.needsLayout())
        XCTAssertGreaterThan(viewController.questionCardView.bounds.width, 0)
        XCTAssertGreaterThan(viewController.questionCardView.bounds.height, 0)
    }

    func testQuestionScreenExposesPolishedLayoutAnchorsAndAnswerControls() {
        QuizFactory.shared.chosenTheme = makeQuestionTheme()
        QuizFactory.shared.questionsCount = 1

        let viewController = QuizQuestionViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()

        XCTAssertNotNil(viewController.view.descendant(withAccessibilityIdentifier: "questionRootView"))
        XCTAssertNotNil(viewController.view.descendant(withAccessibilityIdentifier: "questionThemeLabel"))
        XCTAssertNotNil(viewController.view.descendant(withAccessibilityIdentifier: "questionNumberLabel"))
        XCTAssertNotNil(viewController.view.descendant(withAccessibilityIdentifier: "questionCardView"))
        XCTAssertNotNil(viewController.view.descendant(withAccessibilityIdentifier: "questionTextLabel"))
        XCTAssertNotNil(viewController.view.descendant(withAccessibilityIdentifier: "questionTimerContainerView"))
        XCTAssertNotNil(viewController.view.descendant(withAccessibilityIdentifier: "questionTimerProgressView"))
        XCTAssertNotNil(viewController.view.descendant(withAccessibilityIdentifier: "questionAnswersStackView"))
        XCTAssertNotNil(viewController.view.descendant(withAccessibilityIdentifier: "questionNextButton"))
        XCTAssertNotNil(viewController.view.descendant(withAccessibilityIdentifier: "questionCloseButton"))
        XCTAssertNotNil(viewController.view.descendant(withAccessibilityIdentifier: "questionCardContainerView"))
        XCTAssertNil(viewController.view.descendant(withAccessibilityIdentifier: "questionScrollView"))

        let answerButtons = questionAnswerButtons(in: viewController)
        let cardView = viewController.view.descendant(withAccessibilityIdentifier: "questionCardView")
        let answersStackView = viewController.view.descendant(withAccessibilityIdentifier: "questionAnswersStackView")
        let transitionDestination = viewController as QuizCardSlideTransitionDestination
        let companionViewIDs = transitionDestination.cardSlideTransitionDestinationCompanionViews.compactMap { $0.accessibilityIdentifier }
        XCTAssertEqual(answerButtons.count, 4)
#if DEBUG
        XCTAssertEqual(
            companionViewIDs,
            ["questionThemeLabel", "questionNumberLabel", "questionBackendSource"]
        )
#else
        XCTAssertEqual(companionViewIDs, ["questionThemeLabel", "questionNumberLabel"])
#endif
        XCTAssertTrue(answerButtons.allSatisfy(\.isEnabled))
        XCTAssertTrue(answerButtons.allSatisfy { $0.layer.cornerRadius >= 16 })
        XCTAssertTrue(answerButtons.allSatisfy { $0.backgroundColor == currentAppearance().answerDefaultColor })
        if let cardView, let answersStackView {
            XCTAssertEqual(
                cardView.bounds.maxY - answersStackView.convert(answersStackView.bounds, to: cardView).maxY,
                20,
                accuracy: 0.5
            )
        }

        let timerBar = viewController.view.descendant(withAccessibilityIdentifier: "questionTimerProgressView") as? UIProgressView
        assertColor(timerBar?.progressTintColor, equals: currentAppearance().accentColor)
        assertColor(timerBar?.tintColor, equals: currentAppearance().accentColor)
        XCTAssertEqual(timerBar?.accessibilityLabel, L10n.Question.timeRemaining)
        XCTAssertFalse(timerBar?.accessibilityValue?.isEmpty ?? true)
    }

    func testQuestionTextIsCenteredBetweenProgressBarAndFirstAnswer() throws {
        QuizFactory.shared.chosenTheme = makeQuestionTheme()
        QuizFactory.shared.questionsCount = 1

        let viewController = QuizQuestionViewController()
        viewController.loadViewIfNeeded()
        defer { viewController.presenter?.stopTimer() }
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()

        let cardView = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "questionCardView"))
        let progressBar = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "questionTimerProgressView"))
        let questionLabel = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "questionTextLabel"))
        let firstAnswer = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "questionAnswerButton1"))
        let progressFrame = progressBar.convert(progressBar.bounds, to: cardView)
        let questionFrame = questionLabel.convert(questionLabel.bounds, to: cardView)
        let firstAnswerFrame = firstAnswer.convert(firstAnswer.bounds, to: cardView)
        let availableGapMidY = (progressFrame.maxY + firstAnswerFrame.minY) / 2

        XCTAssertEqual(questionFrame.midY, availableGapMidY, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(questionFrame.minY - progressFrame.maxY, 24)
        XCTAssertGreaterThanOrEqual(firstAnswerFrame.minY - questionFrame.maxY, 24)
    }

    func testRadarThemeTitleCanShrinkToFitLegacySEWidth() throws {
        UserDefaults.standard.set(AppDesignStyle.radar.rawValue, forKey: AppAppearanceStore.Keys.designStyle)
        QuizFactory.shared.chosenTheme = makeQuestionTheme()
        QuizFactory.shared.questionsCount = 1

        let viewController = QuizQuestionViewController()
        viewController.loadViewIfNeeded()
        defer { viewController.presenter?.stopTimer() }
        viewController.view.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
        viewController.loadQuestionToView(
            QuizQuestionViewModel(
                themeName: "История и культура",
                questionText: "Короткий вопрос?",
                questionNumberText: "Вопрос №1",
                answers: [
                    QuizAnswerOption(id: "theme-0", title: "A"),
                    QuizAnswerOption(id: "theme-1", title: "B"),
                    QuizAnswerOption(id: "theme-2", title: "C"),
                    QuizAnswerOption(id: "theme-3", title: "D")
                ]
            )
        )
        viewController.view.layoutIfNeeded()

        let themeLabel = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "questionThemeLabel") as? UILabel
        )
        let unscaledWidth = (themeLabel.text! as NSString).size(withAttributes: [.font: themeLabel.font!]).width
        let minimumFont = themeLabel.font.withSize(themeLabel.font.pointSize * themeLabel.minimumScaleFactor)
        let minimumWidth = (themeLabel.text! as NSString).size(withAttributes: [.font: minimumFont]).width

        XCTAssertEqual(themeLabel.numberOfLines, 1)
        XCTAssertTrue(themeLabel.adjustsFontSizeToFitWidth)
        XCTAssertEqual(themeLabel.minimumScaleFactor, 0.70, accuracy: 0.001)
        XCTAssertGreaterThan(unscaledWidth, themeLabel.bounds.width)
        XCTAssertLessThanOrEqual(minimumWidth, themeLabel.bounds.width + 0.5)
    }

    func testLongAnswersShrinkWithoutClippingAcrossSelectableStylesAndPhoneSizes() throws {
        let styles: [AppDesignStyle] = [.classic, .radar, .clean]
        let phoneSizes = [
            CGSize(width: 402, height: 874),
            CGSize(width: 375, height: 667),
            CGSize(width: 320, height: 568)
        ]
        let longAnswers = philosopherQuoteAnswers

        for style in styles {
            UserDefaults.standard.set(style.rawValue, forKey: AppAppearanceStore.Keys.designStyle)

            for phoneSize in phoneSizes {
                QuizFactory.shared.chosenTheme = makeQuestionTheme()
                QuizFactory.shared.questionsCount = 1

                let viewController = QuizQuestionViewController()
                viewController.loadViewIfNeeded()
                viewController.view.frame = CGRect(origin: .zero, size: phoneSize)
                viewController.loadQuestionToView(
                    QuizQuestionViewModel(
                        themeName: "Цитаты философов",
                        questionText: "Какое из высказываний принадлежит Иммануилу Канту?",
                        questionNumberText: "Вопрос №2",
                        answers: longAnswers.enumerated().map { index, title in
                            QuizAnswerOption(id: "long-answer-\(index)", title: title)
                        }
                    )
                )
                viewController.view.setNeedsLayout()
                viewController.view.layoutIfNeeded()
                viewController.view.layoutIfNeeded()

                try assertAnswerLabelsFit(in: viewController, expectedTitles: longAnswers)

                let baseFont = currentAppearance().typography.font(size: 18, weight: .semibold)
                let firstAnswerLabel = try XCTUnwrap(questionAnswerButtons(in: viewController).first?.titleLabel)
                if phoneSize.height < 600 {
                    XCTAssertEqual(firstAnswerLabel.font.pointSize, baseFont.pointSize, accuracy: 0.1)
                } else {
                    XCTAssertLessThan(firstAnswerLabel.font.pointSize, baseFont.pointSize)
                }
                let minimumSize = phoneSize.height >= 667 ? baseFont.pointSize * 0.72 - 0.1 : 10
                XCTAssertGreaterThanOrEqual(firstAnswerLabel.font.pointSize, minimumSize)

                let shortAnswers = ["A", "B", "C", "D"]
                viewController.loadQuestionToView(
                    QuizQuestionViewModel(
                        themeName: "Короткая тема",
                        questionText: "Короткий вопрос?",
                        questionNumberText: "Вопрос №3",
                        answers: shortAnswers.enumerated().map { index, title in
                            QuizAnswerOption(id: "short-answer-\(index)", title: title)
                        }
                    )
                )
                viewController.view.setNeedsLayout()
                viewController.view.layoutIfNeeded()
                viewController.view.layoutIfNeeded()

                let shortAnswerButtons = questionAnswerButtons(in: viewController)
                XCTAssertEqual(shortAnswerButtons.count, shortAnswers.count)
                XCTAssertTrue(shortAnswerButtons.allSatisfy {
                    abs(($0.titleLabel?.font.pointSize ?? 0) - baseFont.pointSize) <= 0.1
                })
                viewController.presenter?.stopTimer()
            }
        }
    }

    func testInitialLongAnswersFitBeforeSelectionAndStayStableAfterFeedback() throws {
        UserDefaults.standard.set(AppDesignStyle.radar.rawValue, forKey: AppAppearanceStore.Keys.designStyle)
        let fixture = japanUnificationQuestionFixture
        QuizFactory.shared.chosenTheme = makeQuestionTheme(
            id: "initial_long_answers",
            themeName: "История Японии",
            questionText: fixture.question,
            answers: fixture.answers
        )
        QuizFactory.shared.questionsCount = 1

        let viewController = QuizQuestionViewController()
        viewController.loadViewIfNeeded()
        defer { viewController.presenter?.stopTimer() }

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let answerButtons = questionAnswerButtons(in: viewController)
        let displayedAnswers = answerButtons.compactMap { $0.title(for: .normal) }
        XCTAssertEqual(Set(displayedAnswers), Set(fixture.answers))
        XCTAssertTrue(answerButtons.allSatisfy(\.isEnabled))
        let nextButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "questionNextButton") as? UIButton
        )
        XCTAssertFalse(nextButton.isEnabled)
        try assertAnswerLabelsFit(in: viewController, expectedTitles: displayedAnswers)

        let baseFont = currentAppearance().typography.font(
            size: 18,
            weight: .semibold,
            compatibleWith: viewController.view.traitCollection
        )
        let initialResolvedFontSizes = answerButtons.compactMap { $0.titleLabel?.font.pointSize }
        XCTAssertTrue(initialResolvedFontSizes.contains { $0 < baseFont.pointSize - 0.1 })
        XCTAssertTrue(initialResolvedFontSizes.allSatisfy { $0 >= baseFont.pointSize * 0.72 - 0.1 })

        let initialFontSizes = answerButtons.map { $0.titleLabel?.font.pointSize }
        let initialHeights = answerButtons.map(\.bounds.height)
        let selectedButton = try XCTUnwrap(answerButtons.first)
        selectedButton.sendActions(for: .touchUpInside)
        viewController.view.layoutIfNeeded()

        try assertAnswerLabelsFit(in: viewController, expectedTitles: displayedAnswers)
        XCTAssertEqual(answerButtons.map { $0.titleLabel?.font.pointSize }, initialFontSizes)
        XCTAssertEqual(answerButtons.map(\.bounds.height), initialHeights)
    }

    func testLongQuestionsFitAvailableCardHeightAcrossSelectableStylesAndPhoneSizes() throws {
        let styles: [AppDesignStyle] = [.classic, .radar, .clean]
        let phoneSizes = [
            CGSize(width: 402, height: 874),
            CGSize(width: 375, height: 667),
            CGSize(width: 320, height: 568)
        ]
        let fixture = japanUnificationQuestionFixture

        for style in styles {
            UserDefaults.standard.set(style.rawValue, forKey: AppAppearanceStore.Keys.designStyle)

            for phoneSize in phoneSizes {
                QuizFactory.shared.chosenTheme = makeQuestionTheme()
                QuizFactory.shared.questionsCount = 1

                let viewController = QuizQuestionViewController()
                viewController.loadViewIfNeeded()
                defer { viewController.presenter?.stopTimer() }
                viewController.view.frame = CGRect(origin: .zero, size: phoneSize)
                viewController.loadQuestionToView(
                    QuizQuestionViewModel(
                        themeName: "История Японии",
                        questionText: fixture.question,
                        questionNumberText: "Вопрос №1",
                        answers: fixture.answers.enumerated().map { index, title in
                            QuizAnswerOption(id: "japan-\(index)", title: title)
                        }
                    )
                )
                viewController.view.setNeedsLayout()
                viewController.view.layoutIfNeeded()

                let questionLabel = try XCTUnwrap(
                    viewController.view.descendant(withAccessibilityIdentifier: "questionTextLabel") as? UILabel
                )
                let cardView = try XCTUnwrap(
                    viewController.view.descendant(withAccessibilityIdentifier: "questionCardView")
                )
                let baseFont = currentAppearance().typography.font(
                    size: 26,
                    weight: .bold,
                    compatibleWith: viewController.view.traitCollection
                )
                let fittedHeight = textHeight(
                    fixture.question,
                    font: questionLabel.font,
                    width: questionLabel.bounds.width
                )
                let baseHeight = textHeight(
                    fixture.question,
                    font: baseFont,
                    width: questionLabel.bounds.width
                )
                let questionFrame = questionLabel.convert(questionLabel.bounds, to: cardView)

                XCTAssertEqual(questionLabel.text, fixture.question)
                XCTAssertEqual(questionLabel.numberOfLines, 0)
                XCTAssertEqual(questionLabel.lineBreakMode, .byWordWrapping)
                XCTAssertLessThanOrEqual(questionLabel.font.pointSize, baseFont.pointSize)
                XCTAssertLessThanOrEqual(fittedHeight, baseHeight)
                XCTAssertLessThanOrEqual(fittedHeight, questionLabel.bounds.height + 1)
                if phoneSize.height < 600 {
                    let contentFrame = questionLabel.convert(questionLabel.bounds, to: viewController.questionBodyView)
                    XCTAssertTrue(viewController.questionBodyView.bounds.insetBy(dx: -0.5, dy: -0.5).contains(contentFrame))
                } else {
                    XCTAssertTrue(cardView.bounds.insetBy(dx: -0.5, dy: -0.5).contains(questionFrame))
                }
            }
        }
    }

    func testExtremeQuestionRemainsReadableWithScrollableBody() throws {
        UserDefaults.standard.set(AppDesignStyle.radar.rawValue, forKey: AppAppearanceStore.Keys.designStyle)
        QuizFactory.shared.chosenTheme = makeQuestionTheme()
        QuizFactory.shared.questionsCount = 1

        let viewController = QuizQuestionViewController()
        viewController.loadViewIfNeeded()
        defer { viewController.presenter?.stopTimer() }
        viewController.view.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
        let fixture = japanUnificationQuestionFixture
        let extremeQuestion = String(repeating: fixture.question + " ", count: 5)
        viewController.loadQuestionToView(
            QuizQuestionViewModel(
                themeName: "История Японии",
                questionText: extremeQuestion,
                questionNumberText: "Вопрос №1",
                answers: fixture.answers.enumerated().map { index, title in
                    QuizAnswerOption(id: "extreme-question-\(index)", title: title)
                }
            )
        )
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let questionLabel = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "questionTextLabel") as? UILabel
        )
        let container = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "questionCardContainerView")
        )
        let nextButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "questionNextButton") as? UIButton
        )
        let baseFont = currentAppearance().typography.font(
            size: 26,
            weight: .bold,
            compatibleWith: viewController.view.traitCollection
        )
        let requiredHeight = textHeight(
            extremeQuestion,
            font: questionLabel.font,
            width: questionLabel.bounds.width
        )

        XCTAssertEqual(questionLabel.font.pointSize, baseFont.pointSize, accuracy: 0.1)
        XCTAssertGreaterThan(viewController.questionBodyScrollView.contentSize.height, viewController.questionBodyScrollView.bounds.height)
        XCTAssertLessThanOrEqual(requiredHeight, questionLabel.bounds.height + 0.5)
        XCTAssertFalse(container is UIScrollView)
        XCTAssertTrue(container.bounds.contains(viewController.questionCardView.frame))
        XCTAssertFalse(nextButton.isDescendant(of: container))
        XCTAssertLessThanOrEqual(container.frame.maxY, nextButton.frame.minY)
    }

    func testQuestionFontRestoresForShortQuestionAndRefitsAfterWidthChange() throws {
        UserDefaults.standard.set(AppDesignStyle.radar.rawValue, forKey: AppAppearanceStore.Keys.designStyle)
        QuizFactory.shared.chosenTheme = makeQuestionTheme()
        QuizFactory.shared.questionsCount = 1

        let viewController = QuizQuestionViewController()
        viewController.loadViewIfNeeded()
        defer { viewController.presenter?.stopTimer() }
        let fixture = japanUnificationQuestionFixture
        let longQuestionViewModel = QuizQuestionViewModel(
            themeName: "История Японии",
            questionText: fixture.question,
            questionNumberText: "Вопрос №1",
            answers: fixture.answers.enumerated().map { index, title in
                QuizAnswerOption(id: "resize-question-\(index)", title: title)
            }
        )

        viewController.view.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
        viewController.loadQuestionToView(longQuestionViewModel)
        viewController.view.layoutIfNeeded()
        let questionLabel = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "questionTextLabel") as? UILabel
        )
        let compactPointSize = questionLabel.font.pointSize

        viewController.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()
        let widePointSize = questionLabel.font.pointSize
        XCTAssertGreaterThanOrEqual(widePointSize, compactPointSize)

        viewController.loadQuestionToView(
            QuizQuestionViewModel(
                themeName: "Короткая тема",
                questionText: "Короткий вопрос?",
                questionNumberText: "Вопрос №2",
                answers: ["A", "B", "C", "D"].enumerated().map { index, title in
                    QuizAnswerOption(id: "short-question-\(index)", title: title)
                }
            )
        )
        viewController.view.layoutIfNeeded()

        let baseFont = currentAppearance().typography.font(
            size: 26,
            weight: .bold,
            compatibleWith: viewController.view.traitCollection
        )
        XCTAssertEqual(questionLabel.font.pointSize, baseFont.pointSize, accuracy: 0.1)
    }

    func testLongAnswersPreserveAccessibilityFontsInScrollableContent() throws {
        UserDefaults.standard.set(AppDesignStyle.classic.rawValue, forKey: AppAppearanceStore.Keys.designStyle)
        QuizFactory.shared.chosenTheme = makeQuestionTheme()
        QuizFactory.shared.questionsCount = 1

        let viewController = QuizQuestionViewController()
        viewController.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        viewController.loadViewIfNeeded()
        defer { viewController.presenter?.stopTimer() }
        viewController.view.frame = CGRect(x: 0, y: 0, width: 375, height: 667)
        viewController.loadQuestionToView(
            QuizQuestionViewModel(
                themeName: "Цитаты философов",
                questionText: "Какое из высказываний принадлежит Иммануилу Канту?",
                questionNumberText: "Вопрос №2",
                answers: philosopherQuoteAnswers.enumerated().map { index, title in
                    QuizAnswerOption(id: "accessibility-answer-\(index)", title: title)
                }
            )
        )
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()
        viewController.view.layoutIfNeeded()

        try assertAnswerLabelsFit(in: viewController, expectedTitles: philosopherQuoteAnswers)

        let typography = currentAppearance().typography
        let defaultFont = typography.font(
            size: 18,
            weight: .semibold,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        )
        let accessibilityFont = typography.font(
            size: 18,
            weight: .semibold,
            compatibleWith: viewController.traitCollection
        )
        let firstAnswerLabel = try XCTUnwrap(questionAnswerButtons(in: viewController).first?.titleLabel)

        XCTAssertGreaterThan(accessibilityFont.pointSize, defaultFont.pointSize)
        XCTAssertEqual(firstAnswerLabel.font.pointSize, accessibilityFont.pointSize, accuracy: 0.1)
        XCTAssertGreaterThan(viewController.questionBodyScrollView.contentSize.height, viewController.questionBodyScrollView.bounds.height)
        XCTAssertFalse(viewController.cardContainerView is UIScrollView)
        XCTAssertTrue(viewController.cardContainerView.bounds.contains(viewController.questionCardView.frame))
        XCTAssertLessThanOrEqual(
            textHeight(viewController.questionLabel.text!, font: viewController.questionLabel.font, width: viewController.questionLabel.bounds.width),
            viewController.questionLabel.bounds.height + 1
        )
    }

}

@MainActor
final class QuizQuestionIPadLayoutTests: CrossScreenVisualTestCase {
    func testExplanationAndQuestionReturnIntoViewAfterScrollingToAnswers() throws {
        let controller = QuizQuestionViewController()
        let presenter = ExitConfirmationPresenterSpy()
        controller.configurePresenter(presenter)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 744, height: 400)
        let answers = (0..<4).map { index in
            String(repeating: "Длинный вариант ответа \(index). ", count: 12)
        }
        controller.loadQuestionToView(QuizQuestionViewModel(
            themeName: "Тема", questionText: "Какой ответ правильный?", questionNumberText: "Вопрос №2",
            answers: answers.enumerated().map { QuizAnswerOption(id: String($0.offset), title: $0.element) },
            explanation: "Пояснение к выбранному ответу."
        ))
        controller.view.layoutIfNeeded()
        controller.updateProgress(0.42)
        let starts = presenter.startTimerCallCount
        let bodyScroll = try XCTUnwrap(controller.questionBodyScrollView)
        let bottomOffset = bodyScroll.contentSize.height - bodyScroll.bounds.height
        XCTAssertGreaterThan(bottomOffset, 0)
        bodyScroll.setContentOffset(CGPoint(x: 0, y: bottomOffset), animated: false)
        let explanation = try XCTUnwrap(controller.questionExplanationScrollView)
        XCTAssertLessThan(explanation.convert(explanation.bounds, to: bodyScroll).maxY, bodyScroll.bounds.minY)

        controller.colorAndDisableButtons()
        XCTAssertTrue(controller.isQuestionExplanationVisible)
        XCTAssertEqual(explanation.contentOffset.y, 0, accuracy: 0.5)
        let explanationStart = controller.questionExplanationLabel.convert(CGPoint.zero, to: bodyScroll)
        XCTAssertGreaterThanOrEqual(explanationStart.y, bodyScroll.bounds.minY)
        XCTAssertLessThan(explanationStart.y, bodyScroll.bounds.maxY)

        bodyScroll.setContentOffset(CGPoint(x: 0, y: bottomOffset), animated: false)
        controller.questionExplanationBackButtonTapped()
        XCTAssertFalse(controller.isQuestionExplanationVisible)
        XCTAssertEqual(bodyScroll.contentOffset.y, 0, accuracy: 0.5)
        XCTAssertTrue(bodyScroll.bounds.intersects(controller.questionLabel.convert(controller.questionLabel.bounds, to: bodyScroll)))

        bodyScroll.setContentOffset(CGPoint(x: 0, y: bottomOffset), animated: false)
        controller.questionInfoButtonTapped()
        XCTAssertTrue(controller.isQuestionExplanationVisible)
        let reopenedStart = controller.questionExplanationLabel.convert(CGPoint.zero, to: bodyScroll)
        XCTAssertGreaterThanOrEqual(reopenedStart.y, bodyScroll.bounds.minY)
        XCTAssertLessThan(reopenedStart.y, bodyScroll.bounds.maxY)
        XCTAssertEqual(controller.currentAnswerOptions.map(\.title), answers)
        XCTAssertEqual(controller.timerBar.progress, 0.42, accuracy: 0.001)
        XCTAssertEqual(presenter.startTimerCallCount, starts)
    }

    func testShortExplanationIsVisibleWithinVeryLongQuestionSpace() throws {
        let controller = QuizQuestionViewController()
        controller.configurePresenter(ExitConfirmationPresenterSpy())
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 375, height: 400)
        controller.loadQuestionToView(QuizQuestionViewModel(
            themeName: "Тема",
            questionText: String(repeating: "Длинный текст вопроса для маленького окна. ", count: 30),
            questionNumberText: "Вопрос №1",
            answers: ["A", "B", "C", "D"].map { QuizAnswerOption(id: $0, title: $0) },
            explanation: "Короткое пояснение."
        ))
        controller.view.layoutIfNeeded()
        let bodyScroll = try XCTUnwrap(controller.questionBodyScrollView)
        let initialTextTop = controller.questionExplanationLabel.convert(CGPoint.zero, to: bodyScroll).y
        XCTAssertGreaterThan(initialTextTop, bodyScroll.bounds.maxY)

        controller.revealQuestionExplanation()
        XCTAssertTrue(controller.isQuestionExplanationVisible)
        let textTop = controller.questionExplanationLabel.convert(CGPoint.zero, to: bodyScroll).y
        XCTAssertGreaterThanOrEqual(textTop, bodyScroll.bounds.minY)
        XCTAssertLessThan(textTop, bodyScroll.bounds.maxY)
    }

    func testIPadResizePreservesQuestionAnswersAndTimer() throws {
        for style in [AppDesignStyle.classic, .radar, .clean] {
            UserDefaults.standard.set(style.rawValue, forKey: AppAppearanceStore.Keys.designStyle)
        let controller = QuizQuestionViewController()
        let presenter = ExitConfirmationPresenterSpy()
        controller.configurePresenter(presenter)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 834, height: 1194)
        let answers = ["Один", "Два", "Три", "Четыре"]
        controller.loadQuestionToView(QuizQuestionViewModel(
            themeName: "Тема", questionText: "Вопрос сохраняется при изменении окна?", questionNumberText: "Вопрос №2",
            answers: answers.enumerated().map { QuizAnswerOption(id: String($0.offset), title: $0.element) }
        ))
        controller.view.layoutIfNeeded()
        controller.updateProgress(0.42)
        let starts = presenter.startTimerCallCount
        for size in [CGSize(width: 1194, height: 834), CGSize(width: 744, height: 400), CGSize(width: 375, height: 600), CGSize(width: 834, height: 1194)] {
            controller.view.frame.size = size
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            controller.view.layoutIfNeeded()
            XCTAssertEqual(controller.questionLabel.text, "Вопрос сохраняется при изменении окна?")
            XCTAssertEqual(controller.currentAnswerOptions.map(\.title), answers)
            XCTAssertEqual(controller.timerBar.progress, 0.42, accuracy: 0.001)
            XCTAssertEqual(presenter.startTimerCallCount, starts)
            XCTAssertEqual(controller.questionCardView.bounds.width, min(size.width - 40, size.width < 600 ? 430 : 640), accuracy: 1)
            XCTAssertLessThanOrEqual(controller.nextButton.frame.maxY, size.height)
            try assertAnswerLabelsFit(in: controller, expectedTitles: answers)
            if size.height == 400 {
                XCTAssertGreaterThan(controller.questionBodyScrollView.contentSize.height, controller.questionBodyScrollView.bounds.height)
                XCTAssertGreaterThanOrEqual(controller.questionLabel.font.pointSize, 26)
                controller.questionBodyScrollView.setContentOffset(CGPoint(x: 0, y: controller.questionBodyScrollView.contentSize.height - controller.questionBodyScrollView.bounds.height), animated: false)
                let last = try XCTUnwrap(controller.answerButtons.last)
                let frame = last.convert(last.bounds, to: controller.questionBodyScrollView)
                XCTAssertLessThanOrEqual(frame.maxY, controller.questionBodyScrollView.bounds.maxY)
            }
        }
        }
    }

    func testResultFitsIPadAndShortWindowWithReachableActions() throws {
        let controller = QuizResultViewController()
        controller.loadViewIfNeeded()
        controller.updateResultLabels(resultText: "5/5", descriptionText: String(repeating: "Отличный результат! ", count: 20))
        for size in [CGSize(width: 834, height: 1194), CGSize(width: 1194, height: 400), CGSize(width: 375, height: 600)] {
            controller.view.frame = CGRect(origin: .zero, size: size)
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            controller.view.layoutIfNeeded()
            let card = try XCTUnwrap(controller.view.descendant(withAccessibilityIdentifier: "resultCardView"))
            let scroll = try XCTUnwrap(controller.view.descendant(withAccessibilityIdentifier: "resultScrollView") as? UIScrollView)
            let themes = try XCTUnwrap(controller.view.descendant(withAccessibilityIdentifier: "resultThemesButton"))
            XCTAssertEqual(card.bounds.width, min(size.width - 40, size.width < 600 ? 430 : 560), accuracy: 1)
            let actionRect = themes.convert(themes.bounds, to: scroll)
            scroll.scrollRectToVisible(actionRect, animated: false)
            XCTAssertTrue(scroll.bounds.insetBy(dx: -1, dy: -1).contains(themes.convert(themes.bounds, to: scroll)))
        }
    }

    func testResizeFinishesIncomingQuestionTransitionExactlyOnce() {
        let controller = QuizQuestionViewController()
        let presenter = ExitConfirmationPresenterSpy()
        controller.configurePresenter(presenter)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 834, height: 1194)
        controller.view.layoutIfNeeded()
        let starts = presenter.startTimerCallCount
        controller.isQuestionTransitionInProgress = true
        controller.questionCardView.isUserInteractionEnabled = false
        controller.questionCardView.transform = CGAffineTransform(translationX: 800, y: 0)
        controller.view.frame.size = CGSize(width: 744, height: 400)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        controller.completeQuestionTransition() // The old animation's late completion.
        XCTAssertFalse(controller.isQuestionTransitionInProgress)
        XCTAssertTrue(controller.questionCardView.isUserInteractionEnabled)
        XCTAssertEqual(controller.questionCardView.transform, .identity)
        XCTAssertEqual(presenter.startTimerCallCount, starts + 1)
    }

}

@MainActor
private final class QuestionLayoutTestWindow: UIWindow {
    var testSafeAreaInsets = UIEdgeInsets.zero
    override var safeAreaInsets: UIEdgeInsets { testSafeAreaInsets }
}
