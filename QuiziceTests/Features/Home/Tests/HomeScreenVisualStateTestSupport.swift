import SwiftUI
import XCTest
@testable import Quizice

@MainActor
class HomeScreenVisualStateTestCase: XCTestCase {
    var testWindows: [UIWindow] = []

    override func setUp() {
        super.setUp()
        AIQuizAccessStore.shared.update(isAuthenticated: true)
        AppLocalizationStore.shared.languagePreference = .russian
        resetQuizFactory()
        // Pin the clean color scheme so shadow/surface assertions are deterministic
        // regardless of the host simulator's system light/dark appearance.
        UserDefaults.standard.set(CleanColorSchemePreference.light.rawValue, forKey: AppAppearanceStore.Keys.cleanColorScheme)
        UserDefaults.standard.set(AppDesignStyle.classic.rawValue, forKey: AppAppearanceStore.Keys.designStyle)
        UserDefaults.standard.set(AppBackgroundStyle.defaultStyle.rawValue, forKey: AppAppearanceStore.Keys.backgroundStyle)
        UserDefaults.standard.removeObject(forKey: OnboardingProgressStore.Keys.completedVersion)
        UserDefaults.standard.removeObject(forKey: OnboardingProgressStore.Keys.preferredThemeIDs)
        resetLocalizedThemePreferences()
#if DEBUG
        UserDefaults.standard.removeObject(forKey: DebugSubscriptionPromoSettings.showPromoKey)
        UserDefaults.standard.removeObject(forKey: DebugBackendSettings.useLocalContentOnlyKey)
        UserDefaults.standard.removeObject(forKey: DebugBackendSettings.useLocalhostKey)
        UserDefaults.standard.removeObject(forKey: DebugAIRuntimeSettings.useDirectAIKey)
#endif
    }

    override func tearDown() {
        testWindows = []
        AIQuizAccessStore.shared.update(isAuthenticated: false)
        resetQuizFactory()
        UserDefaults.standard.removeObject(forKey: AppAppearanceStore.Keys.designStyle)
        UserDefaults.standard.removeObject(forKey: AppAppearanceStore.Keys.cleanColorScheme)
        UserDefaults.standard.removeObject(forKey: AppAppearanceStore.Keys.backgroundStyle)
        UserDefaults.standard.removeObject(forKey: AppLocalizationStore.Keys.language)
        UserDefaults.standard.removeObject(forKey: OnboardingProgressStore.Keys.completedVersion)
        UserDefaults.standard.removeObject(forKey: OnboardingProgressStore.Keys.preferredThemeIDs)
        resetLocalizedThemePreferences()
#if DEBUG
        UserDefaults.standard.removeObject(forKey: DebugSubscriptionPromoSettings.showPromoKey)
        UserDefaults.standard.removeObject(forKey: DebugBackendSettings.useLocalContentOnlyKey)
        UserDefaults.standard.removeObject(forKey: DebugBackendSettings.useLocalhostKey)
        UserDefaults.standard.removeObject(forKey: DebugAIRuntimeSettings.useDirectAIKey)
#endif
        super.tearDown()
    }

    func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for Home state")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }


    func makeCollectionView(width: CGFloat = 390) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: width, height: 700),
            collectionViewLayout: layout
        )
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "themeCell")
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

    func makeThemeCollectionView(width: CGFloat = 342) -> UICollectionView {
        let collectionView = makeCollectionView(width: width)
        collectionView.accessibilityIdentifier =
            ThemesCollectionService.Content.themeCatalogAccessibilityID
        return collectionView
    }

    func makeHomeViewController(in frame: CGRect) -> QuizViewController {
        let viewController = QuizViewController()
        let window = UIWindow(frame: frame)
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        testWindows.append(window)
        return viewController
    }

    func makeHostedExpandedThemeCard(
        motionProvider: HomeThemeCardMotionProviding,
        reduceMotionProvider: @escaping () -> Bool = { false }
    ) -> ExpandedThemeCardView {
        let card = ExpandedThemeCardView(
            frame: CGRect(x: 20, y: 126, width: 350, height: 518)
        )
        card.reduceMotionProvider = reduceMotionProvider
        card.deviceParallaxEnabledProvider = { true }
        card.deviceMotionProvider = motionProvider
        card.configure(
            theme: makeTheme(name: "Музыка", questionCount: 5),
            appearance: SnapshotSupport.appearance(designStyle: .clean),
            availableQuestionCounts: [5],
            selectedQuestionCount: 5
        )

        let host = UIViewController()
        host.view.addSubview(card)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        testWindows.append(window)
        return card
    }

    func makeStatisticsStore(
        attempts: [(correctAnswers: Int, totalQuestions: Int)] = []
    ) -> StatisticsStore {
        let suiteName = "ru.avtabenskiy.QuiziceTests.HomeScreenVisualStateTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            let key = "home-statistics-test-\(UUID().uuidString)"
            let store = StatisticsStore(userDefaults: .standard, key: key)
            attempts.forEach { store.recordAttempt(correctAnswers: $0.correctAnswers, totalQuestions: $0.totalQuestions) }
            return store
        }

        userDefaults.removePersistentDomain(forName: suiteName)
        let store = StatisticsStore(userDefaults: userDefaults, key: "home-statistics-test")
        attempts.forEach { store.recordAttempt(correctAnswers: $0.correctAnswers, totalQuestions: $0.totalQuestions) }
        return store
    }

    func makeTheme(
        name: String,
        questionCount: Int = 0,
        description: String = "Synthetic home-screen test theme",
        sfSymbolName: String? = nil,
        emoji: String? = nil,
        colorHex: String? = nil,
        isFavorite: Bool = false
    ) -> QuizTheme {
        let id: String
        switch name {
        case "Музыка":
            id = "music"
        case "Технологии":
            id = "technology"
        case "История", "История и культура":
            id = "history_culture"
        case "Политика", "Политика и бизнес":
            id = "politics_business"
        default:
            id = name
        }
        let questions = (0..<questionCount).map { index in
            QuizQuestion(
                question: "Synthetic question \(index)?",
                answers: ["A", "B", "C", "D"],
                correctAnswer: "A"
            )
        }
        let metadata: (sfSymbol: String, emoji: String, colorHex: String) = switch id {
        case "music": ("music.note.list", "🎵", "#FF8252")
        case "technology": ("cpu.fill", "💻", "#62A2E6")
        case "history_culture": ("theatermask.and.paintbrush.fill", "🏛️", "#8B5CF6")
        case "politics_business": ("briefcase.fill", "💼", "#F2C94C")
        default: (QuizTheme.defaultSFSymbolName, QuizTheme.defaultEmoji, "#7C83FD")
        }
        return QuizTheme(
            id: id,
            theme: name,
            themeDescription: description,
            questions: questions,
            sfSymbolName: sfSymbolName ?? metadata.sfSymbol,
            emoji: emoji ?? metadata.emoji,
            colorHex: colorHex ?? metadata.colorHex,
            isFavorite: isFavorite
        )
    }

    func hitView(in rootView: UIView, for control: UIControl) -> UIView? {
        let center = CGPoint(x: control.bounds.midX, y: control.bounds.midY)
        return rootView.hitTest(control.convert(center, to: rootView), with: nil)
    }

    func parallaxPanGestureRecognizer(in view: UIView) -> UIPanGestureRecognizer? {
        if let recognizer = view.gestureRecognizers?
            .compactMap({ $0 as? UIPanGestureRecognizer })
            .first(where: { $0.name?.contains("ParallaxPan") == true }) {
            return recognizer
        }

        return view.subviews.lazy.compactMap {
            self.parallaxPanGestureRecognizer(in: $0)
        }.first
    }

    func drainAnimations(_ duration: TimeInterval = 0.4) {
        RunLoop.main.run(until: Date().addingTimeInterval(duration))
    }

    func useDesignStyle(_ designStyle: AppDesignStyle) {
        UserDefaults.standard.set(designStyle.rawValue, forKey: AppAppearanceStore.Keys.designStyle)
    }

    func resetQuizFactory() {
        QuizFactory.shared.themes = nil
        QuizFactory.shared.chosenTheme = nil
        QuizFactory.shared.questionsCount = 5
        QuizFactory.shared.startup1st = false
        UserDefaults.standard.removeObject(forKey: AppAppearanceStore.Keys.designStyle)
        UserDefaults.standard.removeObject(forKey: AppAppearanceStore.Keys.cleanColorScheme)
        UserDefaults.standard.removeObject(forKey: AppAppearanceStore.Keys.backgroundStyle)
    }

    private func resetLocalizedThemePreferences() {
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

    func assertColor(_ actual: UIColor?, equals expected: UIColor, file: StaticString = #filePath, line: UInt = #line) {
        guard let actual else {
            XCTFail("Expected color, got nil", file: file, line: line)
            return
        }

        let traitCollection = UITraitCollection(userInterfaceStyle: .light)
        let actualColor = actual.resolvedColor(with: traitCollection)
        let expectedColor = expected.resolvedColor(with: traitCollection)
        var actualRed: CGFloat = 0
        var actualGreen: CGFloat = 0
        var actualBlue: CGFloat = 0
        var actualAlpha: CGFloat = 0
        var expectedRed: CGFloat = 0
        var expectedGreen: CGFloat = 0
        var expectedBlue: CGFloat = 0
        var expectedAlpha: CGFloat = 0

        XCTAssertTrue(actualColor.getRed(&actualRed, green: &actualGreen, blue: &actualBlue, alpha: &actualAlpha), file: file, line: line)
        XCTAssertTrue(expectedColor.getRed(&expectedRed, green: &expectedGreen, blue: &expectedBlue, alpha: &expectedAlpha), file: file, line: line)
        XCTAssertEqual(actualRed, expectedRed, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualGreen, expectedGreen, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualBlue, expectedBlue, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualAlpha, expectedAlpha, accuracy: 0.001, file: file, line: line)
    }

    func assetColor(_ name: String) -> UIColor {
        UIColor(named: name) ?? .clear
    }
}

