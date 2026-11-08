import UIKit
import XCTest
@testable import Quizice

@MainActor
final class HomeIPadLayoutTests: HomeScreenVisualStateTestCase {
    func testAccessibilityUsesOneColumnAndOuterScrolling() throws {
        QuizFactory.shared.themes = (0..<12).map { makeTheme(name: "Тема \($0)") }
        let controller = makeHomeViewController(in: CGRect(x: 0, y: 0, width: 1_194, height: 834))
        controller.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        let service = controller.themesCollectionService
        let catalog = try XCTUnwrap(service.catalogCollectionView)
        let grid = service.themeGrid(width: catalog.bounds.width, traits: catalog.traitCollection)
        XCTAssertEqual(grid.columnCount, 1)
        XCTAssertTrue(service.usesOuterScrolling)
        XCTAssertFalse(catalog.isScrollEnabled)
    }

    func testCatalogUsesWindowWidthAndKeepsActionsInSeparateCenteredRows() throws {
        QuizFactory.shared.themes = (0..<12).map { makeTheme(name: "Тема \($0)") }
        for (width, columns) in [(CGFloat(834), 3), (1_366, 4)] {
            let controller = makeHomeViewController(in: CGRect(x: 0, y: 0, width: width, height: 1_194))
            let outer = try XCTUnwrap(controller.themesCollectionView)
            let catalog = try XCTUnwrap(controller.themesCollectionService.catalogCollectionView)
            XCTAssertEqual(outer.bounds.width, min(width, 1_180), accuracy: 1)
            let grid = controller.themesCollectionService.themeGrid(width: catalog.bounds.width, traits: catalog.traitCollection)
            XCTAssertEqual(grid.columnCount, columns)
            let ai = try XCTUnwrap(controller.sourceAIThemeButton())
            let lucky = try XCTUnwrap(controller.view.descendant(withAccessibilityIdentifier: "homeFeelingLuckyButton"))
            XCTAssertLessThanOrEqual(ai.bounds.width, 640)
            XCTAssertEqual(ai.convert(ai.bounds, to: controller.view).midX, controller.view.bounds.midX, accuracy: 1)
            XCTAssertGreaterThan(lucky.convert(lucky.bounds, to: controller.view).minY, ai.convert(ai.bounds, to: controller.view).maxY)
        }
    }

    func testShortWindowUsesOneOuterScrollerAndCanReachStatistics() throws {
        QuizFactory.shared.themes = (0..<18).map { makeTheme(name: "Тема \($0)") }
        let controller = makeHomeViewController(in: CGRect(x: 0, y: 0, width: 900, height: 430))
        let outer = try XCTUnwrap(controller.themesCollectionView)
        let catalog = try XCTUnwrap(controller.themesCollectionService.catalogCollectionView)
        XCTAssertTrue(controller.themesCollectionService.usesOuterScrolling)
        XCTAssertTrue(outer.isScrollEnabled)
        XCTAssertFalse(catalog.isScrollEnabled)
        outer.scrollToItem(at: IndexPath(item: outer.numberOfItems(inSection: 0) - 1, section: 0), at: .bottom, animated: false)
        outer.layoutIfNeeded()
        let statistics = try XCTUnwrap(controller.sourceStatisticsButton())
        let frame = statistics.convert(statistics.bounds, to: outer)
        XCTAssertTrue(outer.bounds.intersects(frame))
    }

    func testResizeSettlesExpansionFlipAndCollapseAtRequestedState() throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка", questionCount: 15)]
        let controller = makeHomeViewController(in: CGRect(x: 0, y: 0, width: 834, height: 1_194))
        let button = try XCTUnwrap(controller.sourceButton(themeID: "music"))
        button.sendActions(for: .touchUpInside)
        resize(controller, to: CGSize(width: 1_194, height: 834))
        XCTAssertNil(controller.expandedCardAnimator)
        XCTAssertEqual(controller.homeCardState.phase, .expandedFront)
        XCTAssertEqual(controller.expandedThemeCardView?.bounds.width, 560)

        controller.sendHomeCardAction(.flipRequested)
        resize(controller, to: CGSize(width: 500, height: 834))
        XCTAssertEqual(controller.homeCardState.phase, .expandedBack)
        XCTAssertEqual(controller.expandedThemeCardView?.face, .back)
        XCTAssertEqual(controller.expandedThemeCardView?.bounds.width, 430)

