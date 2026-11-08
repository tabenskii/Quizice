import SwiftUI
import XCTest
@testable import Quizice

@MainActor
final class HomeExpandedCardTransitionTests: HomeScreenVisualStateTestCase {
    func testExpandedStatisticsCardKeepsLargeHistoryValueVisibleAtNarrowWidths() throws {
        let summary = StatisticsSummary(
            playedQuizzes: 53,
            correctAnswers: 74,
            totalQuestions: 265,
            bestCorrectAnswers: 5,
            bestTotalQuestions: 5
        )
        let appearance = SnapshotSupport.appearance(designStyle: .radar)

        for screenWidth in [CGFloat(402), CGFloat(320)] {
            let card = ExpandedStatisticsCardView(
                frame: CGRect(x: 20, y: 126, width: screenWidth - 40, height: 600)
            )
            card.configure(summary: summary, appearance: appearance)

            let host = UIViewController()
            host.view.addSubview(card)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: screenWidth, height: 874))
            window.rootViewController = host
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            card.layoutIfNeeded()
            testWindows.append(window)

            let correctRow = try XCTUnwrap(
                card.descendant(withAccessibilityIdentifier: "expandedStatisticsMetric-correctAnswers")
            )
            let labels = correctRow.subviews.compactMap { $0 as? UILabel }
            let correctValueLabel = try XCTUnwrap(labels.first { $0.text == "74/265" })
            let titleLabel = try XCTUnwrap(labels.first { $0 !== correctValueLabel })
            let requiredValueWidth = ceil(
                ("74/265" as NSString).size(withAttributes: [.font: correctValueLabel.font!]).width
            )
            let valueFrame = correctValueLabel.convert(correctValueLabel.bounds, to: correctRow)