final class HomeThemeCardMotionProviderFake: HomeThemeCardMotionProviding {
    let isAvailable: Bool
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var isStarted = false

    private var receive: ((HomeThemeCardParallaxInput) -> Void)?

    init(isAvailable: Bool = true) {
        self.isAvailable = isAvailable
    }

    func start(receive: @escaping (HomeThemeCardParallaxInput) -> Void) {
        startCallCount += 1
        isStarted = true
        self.receive = receive
    }

    func stop() {
        stopCallCount += 1
        isStarted = false
        receive = nil
    }

    func send(_ input: HomeThemeCardParallaxInput) {
        receive?(input)
    }
}

final class ThemeCollectionDelegateSpy: ThemeCollectionDelegate {
    private(set) var selectedThemeIDs: [String] = []
    private(set) var aiThemeTapCount = 0
    private(set) var subscriptionPromoTapCount = 0
    private(set) var feelingLuckyTapCount = 0
    private(set) var statisticsTapCount = 0

    func themeButtonTouchedDown(_ sender: UIButton) {}

    func themeButtonTouchedUpInside(_ sender: UIButton, themeID: String) {
        selectedThemeIDs.append(themeID)
    }

    func themeButtonTouchedUpOutside(_ sender: UIButton) {}

    func aiThemeButtonTouchedUpInside(_ sender: UIButton) {
        aiThemeTapCount += 1
    }

    func subscriptionPromoButtonTouchedUpInside(_ sender: UIButton) {
        subscriptionPromoTapCount += 1
    }

    func feelingLuckyButtonTouchedUpInside(_ sender: UIButton) {
        feelingLuckyTapCount += 1
    }

    func statisticsButtonTouchedUpInside(_ sender: UIButton) {
        statisticsTapCount += 1
    }

    func themesCollectionDidScroll(_ scrollView: UIScrollView) {}

}

final class HomeAnalyticsTrackingSpy: AnalyticsTracking {
    private(set) var events: [AnalyticsEvent] = []

    func track(_ event: AnalyticsEvent) {
        events.append(event)
    }

    func reportOperationalError(_ error: Error, context: AnalyticsErrorContext) {}

    func reset() {
        events.removeAll()
    }
}

final class HomeRouterSpy: QuizRouting {
    var onShowQuestion: (() -> Void)?

    private(set) var refreshAccountDataCallCount = 0
    @MainActor func refreshAccountData() async { refreshAccountDataCallCount += 1 }

    private(set) var showQuestionCallCount = 0
    private(set) var showResultCallCount = 0
    private(set) var showSettingsCallCount = 0
    private(set) var showOnboardingCallCount = 0
    private(set) var showSubscriptionCallCount = 0
    private(set) var closeQuestionCallCount = 0
    private(set) var replayQuizCallCount = 0
    private(set) var returnToThemesCallCount = 0

    func showQuestion() {
        onShowQuestion?()
        showQuestionCallCount += 1
    }
    func showResult(_ result: QuizResultState) { showResultCallCount += 1 }
    func showSettings() { showSettingsCallCount += 1 }
    func showOnboarding() { showOnboardingCallCount += 1 }
    func showSubscription() { showSubscriptionCallCount += 1 }
    func closeQuestion() { closeQuestionCallCount += 1 }
    func replayQuiz() { replayQuizCallCount += 1 }
    func returnToThemes() { returnToThemesCallCount += 1 }
}
