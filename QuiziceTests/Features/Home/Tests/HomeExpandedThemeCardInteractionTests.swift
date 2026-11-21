import SwiftUI
import XCTest
@testable import Quizice

@MainActor
final class HomeExpandedThemeCardInteractionTests: HomeScreenVisualStateTestCase {
    func testMusicGenrePickerIsOnBackendMusicBackAndPreservesSelection() throws {
        let card = makeHostedExpandedThemeCard(motionProvider: HomeThemeCardMotionProviderFake())
        let music = makeTheme(name: "Музыка", questionCount: 5)
        music.id = MusicGenre.themeID
        music.questionOrigin = .backend
        let rock = MusicGenre(id: "rock", name: "Рок")
        card.musicGenresProvider = { [rock] }
        let appearance = SnapshotSupport.appearance(designStyle: .clean)
        card.configure(theme: music, appearance: appearance, availableQuestionCounts: [5], selectedQuestionCount: 5)
        card.setFace(.back, animated: false)

        let picker = card.questionFilterButton
        XCTAssertFalse(picker.isHidden)
        XCTAssertTrue(picker.isDescendant(of: card.backFaceView))
        XCTAssertEqual(picker.accessibilityIdentifier, "descriptionGenrePicker")
        XCTAssertEqual(picker.accessibilityValue, L10n.ThemeCard.mixedGenres)
        XCTAssertTrue(picker.menu?.children.contains { $0 is UIDeferredMenuElement } == true)

        card.selectMusicGenre(rock)
        card.configure(theme: music, appearance: appearance, availableQuestionCounts: [5], selectedQuestionCount: 5)
        XCTAssertEqual(card.selectedMusicGenre, rock)
        XCTAssertEqual(picker.accessibilityValue, rock.name)
        card.setStartLoading(true)
        card.selectMusicGenre(nil)
        XCTAssertEqual(card.selectedMusicGenre, rock)
        XCTAssertFalse(picker.isEnabled)

        music.questionOrigin = .bundled
        card.configure(theme: music, appearance: appearance, availableQuestionCounts: [5], selectedQuestionCount: 5)
        XCTAssertTrue(picker.isHidden)
        XCTAssertNil(card.selectedMusicGenre)
    }

    func testCountryButtonPreservesTitleAndSurfaceAcrossSelectionAndAppearanceUpdates() throws {
        let card = makeHostedExpandedThemeCard(motionProvider: HomeThemeCardMotionProviderFake())
        let theme = makeTheme(name: "Политика и бизнес", questionCount: 5)
        theme.id = "politics_business"
        theme.countries = ["IT", "ES", "DE"]
        let button = card.questionFilterButton

        for style: AppDesignStyle in [.classic, .clean, .radar] {
            let appearance = SnapshotSupport.appearance(designStyle: style)
            card.configure(theme: theme, appearance: appearance, availableQuestionCounts: [5],
                           selectedQuestionCount: 5, selectedCountry: "IT")
            card.setFace(.back, animated: false)
            card.layoutIfNeeded()
            XCTAssertTrue(card.backFaceView.accessibilityElements?.contains { ($0 as? UIButton) === button } == true)

            for country in ["ES", "DE"] {
                card.selectCountry(country)
                let title = try XCTUnwrap(AppLocalizationStore.shared.resolvedLocale.localizedString(forRegionCode: country))
                for highlighted in [true, false] {
                    button.isHighlighted = highlighted
                    button.setNeedsUpdateConfiguration()
                    button.layoutIfNeeded()
                    XCTAssertEqual(button.titleLabel?.text, "\(title) ▾")
                    XCTAssertEqual(button.accessibilityValue, title)
                    let background = try XCTUnwrap(button.configuration?.background)
                    assertColor(background.backgroundColor, equals: appearance.row.backgroundColor)
                    assertColor(background.strokeColor, equals: appearance.row.borderColor)
                    XCTAssertEqual(background.cornerRadius, appearance.row.cornerRadius)
                    XCTAssertEqual(background.strokeWidth, appearance.row.borderWidth)
                    // UIKit can clear the outer layer during its menu morph.
                    // The border must belong to the configured background.
                    XCTAssertEqual(button.layer.borderWidth, 0)
                }
            }
        }
    }

