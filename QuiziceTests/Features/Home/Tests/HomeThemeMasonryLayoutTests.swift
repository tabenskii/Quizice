import UIKit
import XCTest
@testable import Quizice

@MainActor
final class HomeThemeMasonryLayoutTests: HomeScreenVisualStateTestCase {
    func testGeometryPlacesCardsInTheShortestColumnWithoutStretchingNeighbors() {
        let geometry = HomeThemeMasonryGeometry(
            itemHeights: [64, 180, 90, 64, 80], columnCount: 2,
            cardWidth: 155, spacing: 16, width: 326
        )

        XCTAssertEqual(geometry.frames, [
            CGRect(x: 0, y: 0, width: 155, height: 64),
            CGRect(x: 171, y: 0, width: 155, height: 180),
            CGRect(x: 0, y: 80, width: 155, height: 90),
            CGRect(x: 0, y: 186, width: 155, height: 64),
            CGRect(x: 171, y: 196, width: 155, height: 80)
        ])
        XCTAssertEqual(geometry.contentSize, CGSize(width: 326, height: 276))
        assertFramesDoNotOverlap(geometry.frames)
    }

    func testEmptyAndOddCatalogsDoNotReserveAnExtraRowOrTrailingSpacing() {
        let empty = HomeThemeMasonryGeometry(
            itemHeights: [], columnCount: 2, cardWidth: 155, spacing: 16, width: 326
        )
        XCTAssertTrue(empty.frames.isEmpty)
        XCTAssertEqual(empty.contentSize.height, 0)

        let odd = HomeThemeMasonryGeometry(
            itemHeights: [64, 64, 100], columnCount: 2,
            cardWidth: 155, spacing: 16, width: 326
        )
        XCTAssertEqual(odd.frames.count, 3)
        XCTAssertEqual(odd.frames.last, CGRect(x: 0, y: 80, width: 155, height: 100))
        XCTAssertEqual(odd.contentSize.height, 180)
    }

    func testSingleColumnGeometryKeepsEveryCardsOwnHeightAndCatalogOrder() {
        let geometry = HomeThemeMasonryGeometry(
            itemHeights: [90, 180, 64], columnCount: 1,
            cardWidth: 327, spacing: 16, width: 327
        )

        XCTAssertEqual(geometry.frames, [
            CGRect(x: 0, y: 0, width: 327, height: 90),
            CGRect(x: 0, y: 106, width: 327, height: 180),
            CGRect(x: 0, y: 302, width: 327, height: 64)
        ])
        XCTAssertEqual(geometry.contentSize, CGSize(width: 327, height: 366))
    }

    func testCatalogUsesIndependentHeightsAndFillsSpaceBelowTheShortCard() throws {
        let catalog = try makeCatalog(names: [
            "Музыка", "История Древнего Рима и Древнего мира", "Кино", "Игры"
        ])
        let collectionView = catalog.cell.themesCollectionView
        XCTAssertTrue(collectionView.collectionViewLayout is HomeThemeMasonryLayout)
        let frames = try itemFrames(in: collectionView)

        XCTAssertEqual(frames[0].height, ThemeCardLayoutMetrics.singleLineHeight)
        XCTAssertGreaterThan(frames[1].height, frames[0].height)
        XCTAssertEqual(frames[2].height, frames[0].height)
        XCTAssertEqual(frames[2].minX, frames[0].minX)
        XCTAssertEqual(frames[1].maxX, collectionView.bounds.width, accuracy: 0.01)
        XCTAssertEqual(frames[2].minY, frames[0].maxY + 16)
        XCTAssertLessThan(frames[2].minY, frames[1].maxY + 16)
        XCTAssertEqual(collectionView.contentSize.height, frames.map(\.maxY).max())
        assertFramesDoNotOverlap(frames)
        withExtendedLifetime(catalog) {}
    }