            XCTAssertEqual(correctRow.accessibilityValue, "74/265")
            XCTAssertTrue(correctValueLabel.adjustsFontSizeToFitWidth)
            XCTAssertEqual(correctValueLabel.minimumScaleFactor, 0.75, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(correctValueLabel.bounds.width + 0.5, requiredValueWidth)
            XCTAssertGreaterThan(
                correctValueLabel.contentCompressionResistancePriority(for: .horizontal).rawValue,
                titleLabel.contentCompressionResistancePriority(for: .horizontal).rawValue
            )
            XCTAssertTrue(correctRow.bounds.insetBy(dx: -0.5, dy: -0.5).contains(valueFrame))
        }
    }

    func testStatisticsCardExpandsInlineTracksOnceAndRestoresTheGridWithoutQuizCancellation() throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка", questionCount: 15)]
        let statisticsStore = makeStatisticsStore(attempts: [
            (correctAnswers: 3, totalQuestions: 5),
            (correctAnswers: 5, totalQuestions: 5)
        ])
        let analytics = HomeAnalyticsTrackingSpy()
        let motionProvider = HomeThemeCardMotionProviderFake()
        let viewController = QuizViewController(
            statisticsStore: statisticsStore,
            analytics: analytics,
            cardDeviceParallaxEnabledProvider: { true },
            cardMotionProvider: motionProvider
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

        let collectionView = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeThemesCollectionView"
            ) as? UICollectionView
        )
        collectionView.layoutIfNeeded()
        let initialScrollEnabled = collectionView.isScrollEnabled
        let initialAlwaysBounceVertical = collectionView.alwaysBounceVertical
        let initialBounces = collectionView.bounces
        let initialContentOffset = collectionView.contentOffset
        let sourceButton = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeStatisticsCard"
            ) as? UIButton
        )

        sourceButton.sendActions(for: .touchUpInside)
        drainAnimations()

        let backdrop = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeExpandedThemeCardBackdrop"
            )
        )
        let expandedCard = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeExpandedStatisticsCard"
            )
        )
        XCTAssertTrue(backdrop.superview === viewController.view)
        XCTAssertEqual(backdrop.frame, viewController.view.bounds)
        XCTAssertTrue(backdrop is UIVisualEffectView)
        XCTAssertNotNil((backdrop as? UIVisualEffectView)?.effect)
        XCTAssertTrue(expandedCard.superview === viewController.view)
        XCTAssertFalse(expandedCard.isDescendant(of: backdrop))
        XCTAssertGreaterThan(expandedCard.layer.zPosition, backdrop.layer.zPosition)
        XCTAssertTrue(expandedCard.accessibilityViewIsModal)
        XCTAssertTrue(sourceButton.isHidden)
        XCTAssertFalse(collectionView.isUserInteractionEnabled)
        XCTAssertFalse(collectionView.isScrollEnabled)
        XCTAssertNil(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeExpandedStatisticsCardTransition"
            )
        )
        XCTAssertFalse(
            (expandedCard.gestureRecognizers ?? []).contains { $0 is UIPanGestureRecognizer }
        )
        XCTAssertNil(parallaxPanGestureRecognizer(in: expandedCard))
        XCTAssertEqual(motionProvider.startCallCount, 0)
        XCTAssertFalse(motionProvider.isStarted)

        let expectedMetrics: [(id: String, title: String, value: String)] = [
            ("playedQuizzes", L10n.Statistics.playedQuizzes, "2"),
            ("correctAnswers", L10n.Statistics.correctAnswers, "8/10"),
            ("percentage", L10n.Statistics.percentage, "80%"),
            ("bestResult", L10n.Statistics.bestResult, "5/5")
        ]
        let metricRows = try expectedMetrics.map { expected in
            let row = try XCTUnwrap(
                viewController.view.descendant(
                    withAccessibilityIdentifier: "expandedStatisticsMetric-\(expected.id)"
                )
            )
            XCTAssertEqual(row.accessibilityLabel, expected.title)
            XCTAssertEqual(row.accessibilityValue, expected.value)
            return row
        }
        XCTAssertEqual(Set(metricRows.map { ObjectIdentifier($0) }).count, 4)
        XCTAssertTrue(
            try XCTUnwrap(
                viewController.view.descendant(
                    withAccessibilityIdentifier: "expandedStatisticsCardEmptyState"
                )
            ).isHidden
        )

        let inlineStatisticsEvents = analytics.events.filter { event in
            !(event.name == "screen_view" && event.parameters["screen"] as? String == "home")
        }
        XCTAssertEqual(inlineStatisticsEvents.map(\.name), ["screen_view", "statistics_viewed"])
        let statisticsScreenEvents = analytics.events.filter {
            $0.name == "screen_view" && $0.parameters["screen"] as? String == "statistics"
        }
        let statisticsViewedEvents = analytics.events.filter { $0.name == "statistics_viewed" }
        XCTAssertEqual(statisticsScreenEvents.count, 1)
        XCTAssertEqual(statisticsViewedEvents.count, 1)
        XCTAssertEqual(statisticsViewedEvents.first?.parameters["attempts_count"] as? Int, 2)
        XCTAssertEqual(statisticsViewedEvents.first?.parameters["total_questions"] as? Int, 10)
        XCTAssertEqual(statisticsViewedEvents.first?.parameters["accuracy_percent"] as? Int, 80)
        XCTAssertFalse(analytics.events.contains { $0.name == "quiz_setup_cancelled" })

        let backdropDismissButton = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeExpandedThemeCardBackdropDismissButton"
            ) as? UIButton
        )
        backdropDismissButton.sendActions(for: .touchUpInside)
        drainAnimations()

        XCTAssertNil(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeExpandedThemeCardBackdrop"
            )
        )
        XCTAssertNil(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeExpandedStatisticsCard"
            )
        )
        let restoredSourceButton = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeStatisticsCard"
            ) as? UIButton
        )
        XCTAssertFalse(restoredSourceButton.isHidden)
        XCTAssertTrue(restoredSourceButton.isUserInteractionEnabled)
        XCTAssertTrue(collectionView.isUserInteractionEnabled)
        XCTAssertEqual(collectionView.isScrollEnabled, initialScrollEnabled)
        XCTAssertEqual(collectionView.alwaysBounceVertical, initialAlwaysBounceVertical)
        XCTAssertEqual(collectionView.bounces, initialBounces)
        XCTAssertEqual(collectionView.contentOffset.x, initialContentOffset.x, accuracy: 0.001)
        XCTAssertEqual(collectionView.contentOffset.y, initialContentOffset.y, accuracy: 0.001)
        let eventsAfterCollapse = analytics.events.filter { event in
            !(event.name == "screen_view" && event.parameters["screen"] as? String == "home")
        }
        XCTAssertEqual(eventsAfterCollapse.map(\.name), ["screen_view", "statistics_viewed"])
        XCTAssertFalse(analytics.events.contains { $0.name == "quiz_setup_cancelled" })
    }

    func testCatalogThemeExpandsInlineAboveFullScreenBlurAndClosesBackToGrid() throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка", questionCount: 15)]

        let viewController = makeHomeViewController(in: CGRect(x: 0, y: 0, width: 390, height: 844))
        let router = HomeRouterSpy()
        viewController.router = router
        let collectionView = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeThemesCollectionView") as? UICollectionView
        )
        let themeCollectionView = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: ThemesCollectionService.Content.themeCatalogAccessibilityID
            ) as? UICollectionView
        )
        let sourceButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "music") as? UIButton
        )
        let sourceCell = try XCTUnwrap(
            themeCollectionView.visibleCells
                .compactMap { $0 as? ThemeCardCollectionViewCell }
                .first(where: { $0.actionButton === sourceButton })
        )
        let sourceFrame = sourceButton.convert(sourceButton.bounds, to: viewController.view)
        let expectedSourceShadowPath = UIBezierPath(
            roundedRect: sourceButton.frame,
            cornerRadius: sourceButton.layer.cornerRadius
        ).cgPath
        XCTAssertEqual(sourceCell.layer.shadowPath, expectedSourceShadowPath)

        sourceButton.sendActions(for: .touchUpInside)

        let backdrop = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedThemeCardBackdrop")
        )
        let card = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedThemeCard")
        )
        let transitionView = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedThemeCardTransition")
        )
        let transitionChrome = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedThemeCardTransitionChrome")
        )
        let transitionIntensity = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedThemeCardTransitionIntensity")
        )
        let sourceSnapshot = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedThemeCardSourceSnapshot")
        )
        let sourceContentHost = try XCTUnwrap(sourceSnapshot.superview)
        let frontImageView = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "expandedThemeCardFrontImageView"
            ) as? UIImageView
        )
        let frontImageShadowView = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "expandedThemeCardFrontImageShadowView"
            ) as? UIImageView
        )
        card.layoutIfNeeded()
        XCTAssertTrue(backdrop.superview === viewController.view)
        XCTAssertTrue(transitionView.superview === viewController.view)
        XCTAssertEqual(transitionChrome.alpha, 1, accuracy: 0.001)
        XCTAssertEqual(transitionIntensity.alpha, 1, accuracy: 0.001)
        XCTAssertFalse(card.superview === viewController.view)
        XCTAssertTrue(sourceSnapshot.isDescendant(of: transitionView))
        XCTAssertEqual(sourceSnapshot.center.x, sourceContentHost.bounds.midX, accuracy: 0.001)
        XCTAssertEqual(sourceSnapshot.center.y, sourceContentHost.bounds.midY, accuracy: 0.001)
        XCTAssertEqual(sourceSnapshot.bounds.size, sourceFrame.size)
        XCTAssertGreaterThan(card.bounds.width, sourceSnapshot.bounds.width)
        XCTAssertGreaterThan(card.bounds.height, sourceSnapshot.bounds.height)
        XCTAssertTrue(CGAffineTransformIsIdentity(card.transform))
        XCTAssertEqual(backdrop.frame, viewController.view.bounds)
        XCTAssertLessThan(backdrop.layer.zPosition, transitionView.layer.zPosition)
        XCTAssertTrue(backdrop is UIVisualEffectView)
        XCTAssertFalse(collectionView.isUserInteractionEnabled)
        XCTAssertTrue(sourceButton.isHidden)
        XCTAssertTrue(card.accessibilityViewIsModal)
        XCTAssertEqual(frontImageView.contentMode, .scaleAspectFit)
        XCTAssertGreaterThan(frontImageView.image?.size.width ?? 0, 0)
        XCTAssertEqual(frontImageShadowView.image?.pngData(), frontImageView.image?.pngData())
        XCTAssertEqual(frontImageShadowView.transform.ty, 3, accuracy: 0.01)
        XCTAssertEqual(frontImageShadowView.alpha, 0.26, accuracy: 0.01)
        assertColor(frontImageShadowView.tintColor, equals: .black)
        XCTAssertTrue(
            viewController.view.descendant(withAccessibilityIdentifier: "homeHeaderStackView")?.accessibilityElementsHidden == true
        )
        XCTAssertTrue(
            viewController.view.descendant(withAccessibilityIdentifier: "homeScreenStackView")?.accessibilityElementsHidden == true
        )
        XCTAssertTrue(
            viewController.view.descendant(withAccessibilityIdentifier: "homeSettingsButton")?.accessibilityElementsHidden == true
        )
        XCTAssertTrue(
            viewController.view.descendant(withAccessibilityIdentifier: "homeOnboardingHelpButton")?.accessibilityElementsHidden == true
        )

        let targetCardFrame = card.convert(card.bounds, to: viewController.view)
        drainAnimations(0.08)
        XCTAssertEqual(sourceSnapshot.bounds.size, sourceFrame.size)
        XCTAssertEqual(card.bounds.size, targetCardFrame.size)
        XCTAssertTrue(CGAffineTransformIsIdentity(card.transform))

        drainAnimations()
        viewController.view.layoutIfNeeded()
        XCTAssertNil(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedThemeCardTransition")
        )
        XCTAssertTrue(card.superview === viewController.view)
        XCTAssertEqual(sourceSnapshot.bounds.size, sourceFrame.size)
        XCTAssertTrue(sourceSnapshot.isHidden)
        XCTAssertGreaterThan(frontImageView.bounds.width, 100)
        XCTAssertGreaterThan(frontImageView.bounds.height, 100)
        XCTAssertNotNil((backdrop as? UIVisualEffectView)?.effect)
        XCTAssertTrue(viewController.cardSlideTransitionSourceView === card)

        let backdropDismissButton = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeExpandedThemeCardBackdropDismissButton"
            ) as? UIButton
        )
        backdropDismissButton.sendActions(for: .touchUpInside)

        let collapsingTransition = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedThemeCardTransition")
        )
        let collapsingChrome = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedThemeCardTransitionChrome")
        )
        let collapsingIntensity = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedThemeCardTransitionIntensity")
        )
        XCTAssertTrue(collapsingTransition.superview === viewController.view)
        XCTAssertEqual(collapsingChrome.alpha, 1, accuracy: 0.001)
        XCTAssertEqual(collapsingIntensity.alpha, 0, accuracy: 0.001)
        XCTAssertEqual(collapsingTransition.layer.shadowPath, sourceCell.layer.shadowPath)
        let collapsingSourceSnapshot = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeExpandedThemeCardSourceSnapshot"
            )
        )
        XCTAssertEqual(collapsingSourceSnapshot.bounds.size, sourceFrame.size)
        XCTAssertFalse(collapsingSourceSnapshot.isHidden)
        XCTAssertFalse(card.superview === viewController.view)
        drainAnimations()

        XCTAssertNil(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedThemeCardBackdrop")
        )
        XCTAssertNil(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedThemeCard")
        )
        XCTAssertTrue(collectionView.isUserInteractionEnabled)
        XCTAssertFalse(
            try XCTUnwrap(viewController.view.descendant(withAccessibilityIdentifier: "music") as? UIButton).isHidden
        )
    }

    func testExpandedClassicArtworkPreservesTheSourceImageAspectRatio() throws {
        useDesignStyle(.classic)
        QuizFactory.shared.themes = [makeTheme(name: "Технологии", questionCount: 15)]

        let viewController = makeHomeViewController(in: CGRect(x: 0, y: 0, width: 390, height: 844))
        let sourceButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "technology") as? UIButton
        )
        let sourceImageView = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeThemeImageView-technology"
            ) as? UIImageView
        )
        let sourceImage = try XCTUnwrap(sourceImageView.image)
        let sourceAspectRatio = sourceImage.size.width / sourceImage.size.height
        XCTAssertGreaterThan(abs(sourceAspectRatio - 1), 0.01)

        sourceButton.sendActions(for: .touchUpInside)

        let expandedImageView = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "expandedThemeCardFrontImageView"
            ) as? UIImageView
        )
        let expandedImage = try XCTUnwrap(expandedImageView.image)
        let expandedAspectRatio = expandedImage.size.width / expandedImage.size.height

        XCTAssertEqual(expandedImageView.contentMode, .scaleAspectFit)
        XCTAssertEqual(expandedAspectRatio, sourceAspectRatio, accuracy: 0.001)
    }

    func testCollapseRefreshesSourceContentAfterAppearanceChanges() throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка", questionCount: 15)]

        let viewController = makeHomeViewController(in: CGRect(x: 0, y: 0, width: 390, height: 844))
        let sourceButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "music") as? UIButton
        )
        sourceButton.sendActions(for: .touchUpInside)
        drainAnimations()

        AppAppearanceStore.shared.designStyle = .radar
        viewController.view.layoutIfNeeded()

        let backdropDismissButton = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeExpandedThemeCardBackdropDismissButton"
            ) as? UIButton
        )
        backdropDismissButton.sendActions(for: .touchUpInside)

        let refreshedSourceContent = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeExpandedThemeCardSourceSnapshot"
            )
        )
        let refreshedImageView = try XCTUnwrap(
            refreshedSourceContent.subviews.compactMap { $0 as? UIImageView }.first
        )
        let expectedRadarImage = try XCTUnwrap(
            UIImage(systemName: "music.note.list")?.withRenderingMode(.alwaysTemplate)
        )

        XCTAssertEqual(refreshedImageView.image?.pngData(), expectedRadarImage.pngData())
        drainAnimations()
    }

    func testExpandAndCollapseReverseInFlightUsingTheSameTransitionView() throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка", questionCount: 15)]

        let viewController = makeHomeViewController(in: CGRect(x: 0, y: 0, width: 390, height: 844))
        let sourceButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "music") as? UIButton
        )
        sourceButton.sendActions(for: .touchUpInside)

        let expandingTransition = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedThemeCardTransition")
        )
        let expandingSurface = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeExpandedThemeCardTransitionSurfaceButton"
            ) as? UIButton
        )
        let expandingBackdrop = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeExpandedThemeCardBackdropDismissButton"
            ) as? UIButton
        )
        XCTAssertFalse(expandingTransition.isUserInteractionEnabled)
        XCTAssertTrue(expandingSurface.superview === viewController.view)

        expandingBackdrop.sendActions(for: .touchUpInside)
        XCTAssertTrue(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeExpandedThemeCardTransition"
            ) === expandingTransition
        )
        drainAnimations()
        XCTAssertNil(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedThemeCard")
        )
        XCTAssertFalse(
            try XCTUnwrap(
                viewController.view.descendant(withAccessibilityIdentifier: "music") as? UIButton
            ).isHidden
        )

        let refreshedSourceButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "music") as? UIButton
        )
        refreshedSourceButton.sendActions(for: .touchUpInside)
        drainAnimations()

        let backdropDismissButton = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeExpandedThemeCardBackdropDismissButton"
            ) as? UIButton
        )
        let expandedCard = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedThemeCard")
        )
        let expandedCardFrame = expandedCard.convert(expandedCard.bounds, to: viewController.view)
        backdropDismissButton.sendActions(for: .touchUpInside)
        let collapsingTransition = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedThemeCardTransition")
        )
        let collapsingSurface = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeExpandedThemeCardTransitionSurfaceButton"
            ) as? UIButton
        )

        let visibleFrame = collapsingTransition.layer.presentation()?.frame ?? expandedCardFrame
        let sourceFrame = refreshedSourceButton.convert(refreshedSourceButton.bounds, to: viewController.view)
        let candidatePoints = [
            CGPoint(x: visibleFrame.minX + 12, y: visibleFrame.minY + 12),
            CGPoint(x: visibleFrame.maxX - 12, y: visibleFrame.minY + 12),
            CGPoint(x: visibleFrame.minX + 12, y: visibleFrame.maxY - 12),
            CGPoint(x: visibleFrame.maxX - 12, y: visibleFrame.maxY - 12)
        ]
        let visiblePointOutsideSource = try XCTUnwrap(
            candidatePoints.first {
                viewController.view.bounds.contains($0) && !sourceFrame.contains($0)
            }
        )
        let hitControl = try XCTUnwrap(
            viewController.view.hitTest(visiblePointOutsideSource, with: nil) as? UIControl
        )
        XCTAssertTrue(hitControl === collapsingSurface)
        hitControl.sendActions(for: .touchUpInside)
        XCTAssertTrue(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeExpandedThemeCardTransition"
            ) === collapsingTransition
        )
        drainAnimations()
        XCTAssertNil(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedThemeCardTransition")
        )
        XCTAssertNil(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedThemeCard")
        )
        XCTAssertNil(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedThemeCardBackdrop")
        )
    }

    func testReducedMotionExpansionCanReverseFromVisibleSourceSurface() throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка", questionCount: 15)]

        let viewController = QuizViewController(cardReduceMotionProvider: { true })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        testWindows.append(window)

        let sourceButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "music") as? UIButton
        )
        sourceButton.sendActions(for: .touchUpInside)

        let backdropDismissButton = try XCTUnwrap(
            viewController.view.descendant(
                withAccessibilityIdentifier: "homeExpandedThemeCardBackdropDismissButton"
            ) as? UIButton
        )
        backdropDismissButton.sendActions(for: .touchUpInside)
        drainAnimations(0.24)

        XCTAssertNil(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedThemeCard")
        )
        XCTAssertFalse(
            try XCTUnwrap(
                viewController.view.descendant(withAccessibilityIdentifier: "music") as? UIButton
            ).isHidden
        )
    }

    func testExpandedThemeCardUsesReducedTransparencyBackdropAndReducedMotionCrossfade() throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка", questionCount: 15)]

        let viewController = QuizViewController(
            cardReduceMotionProvider: { true },
            cardReduceTransparencyProvider: { true }
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        testWindows.append(window)

        let sourceButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "music") as? UIButton
        )
        sourceButton.sendActions(for: .touchUpInside)
        drainAnimations(0.22)

        let backdrop = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "homeExpandedThemeCardBackdrop")
        )
        XCTAssertFalse(backdrop is UIVisualEffectView)
        XCTAssertEqual(backdrop.alpha, 1, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(backdrop.backgroundColor?.cgColor.alpha ?? 0, 0.95)

        let front = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardFrontView")
        )
        let back = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardBackView")
        )
        let rotatingCarrier = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardRotatingCarrier")
        )
        let infoButton = try XCTUnwrap(
            viewController.view.descendant(withAccessibilityIdentifier: "expandedThemeCardInfoButton") as? UIButton
        )
        infoButton.sendActions(for: .touchUpInside)

        XCTAssertTrue(CATransform3DIsIdentity(front.layer.transform))
        XCTAssertTrue(CATransform3DIsIdentity(back.layer.transform))
        XCTAssertTrue(CATransform3DIsIdentity(rotatingCarrier.layer.transform))
        drainAnimations(0.22)
        XCTAssertTrue(front.isHidden)
        XCTAssertFalse(back.isHidden)
        XCTAssertTrue(CATransform3DIsIdentity(front.layer.transform))
        XCTAssertTrue(CATransform3DIsIdentity(back.layer.transform))
        XCTAssertFalse(CATransform3DIsIdentity(rotatingCarrier.layer.transform))
    }

}