    func testExpandedThemeReduceMotionBlocksProviderAndDragThenRuntimeToggleNeutralizesPose() throws {
        var reduceMotion = true
        let motionProvider = HomeThemeCardMotionProviderFake()
        let card = makeHostedExpandedThemeCard(
            motionProvider: motionProvider,
            reduceMotionProvider: { reduceMotion }
        )
        let parallaxCarrier = try XCTUnwrap(
            card.descendant(withAccessibilityIdentifier: "expandedThemeCardParallaxCarrier")
        )
        let frontImage = try XCTUnwrap(
            card.descendant(withAccessibilityIdentifier: "expandedThemeCardFrontImageView")
        )
        let parallaxPan = try XCTUnwrap(
            parallaxPanGestureRecognizer(in: card)
        )

        card.setParallaxPresentationPhase(.front)

        XCTAssertEqual(motionProvider.startCallCount, 0)
        XCTAssertFalse(parallaxPan.isEnabled)
        card.handleFrontParallaxPan(state: .began, translation: .zero, velocity: .zero)
        card.handleFrontParallaxPan(
            state: .changed,
            translation: CGPoint(x: 100, y: 100),
            velocity: .zero
        )
        XCTAssertTrue(CATransform3DIsIdentity(parallaxCarrier.layer.transform))
        XCTAssertTrue(frontImage.transform.isIdentity)

        reduceMotion = false
        NotificationCenter.default.post(
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )
        XCTAssertEqual(motionProvider.startCallCount, 1)
        XCTAssertTrue(parallaxPan.isEnabled)

        motionProvider.send(HomeThemeCardParallaxInput(x: 0.8, y: -0.6))
        XCTAssertFalse(CATransform3DIsIdentity(parallaxCarrier.layer.transform))
        XCTAssertTrue(frontImage.transform.isIdentity)

        reduceMotion = true
        NotificationCenter.default.post(
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )
        XCTAssertEqual(motionProvider.stopCallCount, 1)
        XCTAssertFalse(parallaxPan.isEnabled)
        XCTAssertTrue(CATransform3DIsIdentity(parallaxCarrier.layer.transform))
        XCTAssertTrue(frontImage.transform.isIdentity)

        card.handleFrontParallaxPan(state: .began, translation: .zero, velocity: .zero)
        card.handleFrontParallaxPan(
            state: .changed,
            translation: CGPoint(x: -100, y: -100),
            velocity: .zero
        )
        XCTAssertTrue(CATransform3DIsIdentity(parallaxCarrier.layer.transform))
        XCTAssertTrue(frontImage.transform.isIdentity)
    }

    func testExpandedThemeFlipUsesOneTransformCarrierForBothPlanes() throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка", questionCount: 15)]