    func testLayoutReturnsEveryIntersectingCardIncludingATallCardStartingAboveTheRect() throws {
        let catalog = try makeCatalog(names: [
            "Музыка", String(repeating: "Древний мир ", count: 8), "Кино", "Игры", "Спорт"
        ])
        let collectionView = catalog.cell.themesCollectionView
        let frames = try itemFrames(in: collectionView)
        let rect = CGRect(x: 0, y: frames[2].minY + 1, width: collectionView.bounds.width, height: 8)
        let attributes = try XCTUnwrap(
            collectionView.collectionViewLayout.layoutAttributesForElements(in: rect)
        )
        let expected = frames.enumerated().compactMap { index, frame in
            frame.intersects(rect) ? IndexPath(item: index, section: 0) : nil
        }

        XCTAssertEqual(Set(attributes.map(\.indexPath)), Set(expected))
        XCTAssertTrue(attributes.contains { $0.indexPath.item == 1 })
        XCTAssertTrue(attributes.contains { $0.indexPath.item == 2 })
        withExtendedLifetime(catalog) {}
    }

    func testReloadReplacesFramesWhenTitlesAndItemCountChange() throws {
        let catalog = try makeCatalog(names: [
            "Музыка", String(repeating: "Древний мир ", count: 8), "Кино", "Игры", "Спорт"
        ])
        let collectionView = catalog.cell.themesCollectionView
        let oldHeight = collectionView.contentSize.height

        QuizFactory.shared.themes = [makeTheme(name: "Кино"), makeTheme(name: "Игры")]
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        let frames = try itemFrames(in: collectionView)

        XCTAssertEqual(frames.count, 2)
        XCTAssertTrue(frames.allSatisfy { $0.height == ThemeCardLayoutMetrics.singleLineHeight })
        XCTAssertEqual(collectionView.contentSize.height, ThemeCardLayoutMetrics.singleLineHeight)
        XCTAssertLessThan(collectionView.contentSize.height, oldHeight)
        let attributes = collectionView.collectionViewLayout.layoutAttributesForElements(
            in: CGRect(x: 0, y: 0, width: 327, height: oldHeight)
        ) ?? []
        XCTAssertEqual(Set(attributes.map(\.indexPath)), Set([
            IndexPath(item: 0, section: 0), IndexPath(item: 1, section: 0)
        ]))
        withExtendedLifetime(catalog) {}
    }

    func testWidthChangeRecalculatesEveryFrameAndContentSize() throws {
        let catalog = try makeCatalog(names: [
            "Музыка", "История Древнего Рима и Древнего мира", "Кино", "Игры", "Спорт"
        ])
        let collectionView = catalog.cell.themesCollectionView
        let originalFrames = try itemFrames(in: collectionView)

        catalog.cell.frame.size.width = 272
        catalog.cell.contentView.frame = catalog.cell.bounds
        catalog.cell.setNeedsLayout()
        catalog.cell.layoutIfNeeded()
        catalog.cell.contentView.layoutIfNeeded()
        collectionView.layoutIfNeeded()
        let resizedFrames = try itemFrames(in: collectionView)

        XCTAssertEqual(collectionView.bounds.width, 272, accuracy: 0.5)
        XCTAssertLessThan(resizedFrames[0].width, originalFrames[0].width)
        XCTAssertNotEqual(resizedFrames[1].minX, originalFrames[1].minX)
        XCTAssertTrue(resizedFrames.allSatisfy { $0.minX >= 0 && $0.maxX <= 272 })
        XCTAssertEqual(collectionView.contentSize.width, 272, accuracy: 0.5)
        XCTAssertEqual(collectionView.contentSize.height, resizedFrames.map(\.maxY).max())
        assertFramesDoNotOverlap(resizedFrames)
        withExtendedLifetime(catalog) {}
    }

    func testAccessibilityCatalogUsesOneColumnWithUnclippedIndependentHeights() throws {
        let catalog = try makeCatalog(
            names: ["Музыка", "История Древнего Рима и Древнего мира", "Кино"],
            category: .accessibilityExtraExtraExtraLarge
        )
        let collectionView = catalog.cell.themesCollectionView
        let frames = try itemFrames(in: collectionView)

        XCTAssertTrue(collectionView.traitCollection.preferredContentSizeCategory.isAccessibilityCategory)
        XCTAssertTrue(frames.allSatisfy { $0.minX == 0 && $0.width == collectionView.bounds.width })
        XCTAssertEqual(frames[1].minY, frames[0].maxY + 16)
        XCTAssertEqual(frames[2].minY, frames[1].maxY + 16)
        XCTAssertGreaterThan(frames[1].height, frames[0].height)
        XCTAssertEqual(collectionView.contentSize.height, frames[2].maxY)
        withExtendedLifetime(catalog) {}
    }

