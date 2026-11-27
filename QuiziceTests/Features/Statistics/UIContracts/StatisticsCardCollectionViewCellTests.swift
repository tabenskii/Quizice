import XCTest
@testable import Quizice

@MainActor
final class StatisticsCardCollectionViewCellTests: XCTestCase {
    private var userDefaultsSuiteNames: [String] = []

    override func setUp() {
        super.setUp()
#if DEBUG
        UserDefaults.standard.removeObject(forKey: DebugSubscriptionPromoSettings.showPromoKey)
#endif
        AppLocalizationStore.shared.languagePreference = .russian
        UserDefaults.standard.set(
            AppDesignStyle.clean.rawValue,
            forKey: AppAppearanceStore.Keys.designStyle
        )
        UserDefaults.standard.set(
            CleanColorSchemePreference.light.rawValue,
            forKey: AppAppearanceStore.Keys.cleanColorScheme
        )
        QuizFactory.shared.themes = []
    }

    override func tearDown() {
        userDefaultsSuiteNames.forEach {
            UserDefaults.standard.removePersistentDomain(forName: $0)
        }
        userDefaultsSuiteNames.removeAll()
        QuizFactory.shared.themes = []
        UserDefaults.standard.removeObject(forKey: AppLocalizationStore.Keys.language)
        UserDefaults.standard.removeObject(forKey: AppAppearanceStore.Keys.designStyle)
        UserDefaults.standard.removeObject(forKey: AppAppearanceStore.Keys.cleanColorScheme)
#if DEBUG
        UserDefaults.standard.removeObject(forKey: DebugSubscriptionPromoSettings.showPromoKey)
#endif
        super.tearDown()
    }

    func testCollectionServiceDequeuesRegisteredReusableStatisticsCellWithCurrentSummary() throws {
        let store = makeStatisticsStore()
        store.recordAttempt(correctAnswers: 3, totalQuestions: 5)
        store.recordAttempt(correctAnswers: 5, totalQuestions: 5)
        let service = ThemesCollectionService(statisticsStore: store)
        let collectionView = makeCollectionView(service: service)
        let statisticsIndexPath = IndexPath(item: 3, section: 0)

        collectionView.reloadData()
        collectionView.layoutIfNeeded()

        let cell = try XCTUnwrap(
            collectionView.cellForItem(at: statisticsIndexPath) as? StatisticsCardCollectionViewCell
        )
        let playedValueLabel = try XCTUnwrap(
            cell.contentView.descendant(
                withAccessibilityIdentifier: ThemesCollectionService.Content.statisticsPlayedValueAccessibilityID
            ) as? UILabel
        )
        let accuracyValueLabel = try XCTUnwrap(
            cell.contentView.descendant(
                withAccessibilityIdentifier: ThemesCollectionService.Content.statisticsAccuracyValueAccessibilityID
            ) as? UILabel
        )

        XCTAssertEqual(cell.reuseIdentifier, StatisticsCardCollectionViewCell.reuseIdentifier)
        XCTAssertEqual(cell.actionButton.accessibilityIdentifier, ThemesCollectionService.Content.statisticsAccessibilityID)
        XCTAssertEqual(playedValueLabel.text, "2")
        XCTAssertEqual(accuracyValueLabel.text, "80%")
        XCTAssertEqual(
            cell.actionButton.accessibilityValue,
            L10n.Home.statisticsAccessibilityValue(playedQuizzes: 2, percentage: 80)
        )
    }

    func testPrefetchedStatisticsCellReadsCurrentAccountSummaryBeforeDisplay() throws {
        let store = makeStatisticsStore()
        let service = ThemesCollectionService(statisticsStore: store)
        let collectionView = makeCollectionView(service: service)
        let indexPath = IndexPath(item: 3, section: 0)
        let cell = service.collectionView(collectionView, cellForItemAt: indexPath)
        let played = try XCTUnwrap(cell.contentView.descendant(
            withAccessibilityIdentifier: ThemesCollectionService.Content.statisticsPlayedValueAccessibilityID
        ) as? UILabel)
        XCTAssertEqual(played.text, "0")
        store.activateAuthenticatedUser("player")
        store.recordAttempt(correctAnswers: 4, totalQuestions: 5)

        service.collectionView(collectionView, willDisplay: cell, forItemAt: indexPath)

        XCTAssertEqual(played.text, "1")
        let accuracy = cell.contentView.descendant(
            withAccessibilityIdentifier: ThemesCollectionService.Content.statisticsAccuracyValueAccessibilityID
        ) as? UILabel
        XCTAssertEqual(accuracy?.text, "80%")
        store.activateGuest()
        service.collectionView(collectionView, willDisplay: cell, forItemAt: indexPath)
        XCTAssertEqual(played.text, "0")
    }