        let viewController = makeHomeViewController(in: CGRect(x: 0, y: 0, width: 390, height: 844))
        let sourceButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "music") as? UIButton
        )
        sourceButton.sendActions(for: .touchUpInside)
        drainAnimations()

        let card = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedThemeCard")
        )
        let rotatingCarrier = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardRotatingCarrier")
        )
        let shadowProxy = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardShadowProxy")
        )
        let frontPlane = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardFrontPlane")
        )
        let backPlane = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardBackPlane")
        )
        let perspectiveStage = try XCTUnwrap(rotatingCarrier.superview)
        let front = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardFrontView")
        )
        let back = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardBackView")
        )
        let infoButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardInfoButton") as? UIButton
        )

        XCTAssertTrue(frontPlane.superview === rotatingCarrier)
        XCTAssertTrue(backPlane.superview === rotatingCarrier)
        XCTAssertTrue(frontPlane.isDescendant(of: rotatingCarrier))
        XCTAssertTrue(backPlane.isDescendant(of: rotatingCarrier))
        XCTAssertTrue(rotatingCarrier.layer is CATransformLayer)
        XCTAssertTrue(shadowProxy.superview === perspectiveStage)
        XCTAssertNotNil(shadowProxy.layer.shadowPath)
        XCTAssertFalse(frontPlane.layer.isDoubleSided)
        XCTAssertFalse(backPlane.layer.isDoubleSided)
        XCTAssertTrue(CATransform3DIsIdentity(rotatingCarrier.layer.transform))
        XCTAssertTrue(CATransform3DIsIdentity(frontPlane.layer.transform))
        XCTAssertFalse(CATransform3DIsIdentity(backPlane.layer.transform))
        XCTAssertFalse(front.accessibilityElementsHidden)
        XCTAssertTrue(back.accessibilityElementsHidden)

        infoButton.sendActions(for: .touchUpInside)

        XCTAssertTrue(CATransform3DIsIdentity(card.layer.transform))
        XCTAssertFalse(CATransform3DIsIdentity(rotatingCarrier.layer.transform))
        XCTAssertFalse(CATransform3DIsIdentity(shadowProxy.layer.transform))
        XCTAssertTrue(CATransform3DIsIdentity(frontPlane.layer.transform))
        XCTAssertFalse(CATransform3DIsIdentity(backPlane.layer.transform))
        XCTAssertLessThan(perspectiveStage.layer.sublayerTransform.m34, 0)
        XCTAssertTrue(CATransform3DIsIdentity(front.layer.transform))
        XCTAssertTrue(CATransform3DIsIdentity(back.layer.transform))
        XCTAssertFalse(front.accessibilityElementsHidden)
        XCTAssertTrue(back.accessibilityElementsHidden)

        drainAnimations(0.34)
        XCTAssertTrue(CATransform3DIsIdentity(card.layer.transform))
        XCTAssertFalse(CATransform3DIsIdentity(rotatingCarrier.layer.transform))
        XCTAssertTrue(CATransform3DIsIdentity(frontPlane.layer.transform))
        XCTAssertFalse(CATransform3DIsIdentity(backPlane.layer.transform))
        XCTAssertTrue(frontPlane.isHidden)
        XCTAssertFalse(backPlane.isHidden)
        XCTAssertTrue(front.isHidden)
        XCTAssertFalse(back.isHidden)
        XCTAssertTrue(front.accessibilityElementsHidden)
        XCTAssertFalse(back.accessibilityElementsHidden)

        let backButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "descriptionBackButton") as? UIButton
        )
        backButton.sendActions(for: .touchUpInside)

        XCTAssertTrue(CATransform3DIsIdentity(card.layer.transform))
        XCTAssertTrue(CATransform3DIsIdentity(rotatingCarrier.layer.transform))
        XCTAssertTrue(CATransform3DIsIdentity(frontPlane.layer.transform))
        XCTAssertFalse(CATransform3DIsIdentity(backPlane.layer.transform))
        XCTAssertLessThan(perspectiveStage.layer.sublayerTransform.m34, 0)
        XCTAssertTrue(CATransform3DIsIdentity(front.layer.transform))
        XCTAssertTrue(CATransform3DIsIdentity(back.layer.transform))
        XCTAssertTrue(front.accessibilityElementsHidden)
        XCTAssertFalse(back.accessibilityElementsHidden)

        drainAnimations(0.34)
        XCTAssertTrue(CATransform3DIsIdentity(card.layer.transform))
        XCTAssertTrue(CATransform3DIsIdentity(rotatingCarrier.layer.transform))
        XCTAssertTrue(CATransform3DIsIdentity(frontPlane.layer.transform))
        XCTAssertFalse(CATransform3DIsIdentity(backPlane.layer.transform))
        XCTAssertFalse(frontPlane.isHidden)
        XCTAssertTrue(backPlane.isHidden)
        XCTAssertFalse(front.isHidden)
        XCTAssertTrue(back.isHidden)
        XCTAssertFalse(front.accessibilityElementsHidden)
        XCTAssertTrue(back.accessibilityElementsHidden)
    }

    func testExpandedThemeFlipReversesInFlightWithoutIgnoringRapidTaps() throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка", questionCount: 15)]

        let viewController = makeHomeViewController(in: CGRect(x: 0, y: 0, width: 390, height: 844))
        let sourceButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "music") as? UIButton
        )
        sourceButton.sendActions(for: .touchUpInside)
        drainAnimations()

        let front = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardFrontView")
        )
        let back = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardBackView")
        )
        let infoButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardInfoButton") as? UIButton
        )
        let interactionOverlay = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardFlipInteractionOverlay") as? UIButton
        )

        infoButton.sendActions(for: .touchUpInside)
        XCTAssertFalse(interactionOverlay.isHidden)
        interactionOverlay.sendActions(for: .touchUpInside)
        drainAnimations(0.34)
        XCTAssertFalse(front.isHidden)
        XCTAssertTrue(back.isHidden)

        infoButton.sendActions(for: .touchUpInside)
        interactionOverlay.sendActions(for: .touchUpInside)
        interactionOverlay.sendActions(for: .touchUpInside)
        drainAnimations(0.34)
        XCTAssertTrue(front.isHidden)
        XCTAssertFalse(back.isHidden)
    }

    func testExpandedThemeSurfaceTapsUseFaceActionsWithoutStealingControls() throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка", questionCount: 15)]

        let viewController = makeHomeViewController(in: CGRect(x: 0, y: 0, width: 390, height: 844))
        let sourceButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "music") as? UIButton
        )
        sourceButton.sendActions(for: .touchUpInside)
        drainAnimations()

        let card = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedThemeCard")
        )
        let frontSurfaceButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardFrontSurfaceButton") as? UIButton
        )
        let infoButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardInfoButton") as? UIButton
        )
        let closeButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardCloseButton") as? UIButton
        )
        let titleDepthView = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "expandedThemeCardFrontTitleDepth"
            )
        )

        XCTAssertTrue(card.hitTest(CGPoint(x: card.bounds.midX, y: card.bounds.midY), with: nil) === frontSurfaceButton)
        let titleCenter = titleDepthView.convert(
            CGPoint(x: titleDepthView.bounds.midX, y: titleDepthView.bounds.midY),
            to: card
        )
        XCTAssertTrue(card.hitTest(titleCenter, with: nil) === frontSurfaceButton)
        XCTAssertTrue(hitView(in: card, for: infoButton)?.isDescendant(of: infoButton) == true)
        XCTAssertTrue(hitView(in: card, for: closeButton)?.isDescendant(of: closeButton) == true)

        infoButton.sendActions(for: .touchUpInside)
        drainAnimations(0.34)

        let backSurfaceButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardBackSurfaceButton") as? UIButton
        )
        let backButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "descriptionBackButton") as? UIButton
        )
        let questionCountControl = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "descriptionQuestionCountPicker") as? UISegmentedControl
        )
        let startButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "descriptionStartButton") as? UIButton
        )
        let descriptionScrollView = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "descriptionScrollView") as? UIScrollView
        )
        let backFaceView = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardBackView")
        )
        let backTapGestureRecognizer = try XCTUnwrap(
            backFaceView.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }.first
        )

        XCTAssertTrue(
            card.hitTest(CGPoint(x: card.bounds.maxX - 8, y: card.bounds.midY), with: nil) === backSurfaceButton
        )
        XCTAssertTrue(hitView(in: card, for: backButton)?.isDescendant(of: backButton) == true)
        XCTAssertTrue(hitView(in: card, for: questionCountControl)?.isDescendant(of: questionCountControl) == true)
        XCTAssertTrue(hitView(in: card, for: startButton)?.isDescendant(of: startButton) == true)
        XCTAssertFalse(
            try XCTUnwrap(card as? ExpandedThemeCardView).gestureRecognizer(
                backTapGestureRecognizer,
                shouldRecognizeSimultaneouslyWith: descriptionScrollView.panGestureRecognizer
            )
        )

        backSurfaceButton.sendActions(for: .touchUpInside)
        drainAnimations(0.34)
        XCTAssertFalse(
            try XCTUnwrap(
                viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardFrontView")
            ).isHidden
        )

        frontSurfaceButton.sendActions(for: .touchUpInside)
        drainAnimations(0.34)
        XCTAssertFalse(
            try XCTUnwrap(
                viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardBackView")
            ).isHidden
        )

        let backdropDismissButton = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeExpandedThemeCardBackdropDismissButton"
            ) as? UIButton
        )
        let outsidePoint = CGPoint(x: 4, y: 4)
        let outsideHitView = try XCTUnwrap(viewController.view.hitTest(outsidePoint, with: nil))
        XCTAssertTrue(
            outsideHitView === backdropDismissButton || outsideHitView.isDescendant(of: backdropDismissButton),
            "Expected the backdrop dismiss button, hit \(type(of: outsideHitView)) " +
                "with id \(outsideHitView.accessibilityIdentifier ?? "nil")"
        )
        backdropDismissButton.sendActions(for: .touchUpInside)
        drainAnimations()
        XCTAssertNil(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedThemeCardBackdrop")
        )
    }

    func testExpandedThemeBackSelectsCountAndStartsOnlyOnce() async throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка", questionCount: 15)]

        let viewController = makeHomeViewController(in: CGRect(x: 0, y: 0, width: 390, height: 844))
        let router = HomeRouterSpy()
        viewController.router = router
        let sourceButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "music") as? UIButton
        )
        sourceButton.sendActions(for: .touchUpInside)
        try await waitUntil { viewController.homeCardState.phase == .expandedFront }

        let infoButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardInfoButton") as? UIButton
        )
        infoButton.sendActions(for: .touchUpInside)
        try await waitUntil { viewController.homeCardState.phase == .expandedBack }

        let questionCountControl = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "descriptionQuestionCountPicker") as? UISegmentedControl
        )
        questionCountControl.selectedSegmentIndex = 1
        questionCountControl.sendActions(for: .valueChanged)
        let startButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "descriptionStartButton") as? UIButton
        )
        let activityIndicator = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "descriptionStartActivityIndicator")
                as? UIActivityIndicatorView
        )

        startButton.sendActions(for: .touchUpInside)
        startButton.sendActions(for: .touchUpInside)
        try await waitUntil { router.showQuestionCallCount == 1 }
        try await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertEqual(QuizFactory.shared.questionsCount, 10)
        XCTAssertEqual(router.showQuestionCallCount, 1)
        XCTAssertFalse(activityIndicator.isAnimating)

        viewController.viewWillAppear(false)
        XCTAssertNil(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedThemeCardBackdrop")
        )
        XCTAssertNil(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedThemeCard")
        )
        XCTAssertFalse(
            try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "music") as? UIButton).isHidden
        )
    }

    func testExpandedThemeAnalyticsTracksCancellationAndSelectedCountStart() async throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка", questionCount: 15)]
        let analytics = HomeAnalyticsTrackingSpy()
        let viewController = QuizViewController(
            analytics: analytics,
            cardReduceMotionProvider: { true }
        )
        let router = HomeRouterSpy()
        viewController.router = router
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        testWindows.append(window)
        drainAnimations(0.01)
        analytics.reset()

        var sourceButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "music") as? UIButton
        )
        sourceButton.sendActions(for: .touchUpInside)
        try await waitUntil { viewController.homeCardState.phase == .expandedFront }
        let closeButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardCloseButton") as? UIButton
        )
        closeButton.sendActions(for: .touchUpInside)
        let eventsBeforeCollapseCompletion = analytics.events.filter { event in
            !(event.name == "screen_view" && event.parameters["screen"] as? String == "home")
        }
        XCTAssertEqual(eventsBeforeCollapseCompletion.map(\.name), ["theme_selected"])
        try await waitUntil { viewController.homeCardState.phase == .grid }

        let cancellationEvents = analytics.events.filter { event in
            !(event.name == "screen_view" && event.parameters["screen"] as? String == "home")
        }
        XCTAssertEqual(
            cancellationEvents.map(\.name),
            ["theme_selected", "quiz_setup_cancelled"]
        )
        guard cancellationEvents.count == 2 else { return }
        XCTAssertEqual(cancellationEvents[0].parameters["selection_method"] as? String, "manual")
        XCTAssertEqual(cancellationEvents[0].parameters["theme_id"] as? String, "music")
        XCTAssertEqual(cancellationEvents[1].parameters["theme_id"] as? String, "music")
        XCTAssertFalse(
            cancellationEvents.contains {
                $0.name == "screen_view" && $0.parameters["screen"] as? String == "quiz_description"
            }
        )

        analytics.reset()
        sourceButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "music") as? UIButton
        )
        sourceButton.sendActions(for: .touchUpInside)
        try await waitUntil { viewController.homeCardState.phase == .expandedFront }
        let infoButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardInfoButton") as? UIButton
        )
        infoButton.sendActions(for: .touchUpInside)
        try await waitUntil { viewController.homeCardState.phase == .expandedBack }
        let questionCountControl = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "descriptionQuestionCountPicker") as? UISegmentedControl
        )
        questionCountControl.selectedSegmentIndex = 1
        questionCountControl.sendActions(for: .valueChanged)
        let startButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "descriptionStartButton") as? UIButton
        )
        startButton.sendActions(for: .touchUpInside)
        try await waitUntil { router.showQuestionCallCount == 1 }

        let startEvents = analytics.events.filter { event in
            !(event.name == "screen_view" && event.parameters["screen"] as? String == "home")
        }
        XCTAssertEqual(
            startEvents.map(\.name),
            ["theme_selected", "theme_card_flipped", "screen_view"]
        )
        guard startEvents.count == 3 else { return }
        XCTAssertEqual(startEvents[0].parameters["selection_method"] as? String, "manual")
        XCTAssertEqual(startEvents[1].parameters["visible_face"] as? String, "back")
        XCTAssertEqual(startEvents[1].parameters["theme_id"] as? String, "music")
        XCTAssertEqual(startEvents[2].parameters["screen"] as? String, "quiz_description")
        XCTAssertEqual(router.showQuestionCallCount, 1)
    }

}