    func testOverflowEnablesScrollingAndMoreThemesEvenForASmallCatalog() throws {
        let catalog = try makeCatalog(
            names: ["Музыка", "Кино", String(repeating: "Древний мир ", count: 14), "Игры", "Спорт"],
            outerHeight: 440
        )
        let collectionView = catalog.cell.themesCollectionView
        let moreThemes = try XCTUnwrap(catalog.cell.contentView.descendant(
            withAccessibilityIdentifier: ThemesCollectionService.Content.moreThemesAccessibilityID
        ))

        XCTAssertGreaterThan(collectionView.contentSize.height, collectionView.bounds.height)
        XCTAssertTrue(collectionView.isScrollEnabled)
        XCTAssertTrue(collectionView.alwaysBounceVertical)
        XCTAssertTrue(collectionView.bounces)
        XCTAssertFalse(moreThemes.isHidden)
        XCTAssertGreaterThan(moreThemes.alpha, 0)
        withExtendedLifetime(catalog) {}
    }

    func testCatalogThatFitsDoesNotScrollOrShowMoreThemes() throws {
        let catalog = try makeCatalog(names: ["Музыка", "Кино", "Игры"])
        let collectionView = catalog.cell.themesCollectionView
        let moreThemes = try XCTUnwrap(
            catalog.cell.contentView.subviews.compactMap { $0 as? MoreThemesFadeButton }.first
        )

        XCTAssertLessThanOrEqual(collectionView.contentSize.height, collectionView.bounds.height)
        XCTAssertFalse(collectionView.isScrollEnabled)
        XCTAssertFalse(collectionView.alwaysBounceVertical)
        XCTAssertFalse(collectionView.bounces)
        XCTAssertTrue(moreThemes.isHidden)
        withExtendedLifetime(catalog) {}
    }

    func testReachingBottomHidesMoreThemesAndFadeWithOnlyThreePointsOfOverflow() throws {
        let catalog = try makeCatalog(names: (0..<14).map { "Тема \($0)" })
        let collectionView = catalog.cell.themesCollectionView
        let moreThemes = try XCTUnwrap(catalog.cell.contentView.descendant(
            withAccessibilityIdentifier: ThemesCollectionService.Content.moreThemesAccessibilityID
        ))
        catalog.cell.frame.size.height = collectionView.contentSize.height - 3
        catalog.cell.contentView.frame = catalog.cell.bounds
        catalog.cell.setNeedsLayout()
        catalog.cell.layoutIfNeeded()
        catalog.cell.contentView.layoutIfNeeded()
        collectionView.layoutIfNeeded()
        collectionView.contentOffset = .zero
        catalog.service.scrollViewDidScroll(collectionView)
        drainAnimations(0.25)

        XCTAssertEqual(collectionView.contentSize.height - collectionView.bounds.height, 3, accuracy: 0.5)
        XCTAssertFalse(moreThemes.isHidden)

        collectionView.contentOffset.y = 3
        catalog.service.scrollViewDidScroll(collectionView)
        drainAnimations(0.25)

        XCTAssertTrue(moreThemes.isHidden)
        let fadeColors = try XCTUnwrap((collectionView.layer.mask as? CAGradientLayer)?.colors as? [CGColor])
        XCTAssertEqual(try XCTUnwrap(fadeColors.last).alpha, 1, accuracy: 0.001)
        withExtendedLifetime(catalog) {}
    }