    func testPresentedStatisticsStateReconfiguresOnlyItsSourceVisibility() throws {
        let service = ThemesCollectionService(statisticsStore: makeStatisticsStore())
        let collectionView = makeCollectionView(service: service)
        let statisticsIndexPath = IndexPath(item: 3, section: 0)

        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        let initialCell = try XCTUnwrap(
            collectionView.cellForItem(at: statisticsIndexPath) as? StatisticsCardCollectionViewCell
        )
        XCTAssertFalse(initialCell.actionButton.isHidden)
        XCTAssertTrue(initialCell.actionButton.isUserInteractionEnabled)
        XCTAssertFalse(initialCell.actionButton.accessibilityElementsHidden)

        service.isStatisticsPresented = true
        collectionView.layoutIfNeeded()

        let hiddenCell = try XCTUnwrap(
            collectionView.cellForItem(at: statisticsIndexPath) as? StatisticsCardCollectionViewCell
        )
        XCTAssertTrue(hiddenCell.actionButton.isHidden)
        XCTAssertFalse(hiddenCell.actionButton.isUserInteractionEnabled)
        XCTAssertTrue(hiddenCell.actionButton.accessibilityElementsHidden)

        service.isStatisticsPresented = false
        collectionView.layoutIfNeeded()

        let restoredCell = try XCTUnwrap(
            collectionView.cellForItem(at: statisticsIndexPath) as? StatisticsCardCollectionViewCell
        )
        XCTAssertFalse(restoredCell.actionButton.isHidden)
        XCTAssertTrue(restoredCell.actionButton.isUserInteractionEnabled)
        XCTAssertFalse(restoredCell.actionButton.accessibilityElementsHidden)
    }

    func testMetricsWrapOnNarrowCardsWithLargestDynamicType() throws {
        let width: CGFloat = 250
        let appearance = currentAppearance()
        let traits = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        let height = StatisticsCardCollectionViewCell.height(width: width, appearance: appearance, traits: traits)
        let cell = StatisticsCardCollectionViewCell(frame: CGRect(x: 0, y: 0, width: width, height: height))
        cell.configure(
            summary: StatisticsSummary(
                playedQuizzes: 888,
                correctAnswers: 100,
                totalQuestions: 100,
                bestCorrectAnswers: 5,
                bestTotalQuestions: 5
            ),
            appearance: appearance,
            traits: traits,
            width: width,
            bottomInset: 0,
            isSourceHidden: false
        )
        cell.layoutIfNeeded()
        cell.actionButton.layoutIfNeeded()

        XCTAssertEqual(cell.actionButton.bounds.width, width, accuracy: 0.5)
        let heading = try XCTUnwrap(cell.contentView.descendant(
            withAccessibilityIdentifier: ThemesCollectionService.Content.statisticsTitleAccessibilityID
        ) as? UILabel)
        XCTAssertEqual(heading.text, L10n.Statistics.title)
        XCTAssertLessThanOrEqual(
            heading.sizeThatFits(CGSize(width: heading.bounds.width, height: .greatestFiniteMagnitude)).height,
            heading.bounds.height + 0.5
        )

        let metricIdentifiers = [
            (ThemesCollectionService.Content.statisticsPlayedTitleAccessibilityID,
             ThemesCollectionService.Content.statisticsPlayedValueAccessibilityID),
            (ThemesCollectionService.Content.statisticsAccuracyTitleAccessibilityID,
             ThemesCollectionService.Content.statisticsAccuracyValueAccessibilityID)
        ]
        for (titleID, valueID) in metricIdentifiers {
            let title = try XCTUnwrap(cell.contentView.descendant(withAccessibilityIdentifier: titleID) as? UILabel)
            let value = try XCTUnwrap(cell.contentView.descendant(withAccessibilityIdentifier: valueID) as? UILabel)
            let titleFrame = title.convert(title.bounds, to: cell.actionButton)
            let valueFrame = value.convert(value.bounds, to: cell.actionButton)

            XCTAssertGreaterThan(title.font.pointSize, 16)
            XCTAssertGreaterThan(value.font.pointSize, 18)
            XCTAssertTrue(cell.actionButton.bounds.contains(titleFrame))
            XCTAssertTrue(cell.actionButton.bounds.contains(valueFrame))
            XCTAssertFalse(titleFrame.intersects(valueFrame))
            XCTAssertLessThanOrEqual(
                title.sizeThatFits(CGSize(width: title.bounds.width, height: .greatestFiniteMagnitude)).height,
                title.bounds.height + 0.5
            )
        }
    }

