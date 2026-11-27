import SwiftUI
import XCTest
@testable import Quizice

@MainActor
final class HomeCollectionServicePresentationTests: HomeScreenVisualStateTestCase {
    func testAIActionCardDoesNotReserveAnEmptyAccessibilityPanel() throws {
        for width: CGFloat in [320, 375] {
            for hasPlus in [false, true] {
                let (_, size) = try makeAIActionCard(
                    width: width, category: .accessibilityMedium, hasPlus: hasPlus
                )
                XCTAssertGreaterThanOrEqual(size.height, 72)
                XCTAssertLessThan(size.height, 140, "The first accessibility size should fit the actual text compactly")
            }
        }
    }

    func testAIActionCardHeightRespondsToAvailableWidthAndSubscriberText() throws {
        let (_, narrowFreeSize) = try makeAIActionCard(
            width: 320, category: .accessibilityExtraExtraExtraLarge, hasPlus: false
        )
        let (_, wideFreeSize) = try makeAIActionCard(
            width: 600, category: .accessibilityExtraExtraExtraLarge, hasPlus: false
        )
        let (_, narrowPlusSize) = try makeAIActionCard(
            width: 320, category: .accessibilityExtraExtraExtraLarge, hasPlus: true
        )

        XCTAssertGreaterThan(narrowFreeSize.height, wideFreeSize.height, "A wrapped title needs more room")
        XCTAssertGreaterThan(narrowPlusSize.height, narrowFreeSize.height, "Plus must reserve room for its visible subtitle")
    }

    func testRadarAIShadowTracksFinalCardBoundsAfterResizing() throws {
        useDesignStyle(.radar)
        let (cell, _) = try makeAIActionCard(width: 375, category: .large, hasPlus: false)
        let button = try XCTUnwrap(cell.contentView.descendant(
            withAccessibilityIdentifier: "homeCreateWithAIButton"
        ) as? UIButton)
        for size in [CGSize(width: 600, height: 110), CGSize(width: 280, height: 72)] {
            cell.frame.size = size
            cell.contentView.frame = cell.bounds
            cell.setNeedsLayout()
            cell.layoutIfNeeded()
            cell.contentView.layoutIfNeeded()
            button.layoutIfNeeded()
            XCTAssertEqual(button.layer.shadowPath?.boundingBoxOfPath, button.bounds)
            XCTAssertNil(button.layer.animation(forKey: "shadowPath"))
        }
    }

    func testAIActionCardSizingUsesExplicitTraitsInsteadOfAmbientCategory() {
        let service = ThemesCollectionService()
        service.hasActivePlusSubscription = true
        let large = UITraitCollection(preferredContentSizeCategory: .large)
        let accessible = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        var accessibleHeightInLargeContext: CGFloat = 0
        var accessibleHeightInMatchingContext: CGFloat = 0
        var largeHeightInAccessibleContext: CGFloat = 0

        large.performAsCurrent {
            accessibleHeightInLargeContext = service.aiThemeCardHeight(width: 327, traits: accessible)
        }
        accessible.performAsCurrent {
            accessibleHeightInMatchingContext = service.aiThemeCardHeight(width: 327, traits: accessible)
            largeHeightInAccessibleContext = service.aiThemeCardHeight(width: 327, traits: large)
        }

        XCTAssertGreaterThan(accessibleHeightInLargeContext, 72)
        XCTAssertEqual(accessibleHeightInLargeContext, accessibleHeightInMatchingContext, accuracy: 0.5)
        XCTAssertEqual(largeHeightInAccessibleContext, 72, accuracy: 0.5)
    }