    func testMoreThemesAccessibilityActionPagesThroughUnequalCards() async throws {
        let names = (0..<16).map { index in
            index.isMultiple(of: 3) ? "Тема \(index) про Древний Рим и мир" : "Тема \(index)"
        }
        let catalog = try makeCatalog(names: names)
        let collectionView = catalog.cell.themesCollectionView
        let moreThemes = try XCTUnwrap(
            catalog.cell.contentView.subviews.compactMap { $0 as? MoreThemesFadeButton }.first
        )
        let expectedOffset = collectionView.bounds.height - ThemesCollectionService.Layout.moreThemesButtonHeight
        let maximumOffset = collectionView.contentSize.height - collectionView.bounds.height
        XCTAssertGreaterThan(expectedOffset, ThemeCardLayoutMetrics.singleLineHeight)
        XCTAssertGreaterThan(maximumOffset, expectedOffset)

        XCTAssertTrue(moreThemes.accessibilityActivate())
        try await waitUntil {
            abs(collectionView.contentOffset.y - expectedOffset) < 0.5 && moreThemes.isHidden
        }

        XCTAssertEqual(collectionView.contentOffset.y, expectedOffset, accuracy: 0.5)
        XCTAssertLessThan(collectionView.contentOffset.y, maximumOffset)
        XCTAssertFalse(moreThemes.accessibilityActivate(), "A hidden hint must not trigger a second page")
        withExtendedLifetime(catalog) {}
    }

    func testMoreThemesAccessibilityActionStopsAtTheBottomForTinyOverflow() async throws {
        let catalog = try makeCatalog(names: (0..<14).map { "Тема \($0)" })
        let collectionView = catalog.cell.themesCollectionView
        let moreThemes = try XCTUnwrap(
            catalog.cell.contentView.subviews.compactMap { $0 as? MoreThemesFadeButton }.first
        )
        catalog.cell.frame.size.height = collectionView.contentSize.height - 3
        catalog.cell.contentView.frame = catalog.cell.bounds
        catalog.cell.setNeedsLayout()
        catalog.cell.layoutIfNeeded()
        catalog.cell.contentView.layoutIfNeeded()
        collectionView.layoutIfNeeded()
        catalog.service.scrollViewDidScroll(collectionView)
        XCTAssertEqual(collectionView.contentSize.height - collectionView.bounds.height, 3, accuracy: 0.5)

        XCTAssertTrue(moreThemes.accessibilityActivate())
        try await waitUntil {
            abs(collectionView.contentOffset.y - 3) < 0.5 && moreThemes.isHidden
        }

        XCTAssertEqual(collectionView.contentOffset.y, 3, accuracy: 0.5)
        XCTAssertFalse(moreThemes.accessibilityActivate())
        withExtendedLifetime(catalog) {}
    }

    func testRevealingOffscreenThemePreservesSelectionAndItsTransitionGeometry() throws {
        let targetTitle = "История Древнего Рима и Древнего мира"
        let names = (0..<13).map { "Тема \($0)" } + [targetTitle]
        let catalog = try makeCatalog(names: names)
        let collectionView = catalog.cell.themesCollectionView
        let delegate = ThemeCollectionDelegateSpy()
        catalog.service.delegate = delegate
        let targetIndexPath = IndexPath(item: names.count - 1, section: 0)
        let targetFrame = try XCTUnwrap(collectionView.collectionViewLayout.layoutAttributesForItem(
            at: targetIndexPath
        )).frame
        XCTAssertFalse(targetFrame.intersects(collectionView.bounds))
        XCTAssertGreaterThan(targetFrame.height, ThemeCardLayoutMetrics.singleLineHeight)

        let button = try XCTUnwrap(catalog.service.revealThemeButton(themeID: targetTitle))
        let cell = try XCTUnwrap(collectionView.cellForItem(at: targetIndexPath) as? ThemeCardCollectionViewCell)
        XCTAssertTrue(button === cell.actionButton)
        XCTAssertEqual(button.accessibilityIdentifier, targetTitle)
        XCTAssertGreaterThan(collectionView.contentOffset.y, 0)
        XCTAssertTrue(targetFrame.intersects(collectionView.bounds))

        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(delegate.selectedThemeIDs, [targetTitle])
        let transition = cell.makeTransitionContent()
        XCTAssertEqual(transition.geometry.containerSize, targetFrame.size)
        XCTAssertEqual(transition.view.bounds.size, targetFrame.size)
        let transitionTitle = try XCTUnwrap(transition.view.subviews.compactMap { $0 as? UILabel }.first)
        XCTAssertEqual(transitionTitle.text, targetTitle)
        XCTAssertTrue(transition.view.bounds.insetBy(dx: -0.5, dy: -0.5).contains(transitionTitle.frame))
        withExtendedLifetime(catalog) {}
    }

