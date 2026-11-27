import SwiftUI
import XCTest
@testable import Quizice

@MainActor
final class HomeScreenLayoutTests: HomeScreenVisualStateTestCase {
    func testHomeScreenExposesObservableLayoutAnchors() {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка")]

        let viewController = QuizViewController()
        viewController.loadViewIfNeeded()

        XCTAssertNotNil(viewController.view.descendant(withAccessibilityIdentifier: "homeRootView"))
        XCTAssertNotNil(viewController.view.descendant(withAccessibilityIdentifier: "homeMotivationLabel"))
        XCTAssertNotNil(viewController.view.descendant(withAccessibilityIdentifier: "homeThemesCollectionView"))
        XCTAssertNotNil(viewController.view.descendant(withAccessibilityIdentifier: "homeSettingsButton"))
        XCTAssertNil(viewController.view.descendant(withAccessibilityIdentifier: "homeBackgroundStyleButton"))
        XCTAssertNil(viewController.view.descendant(withAccessibilityIdentifier: "homeDebugInterfaceButton"))
    }

    func testHomeHeaderUsesSingleLeadingMotivationPrompt() throws {
        useDesignStyle(.clean)
        QuizFactory.shared.themes = [makeTheme(name: "Музыка")]

        let viewController = QuizViewController()
        viewController.loadViewIfNeeded()

        let headerStackView = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "homeHeaderStackView") as? UIStackView)
        let motivationLabel = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "homeMotivationLabel") as? UILabel)

        XCTAssertEqual(headerStackView.alignment, .leading)
        XCTAssertTrue(motivationLabel.isDescendant(of: headerStackView))
        XCTAssertEqual(motivationLabel.textAlignment, .left)
        XCTAssertTrue(L10n.Home.motivationPrompts.contains(motivationLabel.text ?? ""))
        XCTAssertNil(viewController.view.descendant(withAccessibilityIdentifier: "homeWelcomeLabel"))
        XCTAssertNil(viewController.view.descendant(withAccessibilityIdentifier: "homeLogoImageView"))
        XCTAssertNil(viewController.view.descendant(withAccessibilityIdentifier: "homeLogoTextLabel"))
        XCTAssertNil(viewController.view.descendant(withAccessibilityIdentifier: "homeChooseThemeLabel"))
    }

    func testNonCleanHomeHeaderAlsoUsesLeadingAlignment() throws {
        UserDefaults.standard.set(AppDesignStyle.radar.rawValue, forKey: AppAppearanceStore.Keys.designStyle)
        QuizFactory.shared.themes = [makeTheme(name: "Музыка")]

        let viewController = QuizViewController()
        viewController.loadViewIfNeeded()

        let headerStackView = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "homeHeaderStackView") as? UIStackView)
        let motivationLabel = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "homeMotivationLabel") as? UILabel)

        XCTAssertEqual(headerStackView.alignment, .leading)
        XCTAssertEqual(motivationLabel.textAlignment, .left)
    }

    func testHomeCollectionCanCancelButtonTouchesForScrolling() {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка")]

        let viewController = QuizViewController()
        viewController.loadViewIfNeeded()

        let collectionView = viewController.view.descendant(withAccessibilityIdentifier: "homeThemesCollectionView") as? UICollectionView

        XCTAssertEqual(collectionView?.delaysContentTouches, true)
        XCTAssertEqual(collectionView?.canCancelContentTouches, true)
        XCTAssertEqual(collectionView?.contentInsetAdjustmentBehavior, .never)
        XCTAssertEqual(collectionView?.touchesShouldCancel(in: UIButton(type: .system)), true)
    }

    func testHomeCollectionScrollsOnlyWhenContentDoesNotFit() {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка")]

        let viewController = makeHomeViewController(in: CGRect(x: 0, y: 0, width: 390, height: 844))

        let collectionView = viewController.view.descendant(withAccessibilityIdentifier: "homeThemesCollectionView") as? UICollectionView
        XCTAssertEqual(collectionView?.isScrollEnabled, false)
        XCTAssertEqual(collectionView?.alwaysBounceVertical, false)
        XCTAssertEqual(collectionView?.bounces, false)

        let compactViewController = makeHomeViewController(in: CGRect(x: 0, y: 0, width: 390, height: 430))
        let compactCollectionView = compactViewController.view.descendant(withAccessibilityIdentifier: "homeThemesCollectionView") as? UICollectionView

        XCTAssertEqual(compactCollectionView?.isScrollEnabled, true)
        XCTAssertEqual(compactCollectionView?.alwaysBounceVertical, true)
        XCTAssertEqual(compactCollectionView?.bounces, true)
    }

    func testHomeBalancesEdgeGapsWhenThemesFillTheAvailableSpace() throws {
        let sizesAndThemeCounts: [(CGSize, Int)] = [
            (CGSize(width: 375, height: 667), 24),
            (CGSize(width: 390, height: 844), 24),
            (CGSize(width: 834, height: 1_194), 36),
            (CGSize(width: 390, height: 844), 1)
        ]
        for (size, themeCount) in sizesAndThemeCounts {
            QuizFactory.shared.themes = (0..<themeCount).map { makeTheme(name: "Тема \($0)") }
            let controller = makeHomeViewController(in: CGRect(origin: .zero, size: size))
            controller.additionalSafeAreaInsets = UIEdgeInsets(top: 9, left: 0, bottom: 13, right: 0)
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()

            let outer = try XCTUnwrap(controller.themesCollectionView)
            let catalog = try XCTUnwrap(controller.themesCollectionService.catalogCollectionView)
            let statistics = try XCTUnwrap(controller.sourceStatisticsButton())
            let header = try XCTUnwrap(controller.motivationLabel)
            let safeArea = controller.view.safeAreaLayoutGuide.layoutFrame
            let topGap = header.convert(header.bounds, to: controller.view).minY - safeArea.minY
            let bottomGap = safeArea.maxY - statistics.convert(statistics.bounds, to: controller.view).maxY

            XCTAssertGreaterThan(topGap, 0)
            XCTAssertFalse(outer.isScrollEnabled)
            XCTAssertEqual(catalog.isScrollEnabled, themeCount > 1)
            if themeCount > 1 {
                XCTAssertEqual(bottomGap, topGap, accuracy: 1, "Home size \(size), \(themeCount) themes")
            } else {
                XCTAssertGreaterThanOrEqual(bottomGap, topGap)
                XCTAssertEqual(catalog.bounds.height, catalog.contentSize.height, accuracy: 1)
            }
        }
    }

    func testHomeMotivationLabelFadesAsCollectionScrollsUp() throws {
        QuizFactory.shared.themes = [
            makeTheme(name: "Музыка"),
            makeTheme(name: "Технологии"),
            makeTheme(name: "История и культура"),
            makeTheme(name: "Политика и бизнес")
        ]

        let viewController = makeHomeViewController(in: CGRect(x: 0, y: 0, width: 390, height: 430))
        let collectionView = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "homeThemesCollectionView") as? UICollectionView)
        let motivationLabel = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "homeMotivationLabel") as? UILabel)
        let topInset = collectionView.adjustedContentInset.top

        XCTAssertGreaterThan(topInset, 0)
        XCTAssertEqual(motivationLabel.alpha, 1)

        collectionView.contentOffset.y = -topInset + 18
        collectionView.delegate?.scrollViewDidScroll?(collectionView)

        XCTAssertEqual(motivationLabel.alpha, 0.75, accuracy: 0.001)

        collectionView.contentOffset.y = -topInset + 36
        collectionView.delegate?.scrollViewDidScroll?(collectionView)

        XCTAssertEqual(motivationLabel.alpha, 0.5, accuracy: 0.001)

        collectionView.contentOffset.y = -topInset + 72
        collectionView.delegate?.scrollViewDidScroll?(collectionView)

        XCTAssertEqual(motivationLabel.alpha, 0, accuracy: 0.001)
    }

    func testHomeMotivationLabelHasNoGlowLayerOnFirstAppearanceAfterLaunch() throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка")]
        QuizFactory.shared.startup1st = true
        let viewController = QuizViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.layoutIfNeeded()

        viewController.viewDidAppear(false)

        XCTAssertNil(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeMotivationBlurredImageView"
            )
        )
        XCTAssertFalse(QuizFactory.shared.startup1st)
    }

    func testHomeStatisticsRefreshesWhenQuizFlowReturns() throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка")]
        let statisticsStore = makeStatisticsStore()
        let viewController = QuizViewController(statisticsStore: statisticsStore)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        testWindows.append(window)

        let initialPlayedValue = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeStatisticsPlayedValueLabel"
            ) as? UILabel
        )
        XCTAssertEqual(initialPlayedValue.text, "0")

        statisticsStore.recordAttempt(correctAnswers: 4, totalQuestions: 5)
        viewController.quizFlowWillReturnToThemes()

        let refreshedPlayedValue = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeStatisticsPlayedValueLabel"
            ) as? UILabel
        )
        XCTAssertEqual(refreshedPlayedValue.text, "1")
    }

    func testHomeCollectionIsLayeredAboveMotivationHeader() throws {
        QuizFactory.shared.themes = [
            makeTheme(name: "Музыка"),
            makeTheme(name: "Технологии")
        ]

        let viewController = makeHomeViewController(in: CGRect(x: 0, y: 0, width: 390, height: 430))
        let headerStackView = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "homeHeaderStackView"))
        let screenStackView = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "homeScreenStackView"))
        let headerIndex = try XCTUnwrap(viewController.view.subviews.firstIndex(of: headerStackView))
        let screenIndex = try XCTUnwrap(viewController.view.subviews.firstIndex(of: screenStackView))

        XCTAssertLessThan(headerIndex, screenIndex)
        XCTAssertLessThan(headerStackView.layer.zPosition, screenStackView.layer.zPosition)
    }

    func testHomeScreenIsVisibleAndInteractiveBeforeFirstRenderedFrame() throws {
        QuizFactory.shared.startup1st = true

        let viewController = QuizViewController()
        viewController.loadView()

        let motivationLabel = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "homeMotivationLabel"))
        let collectionView = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "homeThemesCollectionView"))
        let settingsButton = try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "homeSettingsButton") as? UIButton)

        XCTAssertGreaterThan(motivationLabel.alpha, 0)
        XCTAssertGreaterThan(collectionView.alpha, 0)
        XCTAssertGreaterThan(settingsButton.alpha, 0)
        XCTAssertTrue(collectionView.isUserInteractionEnabled)
        XCTAssertTrue(settingsButton.isUserInteractionEnabled)
        XCTAssertTrue(settingsButton.isEnabled)
    }

    func testHomeShellHasNoAmbiguousLayout() {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка")]

        let viewController = QuizViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        XCTAssertFalse(viewController.view.hasAmbiguousLayout)
    }

}
