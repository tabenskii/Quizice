import UIKit
import XCTest
@testable import Quizice

@MainActor
final class QuizFlowCoordinatorCatalogReplayTests: QuizFlowCoordinatorTestCase {
    func testPoliticsReplayReturnsToConfigurationWithoutRequestingQuestions() {
        let politics = SnapshotSupport.makeTheme(id: "politics_business", name: "Politics")
        politics.countries = ["US", "RU"]
        let repository = CountingReplayThemeRepository(themes: [politics])
        let session = RoutingSession()
        session.chosenTheme = ThemeModel(quizTheme: politics)
        let harness = makeCoordinator(themeRepository: repository, session: session)
        harness.coordinator.replayQuiz()
        XCTAssertEqual(harness.navigationController.popToRootCallCount, 1)
        XCTAssertEqual(harness.navigationController.dismissCallCount, 0)
        XCTAssertEqual(repository.prepareQuizCallCount, 0)
        XCTAssertEqual(repository.prepareRandomQuizCallCount, 0)
    }

    func testReplayQuizWithCatalogThemeDispatchesToRepository() async throws {
        let music = SnapshotSupport.makeTheme(id: "music", name: "Music")
        let repository = CountingReplayThemeRepository(themes: [music])
        let session = RoutingSession()
        session.chosenTheme = ThemeModel(quizTheme: music)
        session.questionsCount = 5
        let harness = makeCoordinator(themeRepository: repository, session: session)

        harness.coordinator.replayQuiz()

        try await waitUntil { repository.prepareQuizCallCount >= 1 }
        // Catalog replay path forwards through repository.prepareQuiz (not
        // prepareRandomQuiz and not the AI service). Concurrent replay taps
        // must be coalesced.
        XCTAssertEqual(repository.prepareRandomQuizCallCount, 0)
    }

    func testReplayQuizIgnoresDuplicateInvocationsWhileRunning() async throws {
        let music = SnapshotSupport.makeTheme(id: "music", name: "Music")
        let repository = CountingReplayThemeRepository(themes: [music])
        let session = RoutingSession()
        session.chosenTheme = ThemeModel(quizTheme: music)
        session.questionsCount = 5
        let harness = makeCoordinator(themeRepository: repository, session: session)

        harness.coordinator.replayQuiz()
        harness.coordinator.replayQuiz()
        harness.coordinator.replayQuiz()

        try await waitUntil { repository.prepareQuizCallCount >= 1 }
        // A second/third replayQuiz while the first is still preparing must
        // short-circuit — otherwise the coordinator would race on session
        // mutation and stack multiple backend requests.
        XCTAssertEqual(repository.prepareQuizCallCount, 1)
    }

    func testBackendRandomReplayRequestsFreshQuestionsWithoutLocalPool() async throws {
        let repository = CountingReplayThemeRepository(themes: [])
        repository.catalogOrigin = .backend
        let session = RoutingSession()
        session.chosenTheme = ThemeModel(quizTheme: SnapshotSupport.makeTheme(
            id: RandomQuizSelection.themeID, name: "Random"))
        session.questionsCount = 5
        let harness = makeCoordinator(themeRepository: repository, session: session)
        harness.coordinator.replayQuiz()
        try await waitUntil { repository.prepareRandomQuizCallCount == 1 }
        XCTAssertEqual(repository.prepareQuizCallCount, 0)
    }

    func testMusicReplayPreservesGenreInTheRoundSnapshotAndRequest() async throws {
        let song = SnapshotSupport.makeTheme(id: "music", name: "Music")
        song.musicGenreID = "rock"
        let snapshot = song.roundSnapshot()
        XCTAssertEqual(snapshot.musicGenreID, "rock")
        let repository = CountingReplayThemeRepository(themes: [song])
        let session = RoutingSession()
        session.chosenTheme = ThemeModel(quizTheme: snapshot)
        session.questionsCount = 10
        let harness = makeCoordinator(themeRepository: repository, session: session)
        harness.coordinator.replayQuiz()
        try await waitUntil { repository.prepareQuizCallCount == 1 }
        XCTAssertEqual(repository.requestedMusicGenreIDs, ["rock"])
    }

    private func makeCoordinator(
        themeRepository: ThemeRepository,
        session: QuizSessionManaging
    ) -> (
        coordinator: QuizFlowCoordinator,
        navigationController: RoutingNavigationControllerSpy
    ) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let navigationController = RoutingNavigationControllerSpy()
        let coordinator = QuizFlowCoordinator(
            window: window,
            navigationController: navigationController,
            themeRepository: themeRepository,
            session: session,
            aiQuizThemeService: MockAIQuizThemeService()
        )
        return (coordinator, navigationController)
    }
}

@MainActor
final class CountingReplayThemeRepository: ThemeRepository {
    var themes: [QuizTheme]?
    var catalogOrigin: QuizCatalogOrigin = .bundled
    private(set) var prepareQuizCallCount = 0
    private(set) var requestedMusicGenreIDs: [String?] = []
    private(set) var prepareRandomQuizCallCount = 0

    init(themes: [QuizTheme]) {
        self.themes = themes
    }

    func loadData(forceReload: Bool) {}

    func fetchQuizThemes() -> [QuizTheme] {
        themes ?? []
    }

    func prepareQuiz(
        themeID: String,
        questionCount: Int,
        difficulty: AIQuizDifficulty,
        locale: String
    ) async throws -> QuizTheme {
        prepareQuizCallCount += 1
        try await Task.sleep(nanoseconds: 300_000_000)
        guard let theme = themes?.first(where: { $0.stableID == themeID }) else {
            throw QuizPreparationError.unavailable
        }
        return theme
    }

    func prepareQuiz(
        themeID: String, questionCount: Int, difficulty: AIQuizDifficulty, locale: String, musicGenreID: String?
    ) async throws -> QuizTheme {
        requestedMusicGenreIDs.append(musicGenreID)
        return try await prepareQuiz(themeID: themeID, questionCount: questionCount, difficulty: difficulty, locale: locale)
    }

    func prepareRandomQuiz(
        selectionMode: CrossThemeQuestionSelectionMode,
        localFallback: QuizTheme,
        questionCount: Int,
        difficulty: AIQuizDifficulty,
        locale: String
    ) async throws -> QuizTheme {
        prepareRandomQuizCallCount += 1
        try await Task.sleep(nanoseconds: 300_000_000)
        return localFallback
    }
}
