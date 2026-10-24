import SwiftUI
import XCTest
@testable import Quizice

@MainActor
final class HomeAIThemeCardInteractionTests: HomeScreenVisualStateTestCase {
    func testServiceNoticeDoesNotBlockSubmissionAndSurvivesProgressUpdates() {
        let notice = "Сейчас вопросы создаются с задержкой."
        for designStyle in AppDesignStyle.allCases {
            let cardView = makeHostedServiceNoticeCard()
            let appearance = AppAppearance(
                designStyle: designStyle,
                cleanColorSchemePreference: .dark,
                traitCollection: UITraitCollection(userInterfaceStyle: .dark)
            )
            var state = HomeAIThemeCardState()
            HomeAIThemeCardReducer.reduce(state: &state, action: .promptChanged("Космос"))
            cardView.configure(state: state, appearance: appearance)
            cardView.setServiceNotice("  \(notice)\n")
            cardView.layoutIfNeeded()
            attachServiceNoticeCard(cardView, name: "Service notice — \(designStyle.rawValue) front")

            XCTAssertTrue(cardView.promptTextView.isEditable)
            XCTAssertTrue(cardView.playButton.isEnabled)
            XCTAssertTrue(cardView.submitButton.isEnabled)
            var submissionCount = 0
            cardView.onSubmit = { submissionCount += 1 }
            cardView.setFace(.back, animated: false)
            cardView.layoutIfNeeded()
            attachServiceNoticeCard(cardView, name: "Service notice — \(designStyle.rawValue) back")
            cardView.submitButton.sendActions(for: .touchUpInside)
            XCTAssertEqual(submissionCount, 1)

            let requestID = UUID()
            HomeAIThemeCardReducer.reduce(
                state: &state,
                action: .submitRequested(
                    requestID: requestID,
                    locale: Locale(identifier: "ru"),
                    now: Date()
                )
            )
            cardView.configure(state: state, appearance: appearance)
            HomeAIThemeCardReducer.reduce(
                state: &state,
                action: .progressAdvanced(requestID: requestID, phase: .generating)
            )
            cardView.configure(state: state, appearance: appearance)

            XCTAssertEqual(cardView.progressLabel.text, AIQuizGenerationPhase.generating.title)
            for label in [cardView.frontServiceNoticeLabel, cardView.backServiceNoticeLabel] {
                XCTAssertEqual(label.text, notice)
                XCTAssertEqual(label.accessibilityLabel, notice)
                XCTAssertFalse(label.isHidden)
                XCTAssertFalse(label.accessibilityElementsHidden)
                XCTAssertTrue(label.isAccessibilityElement)
                assertColor(label.textColor, equals: appearance.secondarySurfaceTextColor)
            }
            XCTAssertTrue(
                (cardView.frontFaceView.accessibilityElements as? [UIView])?
                    .contains(cardView.frontServiceNoticeLabel) == true
            )
            XCTAssertTrue(
                (cardView.backFaceView.accessibilityElements as? [UIView])?
                    .contains(cardView.backServiceNoticeLabel) == true
            )
        }
    }

    func testClearingServiceNoticeRemovesItsLayoutSpaceOnBothFaces() {
        let cardView = makeHostedServiceNoticeCard()
        let appearance = AppAppearance(
            designStyle: .clean,
            cleanColorSchemePreference: .dark,
            traitCollection: UITraitCollection(userInterfaceStyle: .dark)
        )
        cardView.configure(state: HomeAIThemeCardState(), appearance: appearance)
        let missingMessages: [String?] = [nil, "", " \n\t "]
        let faces: [(HomeThemeCardFace, UIStackView)] = [
            (.front, cardView.frontContentStack),
            (.back, cardView.backContentStack)
        ]
        for (face, stack) in faces {
            cardView.setFace(face, animated: false)
            cardView.setServiceNotice(nil)
            cardView.layoutIfNeeded()
            let heightWithoutNotice = stack.bounds.height

            for missingMessage in missingMessages {
                cardView.setServiceNotice("Сейчас вопросы создаются с задержкой.")
                cardView.layoutIfNeeded()
                XCTAssertGreaterThan(stack.bounds.height, heightWithoutNotice)

                cardView.setServiceNotice(missingMessage)
                cardView.layoutIfNeeded()

                XCTAssertEqual(stack.bounds.height, heightWithoutNotice, accuracy: 0.5)
                for label in [cardView.frontServiceNoticeLabel, cardView.backServiceNoticeLabel] {
                    XCTAssertTrue(label.isHidden)
                    XCTAssertTrue(label.accessibilityElementsHidden)
                    XCTAssertNil(label.text)
                    XCTAssertNil(label.accessibilityLabel)
                }
            }
        }
    }