        controller.requestExpandedCardClose()
        resize(controller, to: CGSize(width: 900, height: 600))
        XCTAssertEqual(controller.homeCardState.phase, .grid)
        XCTAssertNil(controller.expandedThemeCardView)
        XCTAssertTrue(controller.themesCollectionView.isUserInteractionEnabled)
    }

    func testResizePreservesAIPromptAndIgnoresFloatingKeyboardBesideCard() throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка")]
        let controller = makeHomeViewController(in: CGRect(x: 0, y: 0, width: 1_194, height: 834))
        try XCTUnwrap(controller.sourceAIThemeButton()).sendActions(for: .touchUpInside)
        drainAnimations()
        let card = try XCTUnwrap(controller.expandedAIThemeCardView)
        card.promptTextView.text = "Древний Рим"
        card.textViewDidChange(card.promptTextView)
        let frame = card.frame
        controller.updateExpandedAIThemeCardFrame(
            card,
            keyboardFrameInWindow: CGRect(x: 0, y: frame.midY, width: frame.minX - 10, height: 220),
            duration: 0, options: []
        )
        XCTAssertEqual(controller.expandedAIKeyboardLift, 0)
        XCTAssertEqual(card.frame, frame)

        let requestID = UUID()
        _ = controller.homeStore.sendAI(.submitRequested(requestID: requestID, locale: Locale(identifier: "ru"), now: Date()))
        let submissionTask = Task<Void, Never> { try? await Task.sleep(nanoseconds: 60_000_000_000) }
        controller.aiSubmissionTask = submissionTask
        defer { submissionTask.cancel() }
        resize(controller, to: CGSize(width: 834, height: 1_194))
        XCTAssertTrue(controller.expandedAIThemeCardView === card)
        XCTAssertEqual(card.promptTextView.text, "Древний Рим")
        XCTAssertEqual(controller.homeAIThemeCardState.prompt, "Древний Рим")
        XCTAssertEqual(controller.homeAIThemeCardState.activeSubmission?.id, requestID)
        XCTAssertFalse(submissionTask.isCancelled)
    }

    func testResizeCompletesReversedExpansionInBothMotionModes() throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка", questionCount: 15)]
        for reduceMotion in [false, true] {
            let controller = QuizViewController(cardReduceMotionProvider: { reduceMotion })
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 834, height: 1_194))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            testWindows.append(window)
            try XCTUnwrap(controller.sourceButton(themeID: "music")).sendActions(for: .touchUpInside)
            controller.requestExpandedCardClose()
            XCTAssertEqual(controller.homeCardState.phase, .collapsing)
            resize(controller, to: CGSize(width: 1_194, height: 834))
            XCTAssertEqual(controller.homeCardState.phase, .grid)
            XCTAssertNil(controller.expandedCardAnimator)
            XCTAssertNil(controller.expandedCardBackdropView)
        }
    }

    func testResizePreservesVisibleThemeAnchorAcrossScrollModes() throws {
        QuizFactory.shared.themes = (0..<60).map { makeTheme(name: "Тема \($0)") }
        let controller = makeHomeViewController(in: CGRect(x: 0, y: 0, width: 834, height: 1_194))
        let service = controller.themesCollectionService
        let catalog = try XCTUnwrap(service.catalogCollectionView)
        catalog.scrollToItem(at: IndexPath(item: 18, section: 0), at: .top, animated: false)
        catalog.layoutIfNeeded()
        service.captureScrollAnchor()
        let anchor = try XCTUnwrap(service.pendingScrollAnchor)
        resize(controller, to: CGSize(width: 900, height: 430))
        XCTAssertTrue(service.usesOuterScrolling)
        XCTAssertNil(service.pendingScrollAnchor)
        let theme = try XCTUnwrap(service.visibleThemeCells.first { $0.actionButton.accessibilityIdentifier == anchor.themeID },
                                 "Anchor \(anchor.themeID), catalog bounds \(catalog.bounds), outer offset \(controller.themesCollectionView.contentOffset)")
        let frame = theme.convert(theme.bounds, to: controller.themesCollectionView)
        let visibleTop = controller.themesCollectionView.contentOffset.y + controller.themesCollectionView.adjustedContentInset.top
        XCTAssertEqual(frame.minY - visibleTop, anchor.offsetFromTop, accuracy: 2)

        service.captureScrollAnchor()
        let returningAnchor = try XCTUnwrap(service.pendingScrollAnchor)
        resize(controller, to: CGSize(width: 834, height: 1_194))
        XCTAssertFalse(service.usesOuterScrolling)
        XCTAssertEqual(controller.themesCollectionView.contentOffset.y,
                       -controller.themesCollectionView.adjustedContentInset.top, accuracy: 1)
        let restoredTheme = try XCTUnwrap(service.visibleThemeCells.first {
            $0.actionButton.accessibilityIdentifier == returningAnchor.themeID
        })
        XCTAssertEqual(restoredTheme.frame.minY - catalog.contentOffset.y, returningAnchor.offsetFromTop, accuracy: 2)
    }

    private func resize(_ controller: QuizViewController, to size: CGSize) {
        controller.view.window?.frame.size = size
        controller.view.frame.size = size
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
    }
}