    func testAIActionCardFittedHeightContainsTextAndPreservesBadgeAndGradient() throws {
        let categories: [UIContentSizeCategory] = [.large, .extraExtraLarge, .accessibilityMedium, .accessibilityExtraExtraExtraLarge]
        for style in [AppDesignStyle.classic, .clean, .radar] {
            useDesignStyle(style)
            for category in categories {
                for hasPlus in [false, true] {
                    let (cell, size) = try makeAIActionCard(width: 375, category: category, hasPlus: hasPlus)
                    let title = try XCTUnwrap(cell.contentView.descendant(
                        withAccessibilityIdentifier: "homeCreateWithAITitle"
                    ) as? UILabel)
                    let subtitle = try XCTUnwrap(cell.contentView.descendant(
                        withAccessibilityIdentifier: "homeCreateWithAISubtitle"
                    ) as? UILabel)
                    let button = try XCTUnwrap(cell.contentView.descendant(
                        withAccessibilityIdentifier: "homeCreateWithAIButton"
                    ) as? UIButton)
                    let badge = cell.contentView.descendant(withAccessibilityIdentifier: "homeCreateWithAIBadge") as? UILabel
                    let traits = UITraitCollection(preferredContentSizeCategory: category)
                    let expectedFont = AppAppearanceStore.shared.appearance(compatibleWith: traits).typography.font(
                        size: 18, weight: .semibold, compatibleWith: traits
                    )

                    XCTAssertEqual(title.font.pointSize, expectedFont.pointSize, accuracy: 0.01)
                    XCTAssertEqual(subtitle.isHidden, !hasPlus)
                    XCTAssertEqual(button.accessibilityValue, hasPlus ? L10n.Subscription.aiCardSubtitle : nil)
                    XCTAssertEqual(badge == nil, category.isAccessibilityCategory)
                    if let badge {
                        XCTAssertEqual(badge.text, (hasPlus ? L10n.Subscription.plus : L10n.Subscription.freeBadge).uppercased())
                        XCTAssertLessThanOrEqual(badge.intrinsicContentSize.width, badge.bounds.width + 0.5)
                    }
                    XCTAssertEqual(
                        cell.contentView.descendant(withAccessibilityIdentifier: "homeCreateWithAIGradientBorder") != nil,
                        style != .radar
                    )
                    if category == .large {
                        XCTAssertEqual(size.height, 72, accuracy: 0.5)
                    }
                    for label in [title, subtitle] where !label.isHidden {
                        let frame = label.convert(label.bounds, to: button)
                        XCTAssertGreaterThan(label.bounds.width, 0)
                        XCTAssertGreaterThanOrEqual(frame.minY, 7.5)
                        XCTAssertLessThanOrEqual(frame.maxY, button.bounds.height - 7.5)
                        XCTAssertLessThanOrEqual(
                            label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)).height,
                            label.bounds.height + 0.5,
                            "The visible text must fit at \(category.rawValue), style=\(style), Plus=\(hasPlus)"
                        )
                    }
                }
            }
        }
    }

    func testAIActionCardDisplaysLocalizedFreeBadgeOnNarrowPhones() throws {
        let localizedTitles: [(AppLanguagePreference, String)] = [
            (.russian, "БЕСПЛАТНО"),
            (.english, "FREE"),
            (.german, "KOSTENLOS"),
            (.french, "GRATUIT"),
            (.spanish, "GRATIS"),
            (.italian, "GRATIS")
        ]

        for (language, expectedTitle) in localizedTitles {
            AppLocalizationStore.shared.languagePreference = language
            let (cell, _) = try makeAIActionCard(width: 320, category: .large, hasPlus: false)
            let badge = try XCTUnwrap(cell.contentView.descendant(
                withAccessibilityIdentifier: ThemesCollectionService.Content.aiThemeBadgeAccessibilityID
            ) as? UILabel)
            let title = try XCTUnwrap(cell.contentView.descendant(
                withAccessibilityIdentifier: ThemesCollectionService.Content.aiThemeTitleAccessibilityID
            ) as? UILabel)
            let button = try XCTUnwrap(cell.contentView.descendant(
                withAccessibilityIdentifier: ThemesCollectionService.Content.aiThemeAccessibilityID
            ) as? UIButton)

            XCTAssertEqual(badge.text, expectedTitle)
            XCTAssertLessThanOrEqual(badge.intrinsicContentSize.width, badge.bounds.width + 0.5)
            XCTAssertTrue(button.bounds.contains(badge.convert(badge.bounds, to: button)))
            XCTAssertLessThan(title.convert(title.bounds, to: button).maxX, badge.frame.minX)
        }
    }

    private func makeAIActionCard(
        width: CGFloat,
        category: UIContentSizeCategory,
        hasPlus: Bool
    ) throws -> (UICollectionViewCell, CGSize) {
        let service = ThemesCollectionService()
        service.hasActivePlusSubscription = hasPlus
        let collectionView = makeCollectionView(width: width)
        let host = UIViewController()
        host.view.addSubview(collectionView)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        testWindows.append(window)
        collectionView.traitOverrides.preferredContentSizeCategory = category
        collectionView.updateTraitsIfNeeded()
        window.layoutIfNeeded()
        collectionView.layoutIfNeeded()
        XCTAssertEqual(collectionView.traitCollection.preferredContentSizeCategory, category)
        let indexPath = IndexPath(item: 1, section: 0)
        let size = service.collectionView(collectionView, layout: collectionView.collectionViewLayout, sizeForItemAt: indexPath)
        let cell = service.collectionView(collectionView, cellForItemAt: indexPath)
        cell.frame = CGRect(origin: .zero, size: size)
        cell.contentView.frame = cell.bounds
        collectionView.addSubview(cell)
        cell.updateTraitsIfNeeded()
        cell.layoutIfNeeded()
        cell.contentView.layoutIfNeeded()
        XCTAssertEqual(cell.traitCollection.preferredContentSizeCategory, category)
        return (cell, size)
    }

    func testCleanDarkThemeCardsRemainShadowless() {
        useDesignStyle(.clean)
        UserDefaults.standard.set(
            CleanColorSchemePreference.dark.rawValue,
            forKey: AppAppearanceStore.Keys.cleanColorScheme
        )
        QuizFactory.shared.themes = [makeTheme(name: "Музыка")]

        let service = ThemesCollectionService()
        let themeCell = service.collectionView(
            makeThemeCollectionView(),
            cellForItemAt: IndexPath(item: 0, section: 0)
        )

        XCTAssertEqual(themeCell.layer.shadowOpacity, 0)
    }

    func testCompactStatisticsTitleCanWrapAndLastItemOwnsBottomSpacing() throws {
        useDesignStyle(.clean)
        QuizFactory.shared.themes = [makeTheme(name: "Музыка")]
        let service = ThemesCollectionService()
        let collectionView = makeCollectionView(width: 320)
        let indexPath = IndexPath(item: 3, section: 0)
        let itemSize = service.collectionView(
            collectionView,
            layout: collectionView.collectionViewLayout,
            sizeForItemAt: indexPath
        )
        let statisticsCell = service.collectionView(collectionView, cellForItemAt: indexPath)
        statisticsCell.frame = CGRect(origin: .zero, size: itemSize)
        statisticsCell.contentView.frame = statisticsCell.bounds
        statisticsCell.layoutIfNeeded()
        statisticsCell.contentView.layoutIfNeeded()

        let statisticsButton = try XCTUnwrap(
            statisticsCell.contentView.descendant(withAccessibilityIdentifier: "homeStatisticsCard") as? UIButton
        )
        let titleLabel = try XCTUnwrap(
            statisticsCell.contentView.descendant(withAccessibilityIdentifier: "homeStatisticsTitleLabel") as? UILabel
        )
        let heading = try XCTUnwrap(titleLabel.superview)
        let playedTitleLabel = try XCTUnwrap(
            statisticsCell.contentView.descendant(withAccessibilityIdentifier: "homeStatisticsPlayedTitleLabel") as? UILabel
        )
        let metrics = try XCTUnwrap(playedTitleLabel.superview?.superview)
        let headingFrame = heading.convert(heading.bounds, to: statisticsButton)
        let metricsFrame = metrics.convert(metrics.bounds, to: statisticsButton)
        let sectionInsets = service.collectionView(
            collectionView,
            layout: collectionView.collectionViewLayout,
            insetForSectionAt: 0
        )

        XCTAssertEqual(itemSize.height, statisticsButton.frame.height + 24, accuracy: 0.5)
        XCTAssertLessThanOrEqual(statisticsButton.frame.height, 118)
        XCTAssertEqual(metricsFrame.minY - headingFrame.maxY, 12, accuracy: 0.5)
        XCTAssertEqual(statisticsCell.bounds.maxY - statisticsButton.frame.maxY, 24, accuracy: 0.5)
        XCTAssertEqual(sectionInsets.bottom, 0)
        XCTAssertEqual(titleLabel.numberOfLines, 0)
        XCTAssertFalse(titleLabel.adjustsFontSizeToFitWidth)
        XCTAssertGreaterThan(titleLabel.bounds.width, 0)
    }

    func testCollectionServiceRendersEmptyStatisticsSummaryOnHomeCard() throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка")]
        let statisticsStore = makeStatisticsStore()
        let service = ThemesCollectionService(statisticsStore: statisticsStore)
        let collectionView = makeCollectionView()

        let indexPath = IndexPath(item: 3, section: 0)
        let itemSize = service.collectionView(
            collectionView,
            layout: collectionView.collectionViewLayout,
            sizeForItemAt: indexPath
        )
        let statisticsCell = service.collectionView(collectionView, cellForItemAt: indexPath)
        statisticsCell.frame = CGRect(origin: .zero, size: itemSize)
        statisticsCell.contentView.frame = statisticsCell.bounds
        statisticsCell.layoutIfNeeded()
        statisticsCell.contentView.layoutIfNeeded()
        let statisticsButton = try XCTUnwrap(statisticsCell.contentView.descendant(withAccessibilityIdentifier: "homeStatisticsCard") as? UIButton)
        let statisticsTitleLabel = try XCTUnwrap(statisticsCell.contentView.descendant(withAccessibilityIdentifier: "homeStatisticsTitleLabel") as? UILabel)
        let playedTitleLabel = try XCTUnwrap(statisticsCell.contentView.descendant(withAccessibilityIdentifier: "homeStatisticsPlayedTitleLabel") as? UILabel)
        let playedValueLabel = try XCTUnwrap(statisticsCell.contentView.descendant(withAccessibilityIdentifier: "homeStatisticsPlayedValueLabel") as? UILabel)
        let accuracyTitleLabel = try XCTUnwrap(statisticsCell.contentView.descendant(withAccessibilityIdentifier: "homeStatisticsAccuracyTitleLabel") as? UILabel)
        let accuracyValueLabel = try XCTUnwrap(statisticsCell.contentView.descendant(withAccessibilityIdentifier: "homeStatisticsAccuracyValueLabel") as? UILabel)

        XCTAssertEqual(playedTitleLabel.text, L10n.Home.statisticsPlayedShort)
        XCTAssertEqual(playedTitleLabel.numberOfLines, 0)
        XCTAssertEqual(playedValueLabel.text, "0")
        XCTAssertEqual(accuracyTitleLabel.text, L10n.Home.statisticsAccuracyShort)
        XCTAssertEqual(accuracyValueLabel.text, "0%")
        XCTAssertFalse(statisticsTitleLabel.adjustsFontSizeToFitWidth)
        XCTAssertLessThan(statisticsButton.frame.height, 96)
        XCTAssertEqual(statisticsCell.bounds.maxY - statisticsButton.frame.maxY, 24, accuracy: 0.5)
        let playedRowStack = try XCTUnwrap(playedTitleLabel.superview as? UIStackView)
        let accuracyRowStack = try XCTUnwrap(accuracyTitleLabel.superview as? UIStackView)
        let metricsStack = try XCTUnwrap(playedRowStack.superview as? UIStackView)
        XCTAssertTrue(playedRowStack === playedValueLabel.superview)
        XCTAssertTrue(accuracyRowStack === accuracyValueLabel.superview)
        XCTAssertTrue(metricsStack === accuracyRowStack.superview)
        XCTAssertLessThanOrEqual(
            playedTitleLabel.sizeThatFits(
                CGSize(width: .greatestFiniteMagnitude, height: playedTitleLabel.bounds.height)
            ).width,
            playedTitleLabel.bounds.width + 0.5
        )
        XCTAssertEqual(playedRowStack.axis, .horizontal)
        XCTAssertEqual(accuracyRowStack.axis, .horizontal)
        XCTAssertEqual(metricsStack.axis, .horizontal)
        XCTAssertEqual(playedRowStack.arrangedSubviews, [playedTitleLabel, playedValueLabel])
        XCTAssertEqual(accuracyRowStack.arrangedSubviews, [accuracyTitleLabel, accuracyValueLabel])
        XCTAssertEqual(playedRowStack.frame.width, accuracyRowStack.frame.width, accuracy: 0.5)
        XCTAssertEqual(
            statisticsButton.accessibilityValue,
            L10n.Home.statisticsAccessibilityValue(playedQuizzes: 0, percentage: 0)
        )
    }

    func testCollectionServiceRendersRecordedStatisticsSummaryOnHomeCard() throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка")]
        let statisticsStore = makeStatisticsStore(attempts: [
            (correctAnswers: 3, totalQuestions: 5),
            (correctAnswers: 5, totalQuestions: 5)
        ])
        let service = ThemesCollectionService(statisticsStore: statisticsStore)
        let collectionView = makeCollectionView()

        let statisticsCell = service.collectionView(collectionView, cellForItemAt: IndexPath(item: 3, section: 0))
        let statisticsButton = try XCTUnwrap(statisticsCell.contentView.descendant(withAccessibilityIdentifier: "homeStatisticsCard") as? UIButton)
        let playedValueLabel = try XCTUnwrap(statisticsCell.contentView.descendant(withAccessibilityIdentifier: "homeStatisticsPlayedValueLabel") as? UILabel)
        let accuracyValueLabel = try XCTUnwrap(statisticsCell.contentView.descendant(withAccessibilityIdentifier: "homeStatisticsAccuracyValueLabel") as? UILabel)

        XCTAssertEqual(playedValueLabel.text, "2")
        XCTAssertEqual(accuracyValueLabel.text, "80%")
        XCTAssertEqual(
            statisticsButton.accessibilityValue,
            L10n.Home.statisticsAccessibilityValue(playedQuizzes: 2, percentage: 80)
        )
    }

    func testCollectionServiceUsesRadarGreenThemeCardText() throws {
        UserDefaults.standard.set(AppDesignStyle.radar.rawValue, forKey: AppAppearanceStore.Keys.designStyle)
        QuizFactory.shared.themes = [makeTheme(name: "Музыка")]
        let service = ThemesCollectionService()
        let collectionView = makeCollectionView()
        let themeCollectionView = makeThemeCollectionView()

        let themeCell = service.collectionView(themeCollectionView, cellForItemAt: IndexPath(item: 0, section: 0))
        let aiThemeCell = service.collectionView(collectionView, cellForItemAt: IndexPath(item: 1, section: 0))
        let statisticsCell = service.collectionView(collectionView, cellForItemAt: IndexPath(item: 3, section: 0))
        let imageView = try XCTUnwrap(themeCell.contentView.descendant(withAccessibilityIdentifier: "homeThemeImageView-music") as? UIImageView)
        let titleLabel = try XCTUnwrap(themeCell.contentView.descendant(withAccessibilityIdentifier: "homeThemeTitleLabel-music") as? UILabel)
        let aiThemeButton = try XCTUnwrap(aiThemeCell.contentView.descendant(withAccessibilityIdentifier: "homeCreateWithAIButton") as? UIButton)
        let statisticsButton = try XCTUnwrap(statisticsCell.contentView.descendant(withAccessibilityIdentifier: "homeStatisticsCard") as? UIButton)
        let expectedImage = try XCTUnwrap(
            UIImage(systemName: "music.note.list")?.withRenderingMode(.alwaysTemplate)
        )

        XCTAssertEqual(imageView.image?.pngData(), expectedImage.pngData())
        assertColor(titleLabel.textColor, equals: assetColor("themeRadarGreen"))
        XCTAssertNil(aiThemeCell.contentView.descendant(withAccessibilityIdentifier: "homeCreateWithAIGradientBorder"))
        assertColor(aiThemeButton.backgroundColor, equals: .clear)
        assertColor(
            UIColor(cgColor: aiThemeButton.layer.borderColor ?? UIColor.clear.cgColor),
            equals: assetColor("themeRadarGreen")
        )
        assertColor(
            UIColor(cgColor: aiThemeButton.layer.shadowColor ?? UIColor.clear.cgColor),
            equals: assetColor("themeRadarGreen")
        )
        XCTAssertEqual(aiThemeButton.layer.borderWidth, 1)
        XCTAssertGreaterThan(aiThemeButton.layer.shadowOpacity, 0)
        XCTAssertFalse(aiThemeButton.clipsToBounds)
        assertColor(statisticsButton.backgroundColor, equals: .clear)
    }

    func testCollectionServiceKeepsSelectionContractsForThemeStatisticsAndUnknownButtons() throws {
        QuizFactory.shared.themes = [makeTheme(name: "Музыка")]
        let service = ThemesCollectionService()
        let delegate = ThemeCollectionDelegateSpy()
        service.delegate = delegate

        let themeButton = UIButton(type: .custom)
        themeButton.accessibilityIdentifier = "music"
        let unknownButton = UIButton(type: .custom)
        unknownButton.accessibilityIdentifier = "Неизвестная тема"
        let aiThemeButton = UIButton(type: .system)
        aiThemeButton.accessibilityIdentifier = "homeCreateWithAIButton"
        let subscriptionButton = UIButton(type: .system)
        subscriptionButton.accessibilityIdentifier = "homeSubscriptionPromoBanner"
        let collectionView = makeCollectionView()
        let feelingLuckyCell = service.collectionView(
            collectionView, cellForItemAt: IndexPath(item: service.feelingLuckyIndex, section: 0)
        )
        let feelingLuckyButton = try XCTUnwrap(feelingLuckyCell.contentView.descendant(
            withAccessibilityIdentifier: "homeFeelingLuckyButton"
        ) as? UIButton)
        let fifteenQuestionsButton = try XCTUnwrap(feelingLuckyCell.contentView.descendant(
            withAccessibilityIdentifier: "homeFeelingLuckyButton-15"
        ) as? UIButton)
        let statisticsButton = UIButton(type: .system)
        statisticsButton.accessibilityIdentifier = "homeStatisticsCard"

        service.buttonTouchedUpInside(themeButton)
        service.buttonTouchedUpInside(unknownButton)
        service.aiThemeButtonTouchedUpInside(aiThemeButton)
        service.subscriptionPromoButtonTouchedUpInside(subscriptionButton)
        XCTAssertFalse(fifteenQuestionsButton.isEnabled)
        fifteenQuestionsButton.sendActions(for: .touchUpInside)
        feelingLuckyButton.sendActions(for: .touchUpInside)
        XCTAssertTrue(delegate.feelingLuckyQuestionCounts.isEmpty)
        XCTAssertTrue(fifteenQuestionsButton.isEnabled)
        fifteenQuestionsButton.sendActions(for: .touchUpInside)
        service.statisticsButtonTouchedUpInside(statisticsButton)

        XCTAssertEqual(delegate.selectedThemeIDs, ["music"])
        XCTAssertEqual(delegate.aiThemeTapCount, 1)
        XCTAssertEqual(delegate.subscriptionPromoTapCount, 1)
        XCTAssertEqual(delegate.feelingLuckyQuestionCounts, [15])
        XCTAssertEqual(delegate.statisticsTapCount, 1)
    }

    func testCollectionServiceKeepsStatisticsCardSafeWhenThemesAreEmpty() {
        QuizFactory.shared.themes = []
        let service = ThemesCollectionService()
        let collectionView = makeCollectionView()

        XCTAssertEqual(service.collectionView(collectionView, numberOfItemsInSection: 0), 4)

        let viewportCell = service.collectionView(collectionView, cellForItemAt: IndexPath(item: 0, section: 0))
        let aiThemeCell = service.collectionView(collectionView, cellForItemAt: IndexPath(item: 1, section: 0))
        let feelingLuckyCell = service.collectionView(collectionView, cellForItemAt: IndexPath(item: 2, section: 0))
        let statisticsCell = service.collectionView(collectionView, cellForItemAt: IndexPath(item: 3, section: 0))

        XCTAssertTrue(viewportCell is ThemesViewportCollectionViewCell)
        XCTAssertNotNil(aiThemeCell.contentView.descendant(withAccessibilityIdentifier: "homeCreateWithAIButton"))
        XCTAssertNotNil(feelingLuckyCell.contentView.descendant(withAccessibilityIdentifier: "homeFeelingLuckyCard"))
        XCTAssertNotNil(statisticsCell.contentView.descendant(withAccessibilityIdentifier: "homeStatisticsCard"))
    }
}