    func testAvailableHeightChangesEnableAndDisableOverflowOnTheSameCatalog() throws {
        let catalog = try makeCatalog(names: [
            "Музыка", "История Древнего Рима и Древнего мира", "Кино", "Игры", "Спорт", "Мифы"
        ])
        let collectionView = catalog.cell.themesCollectionView
        let moreThemes = try XCTUnwrap(
            catalog.cell.contentView.subviews.compactMap { $0 as? MoreThemesFadeButton }.first
        )
        let contentHeight = collectionView.contentSize.height
        XCTAssertFalse(collectionView.isScrollEnabled)
        XCTAssertTrue(moreThemes.isHidden)

        for (outerHeight, expectsOverflow): (CGFloat, Bool) in [(500, true), (700, false)] {
            catalog.outer.frame.size.height = outerHeight
            let size = catalog.service.collectionView(
                catalog.outer, layout: catalog.outer.collectionViewLayout,
                sizeForItemAt: IndexPath(item: 0, section: 0)
            )
            catalog.cell.frame.size = size
            catalog.cell.contentView.frame = catalog.cell.bounds
            catalog.cell.setNeedsLayout()
            catalog.cell.layoutIfNeeded()
            catalog.cell.contentView.layoutIfNeeded()
            collectionView.layoutIfNeeded()

            XCTAssertEqual(collectionView.contentSize.height, contentHeight)
            XCTAssertEqual(collectionView.contentSize.height > collectionView.bounds.height, expectsOverflow)
            XCTAssertEqual(collectionView.isScrollEnabled, expectsOverflow)
            XCTAssertEqual(collectionView.alwaysBounceVertical, expectsOverflow)
            XCTAssertEqual(collectionView.bounces, expectsOverflow)
            XCTAssertEqual(moreThemes.isHidden, !expectsOverflow)
            if !expectsOverflow {
                XCTAssertNil(collectionView.layer.mask, "The fade must be removed once all cards fit")
            }
        }
        withExtendedLifetime(catalog) {}
    }

    private func makeCatalog(
        names: [String], outerHeight: CGFloat = 700,
        category: UIContentSizeCategory = .large
    ) throws -> (service: ThemesCollectionService, outer: UICollectionView, cell: ThemesViewportCollectionViewCell) {
        QuizFactory.shared.themes = names.map { makeTheme(name: $0) }
        let service = ThemesCollectionService(preferredThemeIDsProvider: { [] })
        let outer = makeCollectionView(width: 375)
        outer.frame.size.height = outerHeight
        let host = UIViewController()
        host.traitOverrides.preferredContentSizeCategory = category
        host.view.addSubview(outer)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        testWindows.append(window)
        outer.updateTraitsIfNeeded()
        let indexPath = IndexPath(item: 0, section: 0)
        let size = service.collectionView(outer, layout: outer.collectionViewLayout, sizeForItemAt: indexPath)
        let cell = try XCTUnwrap(service.collectionView(outer, cellForItemAt: indexPath) as? ThemesViewportCollectionViewCell)
        cell.frame = CGRect(origin: .zero, size: size)
        cell.contentView.frame = cell.bounds
        host.view.addSubview(cell)
        cell.updateTraitsIfNeeded()
        cell.layoutIfNeeded()
        cell.contentView.layoutIfNeeded()
        cell.themesCollectionView.layoutIfNeeded()
        return (service, outer, cell)
    }

    private func itemFrames(in collectionView: UICollectionView) throws -> [CGRect] {
        try (0..<collectionView.numberOfItems(inSection: 0)).map { item in
            try XCTUnwrap(collectionView.collectionViewLayout.layoutAttributesForItem(
                at: IndexPath(item: item, section: 0)
            )).frame
        }
    }

    private func assertFramesDoNotOverlap(
        _ frames: [CGRect], file: StaticString = #filePath, line: UInt = #line
    ) {
        for (index, frame) in frames.enumerated() {
            for otherFrame in frames.dropFirst(index + 1) {
                XCTAssertFalse(frame.intersects(otherFrame), file: file, line: line)
            }
        }
    }
}
