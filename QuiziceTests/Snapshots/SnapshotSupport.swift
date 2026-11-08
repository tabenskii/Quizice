import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import Quizice

@MainActor
enum SnapshotSupport {
    static let componentSize = CGSize(width: 390, height: 220)
    static let iPhone17Pro = ViewImageConfig(
        safeArea: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0),
        size: CGSize(width: 402, height: 874),
        traits: ViewImageConfig.iPhone13Pro.traits
    )
    static let iPadPortrait = iPadConfiguration(size: CGSize(width: 834, height: 1_194))
    static let iPadLandscape = iPadConfiguration(size: CGSize(width: 1_194, height: 834))
    static let iPadNarrowWindow = iPadConfiguration(size: CGSize(width: 375, height: 1_024))
    static let iPadShortWindow = iPadConfiguration(size: CGSize(width: 900, height: 430))

    private static func iPadConfiguration(size: CGSize) -> ViewImageConfig {
        ViewImageConfig(
            safeArea: UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0),
            size: size,
            traits: UITraitCollection(traitsFrom: [
                UITraitCollection(userInterfaceIdiom: .pad),
                UITraitCollection(horizontalSizeClass: size.width < 600 ? .compact : .regular),
                UITraitCollection(verticalSizeClass: .regular),
                UITraitCollection(displayScale: 2)
            ])
        )
    }
    private static var snapshotRecordMode: SnapshotTestingConfiguration.Record? {
        ProcessInfo.processInfo.environment["QUIZICE_RECORD_SNAPSHOTS"] == "1" ? .all : nil
    }

    static func setUp(
        designStyle: AppDesignStyle = .clean,
        cleanColorScheme: CleanColorSchemePreference = .light,
        language: AppLanguagePreference = .russian
    ) {
        UIView.setAnimationsEnabled(false)
        AppLocalizationStore.shared.languagePreference = language
        UserDefaults.standard.set(designStyle.rawValue, forKey: AppAppearanceStore.Keys.designStyle)
        UserDefaults.standard.set(cleanColorScheme.rawValue, forKey: AppAppearanceStore.Keys.cleanColorScheme)
        UserDefaults.standard.set(AppBackgroundStyle.defaultStyle.rawValue, forKey: AppAppearanceStore.Keys.backgroundStyle)
        UserDefaults.standard.removeObject(forKey: OnboardingProgressStore.Keys.completedVersion)
        UserDefaults.standard.removeObject(forKey: OnboardingProgressStore.Keys.preferredThemeIDs)
#if DEBUG
        UserDefaults.standard.removeObject(forKey: DebugSubscriptionPromoSettings.showPromoKey)
        SubscriptionEntitlementStore.shared.setDebugSubscriptionActive(false)
#endif
        resetLocalizedThemePreferences()
    }

    static func tearDown() {
        UIView.setAnimationsEnabled(true)
        UserDefaults.standard.removeObject(forKey: AppAppearanceStore.Keys.designStyle)
        UserDefaults.standard.removeObject(forKey: AppAppearanceStore.Keys.cleanColorScheme)
        UserDefaults.standard.removeObject(forKey: AppAppearanceStore.Keys.backgroundStyle)
        UserDefaults.standard.removeObject(forKey: AppLocalizationStore.Keys.language)
        UserDefaults.standard.removeObject(forKey: OnboardingProgressStore.Keys.completedVersion)
        UserDefaults.standard.removeObject(forKey: OnboardingProgressStore.Keys.preferredThemeIDs)
#if DEBUG
        UserDefaults.standard.removeObject(forKey: DebugSubscriptionPromoSettings.showPromoKey)
        SubscriptionEntitlementStore.shared.setDebugSubscriptionActive(false)
#endif
        resetLocalizedThemePreferences()
        resetSharedQuizFactoryForTests()
    }

    private static func resetLocalizedThemePreferences() {
        UserDefaults.standard.removeObject(forKey: "quizice.favorites.global.v2")
        UserDefaults.standard.removeObject(
            forKey: OnboardingProgressStore.Keys.legacyPreferencesMigrationLocale
        )
        AppLanguagePreference.allCases.compactMap(\.languageCode).forEach { locale in
            UserDefaults.standard.removeObject(
                forKey: OnboardingProgressStore.Keys.preferredThemeIDs(locale: locale)
            )
            UserDefaults.standard.removeObject(
                forKey: OnboardingProgressStore.Keys.pendingThemePreferences(locale: locale)
            )
        }
    }

    static func assertScreen(
        _ viewController: UIViewController,
        named name: String,
        size: CGSize? = nil,
        device: ViewImageConfig? = nil,
        contentSizeCategory: UIContentSizeCategory? = nil,
        afterPrepare: ((UIViewController) -> Void)? = nil,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        precondition(size == nil || device == nil, "Pass either a canvas size or a device configuration, not both")
        prepare(viewController, size: device?.size ?? size, contentSizeCategory: contentSizeCategory)
        // Some UIKit controls only render state correctly after their final bounds are known.
        afterPrepare?(viewController)
        viewController.view.layoutIfNeeded()
        let snapshotting: Snapshotting<UIViewController, UIImage>
        if let device {
            let displayScale: CGFloat = device.traits.userInterfaceIdiom == .pad
                || device.size == ViewImageConfig.iPhone8.size ? 2 : 3
            let traits = device.traits.modifyingTraits {
                $0.displayScale = displayScale
            }
            snapshotting = .image(on: device, traits: traits)
        } else if let size {
            snapshotting = .image(size: size)
        } else {
            snapshotting = .image(on: .iPhoneX)
        }
        assertSnapshot(
            of: viewController,
            as: snapshotting,
            named: name,
            record: snapshotRecordMode,
            file: file,
            testName: testName,
            line: line
        )
    }

    static func assertComponent(
        _ view: UIView,
        named name: String,
        size: CGSize = CGSize(width: 390, height: 220),
        backgroundAppearance: AppAppearance? = nil,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let viewController = ComponentHostViewController(
            contentView: view,
            canvasSize: size,
            backgroundAppearance: backgroundAppearance
        )
        prepare(viewController, size: size)
        assertSnapshot(
            of: viewController,
            as: .image(size: size),
            named: name,
            record: snapshotRecordMode,
            file: file,
            testName: testName,
            line: line
        )
    }

    static func appearance(
        designStyle: AppDesignStyle,
        cleanColorScheme: CleanColorSchemePreference = .light
    ) -> AppAppearance {
        AppAppearance(
            designStyle: designStyle,
            cleanColorSchemePreference: cleanColorScheme,
            traitCollection: UITraitCollection(userInterfaceStyle: cleanColorScheme == .dark ? .dark : .light)
        )
    }

    static func makeActionButton(
        title: String,
        style: AppSurfaceStyle,
        appearance: AppAppearance,
        textColor: UIColor? = nil
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.applyActionAppearance(style, appearance: appearance, textColor: textColor)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = appearance.typography.button()
        button.heightAnchor.constraint(equalToConstant: 52).isActive = true
        button.widthAnchor.constraint(equalToConstant: 280).isActive = true
        return button
    }

    static func makeCollectionCell(
        item: Int,
        themes: [QuizTheme],
        designStyle: AppDesignStyle = .clean,
        cleanColorScheme: CleanColorSchemePreference = .light,
        collectionWidth: CGFloat = 390,
        feelingLuckyLoading: Bool = false
    ) -> UICollectionViewCell {
        setUp(designStyle: designStyle, cleanColorScheme: cleanColorScheme)
        let repository = SnapshotThemeRepository(themes: themes)
        let suiteName = "SnapshotSupport.collectionCell.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = ThemesCollectionService(
            themeRepository: repository,
            statisticsStore: StatisticsStore(userDefaults: defaults, key: "attempts")
        )
        service.isFeelingLuckyLoading = feelingLuckyLoading
        let collectionView = makeCollectionView(width: collectionWidth)
        collectionView.dataSource = service
        collectionView.delegate = service
        collectionView.layoutIfNeeded()
        let targetCollectionView: UICollectionView
        let targetItem: Int
        if item < themes.count {
            targetCollectionView = makeCollectionView(
                width: max(
                    collectionWidth
                        - ThemesCollectionService.Layout.sectionInsets.left
                        - ThemesCollectionService.Layout.sectionInsets.right,
                    0
                )
            )
            targetCollectionView.accessibilityIdentifier =
                ThemesCollectionService.Content.themeCatalogAccessibilityID
            targetItem = item
        } else {
            targetCollectionView = collectionView
            targetItem = item - themes.count + 1
        }
        let indexPath = IndexPath(item: targetItem, section: 0)
        let cell = service.collectionView(targetCollectionView, cellForItemAt: indexPath)
        cell.frame = CGRect(origin: .zero, size: service.collectionView(
            targetCollectionView,
            layout: targetCollectionView.collectionViewLayout,
            sizeForItemAt: indexPath
        ))
        cell.contentView.frame = cell.bounds
        cell.setNeedsLayout()
        cell.layoutIfNeeded()
        cell.contentView.layoutIfNeeded()
        return cell
    }

    static func makeTheme(
        id: String,
        name: String,
        description: String = "Synthetic snapshot theme",
        sfSymbolName: String? = nil,
        emoji: String = QuizTheme.defaultEmoji,
        colorHex: String? = nil,
        source: QuizThemeSource = .catalog,
        questions: [QuizQuestion] = [
            QuizQuestion(
                question: "Question?",
                answers: ["A", "B", "C", "D"],
                correctAnswer: "A"
            )
        ]
    ) -> QuizTheme {
        let resolvedSymbol = sfSymbolName ?? [
            "music": "music.note.list",
            "technology": "cpu.fill",
            "history_culture": "theatermask.and.paintbrush.fill",
            "politics_business": "briefcase.fill"
        ][id] ?? QuizTheme.defaultSFSymbolName
        let resolvedEmoji = emoji == QuizTheme.defaultEmoji ? [
            "music": "🎵",
            "technology": "💻",
            "history_culture": "🏛️",
            "politics_business": "💼"
        ][id] ?? emoji : emoji
        let resolvedColorHex = colorHex ?? [
            "music": "#FF8252",
            "technology": "#62A2E6",
            "history_culture": "#8B5CF6",
            "politics_business": "#F2C94C"
        ][id]
        return QuizTheme(
            id: id,
            theme: name,
            themeDescription: description,
            questions: questions,
            sfSymbolName: resolvedSymbol,
            emoji: resolvedEmoji,
            colorHex: resolvedColorHex,
            source: source
        )
    }

    private static func prepare(
        _ viewController: UIViewController,
        size: CGSize? = nil,
        contentSizeCategory: UIContentSizeCategory? = nil
    ) {
        if let contentSizeCategory {
            viewController.traitOverrides.preferredContentSizeCategory = contentSizeCategory
        }
        viewController.loadViewIfNeeded()
        if let size {
            viewController.view.frame = CGRect(origin: .zero, size: size)
        }
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()
    }

    private static func makeCollectionView(width: CGFloat) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: width, height: 844),
            collectionViewLayout: layout
        )
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: ThemesCollectionService.Content.themeCellReuseIdentifier)
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
        return collectionView
    }
}