extension HomeExpandedCardTransitionTests {
    func testRemoteStatisticsRefreshUpdatesAnAlreadyExpandedCard() async throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка", questionCount: 15)]
        let statistics = makeStatisticsStore()
        statistics.activateAuthenticatedUser("remote-player")
        let controller = QuizViewController(statisticsStore: statistics, cardReduceMotionProvider: { true })
        let router = HomeRouterSpy()
        controller.router = router
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        testWindows.append(window)
        try await waitUntil { router.refreshAccountDataCallCount >= 1 }
        let initialRefreshes = router.refreshAccountDataCallCount
        let button = try XCTUnwrap(controller.view.descendant(withAccessibilityIdentifier: "homeStatisticsCard") as? UIButton)
        button.sendActions(for: .touchUpInside)
        try await waitUntil { controller.homeCardState.phase == .expandedFront }
        try await waitUntil { router.refreshAccountDataCallCount > initialRefreshes }
        let summary = StatisticsSummary(playedQuizzes: 2, correctAnswers: 9, totalQuestions: 10,
                                        bestCorrectAnswers: 5, bestTotalQuestions: 5)
        statistics.applySyncResponse(.init(summary: summary, acceptedAttemptIds: [], legacySummaryAccepted: false), for: "remote-player")
        try await waitUntil { controller.expandedStatisticsSummary == summary }
        XCTAssertTrue(controller.homeCardState.isStatisticsPresented)
    }
}