    func testPrepareForReuseFullyRestoresStatisticsCellContract() throws {
        let cell = StatisticsCardCollectionViewCell(
            frame: CGRect(x: 0, y: 0, width: 342, height: 136)
        )
        cell.contentView.frame = cell.bounds
        cell.configure(
            summary: StatisticsSummary(
                playedQuizzes: 2,
                correctAnswers: 8,
                totalQuestions: 10,
                bestCorrectAnswers: 5,
                bestTotalQuestions: 5
            ),
            appearance: currentAppearance(),
            traits: UITraitCollection(preferredContentSizeCategory: .large),
            width: 342,
            bottomInset: 24,
            isSourceHidden: true
        )
        let target = StatisticsCellTargetSpy()
        cell.actionButton.addTarget(target, action: #selector(StatisticsCellTargetSpy.tapped), for: .touchUpInside)
        cell.actionButton.isEnabled = false
        cell.actionButton.alpha = 0.4
        cell.actionButton.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)

        cell.prepareForReuse()

        XCTAssertFalse(cell.actionButton.isHidden)
        XCTAssertTrue(cell.actionButton.isEnabled)
        XCTAssertTrue(cell.actionButton.isUserInteractionEnabled)
        XCTAssertFalse(cell.actionButton.accessibilityElementsHidden)
        XCTAssertEqual(cell.actionButton.alpha, 1)
        XCTAssertEqual(cell.actionButton.transform, .identity)
        XCTAssertEqual(cell.actionButton.layer.borderWidth, 0)
        XCTAssertEqual(cell.actionButton.layer.cornerRadius, 0)
        XCTAssertNil(cell.actionButton.accessibilityIdentifier)
        XCTAssertNil(cell.actionButton.accessibilityLabel)
        XCTAssertNil(cell.actionButton.accessibilityHint)
        XCTAssertNil(cell.actionButton.accessibilityValue)
        XCTAssertTrue(cell.actionButton.allTargets.isEmpty)

        let labelIdentifiers = [
            ThemesCollectionService.Content.statisticsTitleAccessibilityID,
            ThemesCollectionService.Content.statisticsPlayedTitleAccessibilityID,
            ThemesCollectionService.Content.statisticsPlayedValueAccessibilityID,
            ThemesCollectionService.Content.statisticsAccuracyTitleAccessibilityID,
            ThemesCollectionService.Content.statisticsAccuracyValueAccessibilityID
        ]
        for identifier in labelIdentifiers {
            let label = try XCTUnwrap(
                cell.contentView.descendant(withAccessibilityIdentifier: identifier) as? UILabel
            )
            XCTAssertNil(label.text)
            XCTAssertEqual(label.textColor, UILabel().textColor)
        }
    }

    private func makeCollectionView(service: ThemesCollectionService) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 500),
            collectionViewLayout: layout
        )
        collectionView.register(
            UICollectionViewCell.self,
            forCellWithReuseIdentifier: ThemesCollectionService.Content.themeCellReuseIdentifier
        )
        collectionView.register(
            ThemeCardCollectionViewCell.self,
            forCellWithReuseIdentifier: ThemeCardCollectionViewCell.reuseIdentifier
        )
        collectionView.register(
            ThemesViewportCollectionViewCell.self,
            forCellWithReuseIdentifier: ThemesViewportCollectionViewCell.reuseIdentifier
        )
        collectionView.register(
            StatisticsCardCollectionViewCell.self,
            forCellWithReuseIdentifier: StatisticsCardCollectionViewCell.reuseIdentifier
        )
        collectionView.register(
            SubscriptionPromoBannerCollectionViewCell.self,
            forCellWithReuseIdentifier: SubscriptionPromoBannerCollectionViewCell.reuseIdentifier
        )
        collectionView.dataSource = service
        collectionView.delegate = service
        return collectionView
    }

    private func makeStatisticsStore() -> StatisticsStore {
        let suiteName = "StatisticsCardCollectionViewCellTests.\(UUID().uuidString)"
        userDefaultsSuiteNames.append(suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return StatisticsStore(userDefaults: defaults)
    }

    private func currentAppearance() -> AppAppearance {
        AppAppearanceStore.shared.appearance(
            compatibleWith: UITraitCollection(userInterfaceStyle: .light)
        )
    }
}