@MainActor
final class ComponentHostViewController: UIViewController {
    private let contentView: UIView
    private let canvasSize: CGSize
    private let backgroundAppearance: AppAppearance?

    init(contentView: UIView, canvasSize: CGSize, backgroundAppearance: AppAppearance? = nil) {
        self.contentView = contentView
        self.canvasSize = canvasSize
        self.backgroundAppearance = backgroundAppearance
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let rootView = UIView(frame: CGRect(origin: .zero, size: canvasSize))
        let appearance = backgroundAppearance ?? AppAppearanceStore.shared.appearance(compatibleWith: rootView.traitCollection)
        appearance.applyBackground(to: rootView)
        rootView.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        var constraints = [
            contentView.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            contentView.centerYAnchor.constraint(equalTo: rootView.centerYAnchor)
        ]
        if contentView.bounds.width > 0 {
            constraints.append(contentView.widthAnchor.constraint(equalToConstant: contentView.bounds.width))
        }
        if contentView.bounds.height > 0 {
            constraints.append(contentView.heightAnchor.constraint(equalToConstant: contentView.bounds.height))
        }
        NSLayoutConstraint.activate(constraints)
        view = rootView
    }
}

final class SnapshotThemeRepository: ThemeRepository {
    var themes: [QuizTheme]?

    init(themes: [QuizTheme]) {
        self.themes = themes
    }

    func loadData(forceReload: Bool) {}

    func fetchQuizThemes() -> [QuizTheme] {
        themes ?? []
    }
}

func resetSharedQuizFactoryForTests() {
    QuizFactory.shared.themes = nil
    QuizFactory.shared.chosenTheme = nil
    QuizFactory.shared.questionsCount = 5
    QuizFactory.shared.startup1st = false
}

extension UIView {
    func snapshotDescendant(withAccessibilityIdentifier identifier: String) -> UIView? {
        if accessibilityIdentifier == identifier {
            return self
        }
        for subview in subviews {
            if let match = subview.snapshotDescendant(withAccessibilityIdentifier: identifier) {
                return match
            }
        }
        return nil
    }
}