    func testLongServiceNoticeWrapsAndRemainsScrollableWithAccessibilityTextSize() {
        let cardView = makeHostedServiceNoticeCard(
            size: CGSize(width: 280, height: 400),
            category: .accessibilityExtraExtraExtraLarge
        )
        let appearance = AppAppearance(
            designStyle: .clean,
            cleanColorSchemePreference: .dark,
            traitCollection: cardView.traitCollection
        )
        cardView.configure(state: HomeAIThemeCardState(), appearance: appearance)
        cardView.setServiceNotice(
            "Сейчас вопросы создаются с задержкой. Создание может занять несколько минут."
        )
        cardView.layoutIfNeeded()

        let faces: [(HomeThemeCardFace, UILabel, UIScrollView, UIStackView)] = [
            (.front, cardView.frontServiceNoticeLabel, cardView.frontScrollView, cardView.frontContentStack),
            (.back, cardView.backServiceNoticeLabel, cardView.backScrollView, cardView.backContentStack)
        ]
        for (face, label, scrollView, stack) in faces {
            cardView.setFace(face, animated: false)
            cardView.setNeedsLayout()
            cardView.layoutIfNeeded()
            XCTAssertEqual(label.numberOfLines, 0)
            XCTAssertTrue(label.adjustsFontForContentSizeCategory)
            XCTAssertGreaterThan(label.font.pointSize, ExpandedAIThemeCardView.Typography.serviceNoticeSize)
            XCTAssertGreaterThan(label.bounds.height, label.font.lineHeight)
            let fittedHeight = label.sizeThatFits(
                CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)
            ).height
            XCTAssertGreaterThanOrEqual(label.bounds.height + 0.5, fittedHeight)
            XCTAssertGreaterThan(scrollView.contentSize.height, scrollView.bounds.height)
            XCTAssertEqual(stack.bounds.maxY, label.frame.maxY, accuracy: 0.5)
            scrollView.scrollRectToVisible(label.convert(label.bounds, to: scrollView), animated: false)
            attachServiceNoticeCard(cardView, name: "Service notice — accessibility \(face)")
        }
        XCTAssertFalse(cardView.promptTextView.isScrollEnabled)
        cardView.updateKeyboardInsets(overlap: 200, duration: 0, options: [])
        XCTAssertEqual(cardView.frontScrollView.contentInset.bottom, 212)
        XCTAssertFalse(cardView.frontServiceNoticeLabel.isHidden)
    }

    private func makeHostedServiceNoticeCard(
        size: CGSize = CGSize(width: 342, height: 640),
        category: UIContentSizeCategory = .large
    ) -> ExpandedAIThemeCardView {
        let cardView = ExpandedAIThemeCardView(frame: CGRect(origin: CGPoint(x: 20, y: 20), size: size))
        let host = UIViewController()
        host.view.addSubview(cardView)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: size.width + 40, height: size.height + 40))
        window.rootViewController = host
        window.makeKeyAndVisible()
        testWindows.append(window)
        cardView.traitOverrides.preferredContentSizeCategory = category
        cardView.updateTraitsIfNeeded()
        window.layoutIfNeeded()
        XCTAssertEqual(cardView.traitCollection.preferredContentSizeCategory, category)
        return cardView
    }

    private func attachServiceNoticeCard(_ cardView: ExpandedAIThemeCardView, name: String) {
        let image = UIGraphicsImageRenderer(bounds: cardView.bounds).image { _ in
            cardView.drawHierarchy(in: cardView.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPromptPlaceholderMatchesTextEntryOrigin() {
        let cardView = ExpandedAIThemeCardView(
            frame: CGRect(x: 0, y: 0, width: 342, height: 640)
        )
        let appearance = AppAppearance(
            designStyle: .clean,
            cleanColorSchemePreference: .dark,
            traitCollection: UITraitCollection(userInterfaceStyle: .dark)
        )
        cardView.configure(state: HomeAIThemeCardState(), appearance: appearance)
        cardView.layoutIfNeeded()

        let textView = cardView.promptTextView
        let placeholder = cardView.promptPlaceholderLabel
        let expectedX = textView.frame.minX
            + textView.textContainerInset.left
            + textView.textContainer.lineFragmentPadding
        let expectedY = textView.frame.minY + textView.textContainerInset.top

        XCTAssertEqual(placeholder.frame.minX, expectedX, accuracy: 0.5)
        XCTAssertEqual(placeholder.frame.minY, expectedY, accuracy: 0.5)
    }

    func testGuestTapShowsAuthenticationAlertWithoutOpeningAIThemeCard() async throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка")]
        let viewController = QuizViewController(
            aiQuizAccessProvider: HomeAIQuizAccessStub(isAvailable: false)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        testWindows.append(window)
        let sourceButton = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeCreateWithAIButton"
            ) as? UIButton
        )

        sourceButton.sendActions(for: .touchUpInside)

        try await waitUntil {
            viewController.aiAlertPresenter.alertViewController != nil
        }

        XCTAssertEqual(viewController.homeCardState.phase, .grid)
        XCTAssertNil(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeExpandedAIThemeCard"
            )
        )

        let alertViewController = try XCTUnwrap(
            viewController.aiAlertPresenter.alertViewController
        )
        XCTAssertTrue(alertViewController.isModalInPresentation)
        XCTAssertTrue(alertViewController.view.accessibilityViewIsModal)
    }

    func testAIThemeCardExpandsInlineAboveFullScreenBackdropAndDisablesGrid() throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка")]

        let viewController = makeHomeViewController(in: CGRect(x: 0, y: 0, width: 390, height: 844))
        let router = HomeRouterSpy()
        viewController.router = router
        let collectionView = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeThemesCollectionView"
            ) as? UICollectionView
        )
        collectionView.layoutIfNeeded()
        let sourceButton = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeCreateWithAIButton"
            ) as? UIButton
        )
        let initialScrollEnabled = collectionView.isScrollEnabled
        let initialContentOffset = collectionView.contentOffset

        sourceButton.sendActions(for: .touchUpInside)
        drainAnimations()

        let backdrop = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeExpandedThemeCardBackdrop"
            )
        )
        let card = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeExpandedAIThemeCard"
            )
        )

        XCTAssertTrue(backdrop.superview === viewController.view)
        XCTAssertEqual(backdrop.frame, viewController.view.bounds)
        XCTAssertTrue(backdrop is UIVisualEffectView)
        XCTAssertNotNil((backdrop as? UIVisualEffectView)?.effect)
        XCTAssertTrue(card.superview === viewController.view)
        XCTAssertFalse(card.isDescendant(of: backdrop))
        XCTAssertGreaterThan(card.layer.zPosition, backdrop.layer.zPosition)
        XCTAssertTrue(card.accessibilityViewIsModal)
        let presentedSourceButton = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeCreateWithAIButton"
            ) as? UIButton
        )
        XCTAssertTrue(presentedSourceButton.isHidden)
        XCTAssertFalse(presentedSourceButton.isEnabled)
        XCTAssertFalse(collectionView.isUserInteractionEnabled)
        XCTAssertFalse(collectionView.isScrollEnabled)
        XCTAssertNil(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeExpandedAIThemeCardTransition"
            )
        )

        let backdropDismissButton = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeExpandedThemeCardBackdropDismissButton"
            ) as? UIButton
        )
        backdropDismissButton.sendActions(for: .touchUpInside)
        drainAnimations()

        XCTAssertNil(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeExpandedAIThemeCard"
            )
        )
        XCTAssertNil(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeExpandedThemeCardBackdrop"
            )
        )
        let restoredSourceButton = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeCreateWithAIButton"
            ) as? UIButton
        )
        XCTAssertFalse(restoredSourceButton.isHidden)
        XCTAssertTrue(restoredSourceButton.isEnabled)
        XCTAssertTrue(restoredSourceButton.isAccessibilityElement)
        XCTAssertTrue(collectionView.isUserInteractionEnabled)
        XCTAssertEqual(collectionView.isScrollEnabled, initialScrollEnabled)
        XCTAssertEqual(collectionView.contentOffset.x, initialContentOffset.x, accuracy: 0.001)
        XCTAssertEqual(collectionView.contentOffset.y, initialContentOffset.y, accuracy: 0.001)
    }

    func testAIThemeCardRequiresTrimmedPromptBeforeFlipAndHasNoParallax() throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка")]

        let motionProvider = HomeThemeCardMotionProviderFake()
        let viewController = QuizViewController(
            cardReduceMotionProvider: { false },
            cardDeviceParallaxEnabledProvider: { true },
            cardMotionProvider: motionProvider
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        testWindows.append(window)
        let collectionView = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeThemesCollectionView"
            ) as? UICollectionView
        )
        collectionView.layoutIfNeeded()
        let sourceButton = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeCreateWithAIButton"
            ) as? UIButton
        )

        sourceButton.sendActions(for: .touchUpInside)
        drainAnimations()

        let card = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeExpandedAIThemeCard"
            )
        )
        let cardView = try XCTUnwrap(card as? ExpandedAIThemeCardView)
        let promptEditor = try XCTUnwrap(
            card.descendant(withAccessibilityIdentifier: "aiThemePromptEditor") as? UITextView
        )
        let playButton = try XCTUnwrap(
            card.descendant(
                withAccessibilityIdentifier: "expandedAIThemeCardPlayButton"
            ) as? UIButton
        )
        let frontView = try XCTUnwrap(
            card.descendant(withAccessibilityIdentifier: "expandedAIThemeCardFrontView")
        )
        let backView = try XCTUnwrap(
            card.descendant(withAccessibilityIdentifier: "expandedAIThemeCardBackView")
        )

        XCTAssertFalse(playButton.isEnabled)
        XCTAssertFalse(frontView.isHidden)
        XCTAssertTrue(backView.isHidden)
        XCTAssertFalse(promptEditor.isFirstResponder)
        XCTAssertFalse(promptEditor.isScrollEnabled)
        XCTAssertEqual(cardView.backTitleLabel.numberOfLines, 2)
        XCTAssertEqual(cardView.backTitleLabel.lineBreakMode, .byTruncatingTail)

        promptEditor.text = " \n\t "
        promptEditor.delegate?.textViewDidChange?(promptEditor)

        XCTAssertFalse(playButton.isEnabled)

        promptEditor.text = "  Космос  \n"
        promptEditor.delegate?.textViewDidChange?(promptEditor)

        XCTAssertTrue(playButton.isEnabled)

        promptEditor.text = String(
            repeating: "Очень длинная тема ",
            count: 10
        )
        promptEditor.delegate?.textViewDidChange?(promptEditor)

        let validationLabel = try XCTUnwrap(
            card.descendant(withAccessibilityIdentifier: "aiThemePromptValidation") as? UILabel
        )
        XCTAssertFalse(validationLabel.isHidden)
        XCTAssertEqual(
            validationLabel.text,
            L10n.AITheme.promptTooLong(
                maximumLength: AIQuizGenerationConfiguration.maximumThemeLength
            )
        )
        XCTAssertFalse(playButton.isEnabled)

        promptEditor.text = "  Космос  \n"
        promptEditor.delegate?.textViewDidChange?(promptEditor)
        XCTAssertTrue(validationLabel.isHidden)
        XCTAssertTrue(playButton.isEnabled)

        playButton.sendActions(for: .touchUpInside)
        drainAnimations()

        XCTAssertTrue(frontView.isHidden)
        XCTAssertFalse(backView.isHidden)
        XCTAssertFalse(backView.accessibilityElementsHidden)
        XCTAssertNil(
            card.descendant(
                withAccessibilityIdentifier: "expandedAIThemeCardParallaxCarrier"
            )
        )
        XCTAssertNil(
            card.descendant(
                withAccessibilityIdentifier: "expandedThemeCardParallaxCarrier"
            )
        )
        XCTAssertNil(parallaxPanGestureRecognizer(in: card))
        XCTAssertFalse(
            (card.gestureRecognizers ?? []).contains { $0 is UIPanGestureRecognizer }
        )
        XCTAssertEqual(motionProvider.startCallCount, 0)
        XCTAssertFalse(motionProvider.isStarted)
    }

    func testAIThemeCardMovesUpForKeyboardWithoutAccumulatingOffsetAndRestores() throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка")]
        let viewController = QuizViewController(cardReduceMotionProvider: { false })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        testWindows.append(window)

        let sourceButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeCreateWithAIButton") as? UIButton
        )
        sourceButton.sendActions(for: .touchUpInside)
        drainAnimations()

        let card = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedAIThemeCard") as? ExpandedAIThemeCardView
        )
        let promptEditor = try XCTUnwrap(
            card.descendant(withAccessibilityIdentifier: "aiThemePromptEditor") as? UITextView
        )
        let promptContainer = try XCTUnwrap(promptEditor.superview)
        let originalFrame = card.frame
        XCTAssertTrue(promptEditor.becomeFirstResponder())

        let initialPromptFrame = promptContainer.convert(promptContainer.bounds, to: viewController.view)
        let keyboardTop = initialPromptFrame.maxY - 36
        let keyboardFrameInWindow = CGRect(
            x: 0,
            y: keyboardTop,
            width: window.bounds.width,
            height: window.bounds.maxY - keyboardTop
        )
        // The fixture intentionally owns a window without a scene. Inject window
        // coordinates at the notification adapter boundary, because screen-space
        // conversion is undefined for this detached test window.
        card.updateKeyboardFrameInWindow(keyboardFrameInWindow, duration: 0, options: [])
        viewController.view.layoutIfNeeded()

        XCTAssertLessThan(card.frame.minY, originalFrame.minY)
        XCTAssertGreaterThanOrEqual(
            card.frame.minY,
            viewController.view.safeAreaLayoutGuide.layoutFrame.minY + 7.5
        )
        let visiblePromptFrame = promptContainer.convert(promptContainer.bounds, to: viewController.view)
        XCTAssertLessThanOrEqual(visiblePromptFrame.maxY, keyboardTop - 11.5)

        let firstLiftedFrame = card.frame
        card.updateKeyboardFrameInWindow(keyboardFrameInWindow, duration: 0, options: [])
        XCTAssertEqual(card.frame.minY, firstLiftedFrame.minY, accuracy: 0.01)

        card.updateKeyboardFrameInWindow(nil, duration: 0, options: [])
        XCTAssertEqual(card.frame.minY, originalFrame.minY, accuracy: 0.01)
        _ = promptEditor.resignFirstResponder()
    }

    func testAIThemeCollapseStartsFromVisibleFrameDuringKeyboardLift() throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка")]
        let viewController = QuizViewController(cardReduceMotionProvider: { false })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        testWindows.append(window)

        let sourceButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeCreateWithAIButton") as? UIButton
        )
        sourceButton.sendActions(for: .touchUpInside)
        drainAnimations()

        let card = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedAIThemeCard")
                as? ExpandedAIThemeCardView
        )
        let closeButton = try XCTUnwrap(
            card.descendant(withAccessibilityIdentifier: "expandedAIThemeCardCloseButton") as? UIButton
        )
        let restingFrame = card.frame

        let keyboardTop = card.frame.minY + card.promptContainerMaxYAtRest - 80
        let keyboardFrameInWindow = CGRect(
            x: 0,
            y: keyboardTop,
            width: window.bounds.width,
            height: window.bounds.maxY - keyboardTop
        )
        viewController.updateExpandedAIThemeCardFrameForTesting(
            keyboardFrameInWindow: keyboardFrameInWindow,
            duration: 0.8,
            curveRawValue: 7
        )
        _ = try XCTUnwrap(viewController.expandedAIKeyboardAnimatorForTesting)
        XCTAssertEqual(viewController.expandedAIKeyboardAnimationCurveForTesting, .easeInOut)
        let liftedFrame = card.frame
        let visibleCardFrame = CGRect(
            x: restingFrame.minX,
            y: restingFrame.minY + (liftedFrame.minY - restingFrame.minY) * 0.25,
            width: restingFrame.width,
            height: restingFrame.height
        )
        viewController.freezeExpandedAIKeyboardAnimationForTesting(
            visibleFrame: visibleCardFrame
        )
        closeButton.sendActions(for: .touchUpInside)

        XCTAssertNil(viewController.expandedAIKeyboardAnimatorForTesting)
        let collapseStartFrame = try XCTUnwrap(
            viewController.expandedCardTransitionInitialFrameForTesting
        )

        XCTAssertEqual(collapseStartFrame.minY, visibleCardFrame.minY, accuracy: 2)
        XCTAssertEqual(collapseStartFrame.height, visibleCardFrame.height, accuracy: 2)

        drainAnimations()
    }

    func testExpandedAIThemeCardUsesOpaqueGrayClassicSurface() {
        let cardView = ExpandedAIThemeCardView(
            frame: CGRect(x: 0, y: 0, width: 342, height: 640)
        )
        let classicAppearance = AppAppearance(
            designStyle: .classic,
            cleanColorSchemePreference: .dark,
            traitCollection: UITraitCollection(userInterfaceStyle: .dark)
        )

        cardView.configure(
            state: HomeAIThemeCardState(),
            appearance: classicAppearance
        )

        let classicSurfaceColor = cardView.configuredSurfaceStyle?.backgroundColor
        XCTAssertFalse(
            classicSurfaceColor?.isEqual(
                classicAppearance.dialogSurface.backgroundColor
            ) == true
        )
        XCTAssertEqual(
            cardView.frontSurfaceView.backgroundColor?.cgColor.alpha ?? -1,
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            cardView.backSurfaceView.backgroundColor?.cgColor.alpha ?? -1,
            1,
            accuracy: 0.001
        )
        assertColor(cardView.frontSurfaceView.backgroundColor, equals: classicSurfaceColor ?? .clear)
        assertColor(cardView.backSurfaceView.backgroundColor, equals: classicSurfaceColor ?? .clear)

        var surfaceRed: CGFloat = 0
        var surfaceGreen: CGFloat = 0
        var surfaceBlue: CGFloat = 0
        var surfaceAlpha: CGFloat = 0
        var backgroundRed: CGFloat = 0
        var backgroundGreen: CGFloat = 0
        var backgroundBlue: CGFloat = 0
        var backgroundAlpha: CGFloat = 0
        XCTAssertTrue(
            classicSurfaceColor?.getRed(
                &surfaceRed,
                green: &surfaceGreen,
                blue: &surfaceBlue,
                alpha: &surfaceAlpha
            ) == true
        )
        XCTAssertTrue(
            classicAppearance.backgroundColor.getRed(
                &backgroundRed,
                green: &backgroundGreen,
                blue: &backgroundBlue,
                alpha: &backgroundAlpha
            )
        )
        XCTAssertGreaterThan(surfaceRed, backgroundRed)
        XCTAssertGreaterThan(surfaceGreen, backgroundGreen)
        XCTAssertGreaterThan(surfaceBlue, backgroundBlue)
        XCTAssertEqual(surfaceAlpha, 1, accuracy: 0.001)
    }

    func testExpandedAIThemeCardKeepsRadarSurfaceOpaque() {
        let cardView = ExpandedAIThemeCardView(
            frame: CGRect(x: 0, y: 0, width: 342, height: 640)
        )
        let radarAppearance = AppAppearance(
            designStyle: .radar,
            cleanColorSchemePreference: .dark,
            traitCollection: UITraitCollection(userInterfaceStyle: .dark)
        )

        cardView.configure(
            state: HomeAIThemeCardState(),
            appearance: radarAppearance
        )

        XCTAssertTrue(
            cardView.configuredSurfaceStyle?.backgroundColor.isEqual(
                radarAppearance.dialogSurface.backgroundColor
            ) == true
        )
        XCTAssertEqual(
            cardView.frontSurfaceView.backgroundColor?.cgColor.alpha ?? -1,
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            cardView.backSurfaceView.backgroundColor?.cgColor.alpha ?? -1,
            1,
            accuracy: 0.001
        )
    }

}

private final class HomeAIQuizAccessStub: AIQuizAccessProviding {
    let isAIQuizAvailable: Bool

    init(isAvailable: Bool) {
        isAIQuizAvailable = isAvailable
    }
}
