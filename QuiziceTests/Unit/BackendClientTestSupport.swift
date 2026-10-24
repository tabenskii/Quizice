import Foundation
import XCTest
@testable import Quizice

final class BackendTestURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.requestHandler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class BackendMetricSpy: BackendRequestMetricRecording {
    private(set) var values: [BackendRequestMetric] = []
    func record(_ metric: BackendRequestMetric) { values.append(metric) }
}

struct BackendAccessTokenStub: BackendAccessTokenProviding {
    let token: String?

    func validAccessToken() -> String? { token }
}

final class BackendAuthenticationRecovererSpy: BackendAuthenticationRecovering, @unchecked Sendable {
    let refreshedToken: String
    private(set) var rejectedTokens: [String] = []

    init(refreshedToken: String) {
        self.refreshedToken = refreshedToken
    }

    func reauthenticate(afterRejectedAccessToken accessToken: String) async throws -> String {
        rejectedTokens.append(accessToken)
        return refreshedToken
    }
}

final class BackendMemorySessionStore: SessionStoring {
    var session: AuthSession?

    init(session: AuthSession? = nil) {
        self.session = session
    }

    func load() throws -> AuthSession? { session }
    func save(_ session: AuthSession) throws { self.session = session }
    func clear() throws { session = nil }
}

final class BackendScriptedSessionStore: SessionStoring {
    private var loadResults: [AuthSession?]
    private(set) var loadCount = 0

    init(loadResults: [AuthSession?]) {
        self.loadResults = loadResults
    }

    func load() throws -> AuthSession? {
        let index = min(loadCount, loadResults.count - 1)
        loadCount += 1
        return loadResults[index]
    }

    func save(_ session: AuthSession) throws {
        loadResults = [session]
        loadCount = 0
    }

    func clear() throws {
        loadResults = [nil]
        loadCount = 0
    }
}

final class BackendAIQuizAccessStub: AIQuizAccessUpdating {
    private(set) var isAIQuizAvailable: Bool

    init(isAvailable: Bool) {
        isAIQuizAvailable = isAvailable
    }

    func update(isAuthenticated: Bool) {
        isAIQuizAvailable = isAuthenticated
    }
}

struct SlowBackendContentAPI: BackendContentAPI {
    func fetchThemes(locale: String) async throws -> BackendThemeCatalogResponse {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        throw URLError(.timedOut)
    }

    func fetchQuestions(
        themeID: String,
        count: Int,
        locale: String,
        seed: String
    ) async throws -> BackendQuestionBatchResponse {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        throw URLError(.timedOut)
    }

    func fetchRandomQuestions(
        selectionMode: CrossThemeQuestionSelectionMode,
        count: Int,
        locale: String,
        seed: String
    ) async throws -> BackendQuestionBatchResponse {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        throw URLError(.timedOut)
    }
}

final class RecordingBackendContentAPI: BackendContentAPI {
    private(set) var requestedCountries: [String?] = []

    func fetchQuestions(
        themeID: String, count: Int, locale: String, difficulty: AIQuizDifficulty,
        seed: String, strategy: QuestionRepeatStrategy, country: String?
    ) async throws -> BackendQuestionBatchResponse {
        requestedCountries.append(country)
        return try await fetchQuestions(themeID: themeID, count: count, locale: locale, seed: seed)
    }

    func fetchRandomQuestions(
        selectionMode: CrossThemeQuestionSelectionMode, count: Int, locale: String,
        difficulty: AIQuizDifficulty, seed: String, strategy: QuestionRepeatStrategy, country: String?
    ) async throws -> BackendQuestionBatchResponse {
        requestedCountries.append(country)
        return try await fetchRandomQuestions(selectionMode: selectionMode, count: count, locale: locale, seed: seed)
    }

    private let catalogThemes: [BackendThemeDTO]
    private let questionError: Error?
    var returnedQuestionCount: Int?
    var onQuestions: (() throws -> Void)?
    private(set) var themeRequestCount = 0
    private(set) var seeds: [String] = []
    private(set) var randomSelectionModes: [CrossThemeQuestionSelectionMode] = []

    init(
        catalogThemes: [BackendThemeDTO] = [
            BackendThemeDTO(
                id: "music",
                name: "Remote Music",
                description: "Remote Description",
                sfSymbol: "music.note.list",
                emoji: "🎵",
                colorHex: "#FF8252",
                isFavorite: false
            )
        ],
        questionError: Error? = nil
    ) {
        self.catalogThemes = catalogThemes
        self.questionError = questionError
    }

    func fetchThemes(locale: String) async throws -> BackendThemeCatalogResponse {
        themeRequestCount += 1
        return BackendThemeCatalogResponse(locale: locale, themes: catalogThemes)
    }

    func fetchQuestions(
        themeID: String,
        count: Int,
        locale: String,
        seed: String
    ) async throws -> BackendQuestionBatchResponse {
        seeds.append(seed)
        try onQuestions?()
        if let questionError {
            throw questionError
        }
        return BackendQuestionBatchResponse(
            locale: locale,
            seed: seed,
            questions: (0..<(returnedQuestionCount ?? count)).map { index in
                BackendQuestionDTO(
                    question: "Remote \(seed) \(index)",
                    answers: ["A\(index)", "B\(index)", "C\(index)", "D\(index)"],
                    correctAnswer: "B\(index)",
                    explanation: "Explanation"
                )
            }
        )
    }

    func fetchRandomQuestions(
        selectionMode: CrossThemeQuestionSelectionMode,
        count: Int,
        locale: String,
        seed: String
    ) async throws -> BackendQuestionBatchResponse {
        randomSelectionModes.append(selectionMode)
        return try await fetchQuestions(
            themeID: RandomQuizSelection.themeID,
            count: count,
            locale: locale,
            seed: seed
        )
    }
}

final class QuestionAnswerBackendContentAPI: BackendContentAPI {
    var submitResults: [Result<QuestionAnswerBatchResponse, Error>]
    var onSubmit: (([QuestionAnswerEvent]) async throws -> QuestionAnswerBatchResponse)?
    private(set) var submittedSessions: [AuthSession] = []
    private(set) var submittedBatches: [[QuestionAnswerEvent]] = []

    init(submitResults: [Result<QuestionAnswerBatchResponse, Error>]) {
        self.submitResults = submitResults
    }

    func submitQuestionAnswers(_ events: [QuestionAnswerEvent], session: AuthSession) async throws -> QuestionAnswerBatchResponse {
        submittedSessions.append(session)
        return try await submitQuestionAnswers(events)
    }

    func submitQuestionAnswers(_ events: [QuestionAnswerEvent]) async throws -> QuestionAnswerBatchResponse {
        submittedBatches.append(events)
        if let onSubmit { return try await onSubmit(events) }
        return try submitResults.removeFirst().get()
    }

    func fetchThemes(locale: String) async throws -> BackendThemeCatalogResponse {
        BackendThemeCatalogResponse(locale: locale, themes: [])
    }

    func fetchQuestions(
        themeID: String,
        count: Int,
        locale: String,
        seed: String
    ) async throws -> BackendQuestionBatchResponse {
        BackendQuestionBatchResponse(locale: locale, seed: seed, questions: [])
    }

    func fetchRandomQuestions(
        selectionMode: CrossThemeQuestionSelectionMode,
        count: Int,
        locale: String,
        seed: String
    ) async throws -> BackendQuestionBatchResponse {
        BackendQuestionBatchResponse(locale: locale, seed: seed, questions: [])
    }
}

final class ThemePreferencesBackendContentAPI: BackendContentAPI {
    private let catalogThemes: [BackendThemeDTO]
    var remoteFavoriteThemeIDs: [String]
    var preferencesError: Error?
    var beforePreferencesResponse: (() -> Void)?
    var beforeAsyncPreferencesResponse: (() async -> Void)?
    var beforeCatalogResponse: (() async -> Void)?
    var catalogError: Error?
    private(set) var fetchedCatalogLocales: [String] = []
    private(set) var fetchedPreferenceLocales: [String] = []
    private(set) var replacedPreferences: [(locale: String, themeIDs: [String])] = []

    init(
        catalogThemes: [BackendThemeDTO],
        remoteFavoriteThemeIDs: [String] = []
    ) {
        self.catalogThemes = catalogThemes
        self.remoteFavoriteThemeIDs = remoteFavoriteThemeIDs
    }

    func fetchThemes(locale: String) async throws -> BackendThemeCatalogResponse {
        fetchedCatalogLocales.append(locale)
        await beforeCatalogResponse?()
        if let catalogError { throw catalogError }
        return BackendThemeCatalogResponse(locale: locale, themes: catalogThemes)
    }

    func fetchThemePreferences(locale: String) async throws -> BackendThemePreferencesResponse {
        fetchedPreferenceLocales.append(locale)
        beforePreferencesResponse?()
        await beforeAsyncPreferencesResponse?()
        if let preferencesError {
            throw preferencesError
        }
        return BackendThemePreferencesResponse(
            locale: locale,
            favoriteThemeIds: remoteFavoriteThemeIDs
        )
    }

    func replaceThemePreferences(
        locale: String,
        favoriteThemeIDs: [String]
    ) async throws -> BackendThemePreferencesResponse {
        replacedPreferences.append((locale, favoriteThemeIDs))
        beforePreferencesResponse?()
        await beforeAsyncPreferencesResponse?()
        if let preferencesError {
            throw preferencesError
        }
        remoteFavoriteThemeIDs = favoriteThemeIDs
        return BackendThemePreferencesResponse(
            locale: locale,
            favoriteThemeIds: favoriteThemeIDs
        )
    }

    func fetchQuestions(
        themeID: String,
        count: Int,
        locale: String,
        seed: String
    ) async throws -> BackendQuestionBatchResponse {
        throw URLError(.unsupportedURL)
    }

    func fetchRandomQuestions(
        selectionMode: CrossThemeQuestionSelectionMode,
        count: Int,
        locale: String,
        seed: String
    ) async throws -> BackendQuestionBatchResponse {
        throw URLError(.unsupportedURL)
    }
}

final class SequencedCatalogBackendContentAPI: BackendContentAPI {
    private var fetchCount = 0

    func fetchThemes(locale: String) async throws -> BackendThemeCatalogResponse {
        defer { fetchCount += 1 }
        guard fetchCount == 0 else { throw URLError(.timedOut) }
        return BackendThemeCatalogResponse(
            locale: locale,
            themes: [
                BackendThemeDTO(
                    id: "music",
                    name: "Remote Music",
                    description: "Remote Description",
                    sfSymbol: "music.note.list",
                    emoji: "🎵",
                    colorHex: "#FF8252",
                    isFavorite: false
                )
            ]
        )
    }

    func fetchQuestions(
        themeID: String,
        count: Int,
        locale: String,
        seed: String
    ) async throws -> BackendQuestionBatchResponse {
        throw URLError(.unsupportedURL)
    }

    func fetchRandomQuestions(
        selectionMode: CrossThemeQuestionSelectionMode,
        count: Int,
        locale: String,
        seed: String
    ) async throws -> BackendQuestionBatchResponse {
        throw URLError(.unsupportedURL)
    }
}

final class BackendRandomQuestionTests: XCTestCase {
    override func tearDown() {
        BackendTestURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testCrossThemeQuestionModesUseDocumentedEndpointsAndContract() async throws {
        let api = makeContentAPI()
        let seed = "550e8400-e29b-41d4-a716-446655440000"

        for selectionMode in CrossThemeQuestionSelectionMode.allCases {
            BackendTestURLProtocol.requestHandler = { request in
                XCTAssertEqual(request.url?.path, "/api/v1/questions/\(selectionMode.rawValue)")
                let query = try XCTUnwrap(
                    URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
                )
                XCTAssertEqual(
                    Dictionary(uniqueKeysWithValues: query.compactMap { item in
                        item.value.map { (item.name, $0) }
                    }),
                    ["count": "5", "locale": "ru", "seed": seed]
                )
                let body = try JSONSerialization.data(withJSONObject: [
                    "locale": "ru",
                    "seed": seed,
                    "questions": (0..<5).map(Self.questionJSON)
                ])
                return Self.response(for: request, data: body)
            }

            let response = try await api.fetchRandomQuestions(
                selectionMode: selectionMode,
                count: 5,
                locale: "ru",
                seed: seed
            )
            XCTAssertEqual(response.questions.count, 5)
        }
    }

    func testRandomQuizPreparationForwardsBothSelectionModesToBackend() async throws {
        let backend = RecordingBackendContentAPI()
        let repository = ThemeCatalogRepository(backendContentAPI: backend)
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        let didRefresh = await repository.refreshBackendCatalog(locale: locale)
        XCTAssertTrue(didRefresh)
        let localFallback = QuizTheme(
            id: RandomQuizSelection.themeID,
            theme: L10n.Home.randomSelection,
            themeDescription: L10n.Home.feelingLucky,
            questions: Self.localQuestions(count: 5)
        )

        for selectionMode in CrossThemeQuestionSelectionMode.allCases {
            let prepared = try await repository.prepareRandomQuiz(
                selectionMode: selectionMode,
                localFallback: localFallback,
                questionCount: 5,
                locale: locale
            )
            XCTAssertEqual(prepared.stableID, RandomQuizSelection.themeID)
            XCTAssertEqual(prepared.questionOrigin, .backend)
            XCTAssertEqual(prepared.questions.count, 5)
            XCTAssertTrue(prepared.questions.allSatisfy { $0.explanation == "Explanation" })
        }

        XCTAssertEqual(backend.randomSelectionModes, [.random, .randomBalanced])
        XCTAssertEqual(backend.seeds.count, 2)
        XCTAssertNotEqual(backend.seeds[0], backend.seeds[1])
    }

    func testBundledRandomQuizDoesNotCallBackend() async throws {
        let backend = RecordingBackendContentAPI()
        let repository = ThemeCatalogRepository(backendContentAPI: backend)
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        let localFallback = QuizTheme(
            id: RandomQuizSelection.themeID,
            theme: L10n.Home.randomSelection,
            themeDescription: L10n.Home.feelingLucky,
            questions: Self.localQuestions(count: 5)
        )

        let prepared = try await repository.prepareRandomQuiz(
            selectionMode: .random,
            localFallback: localFallback,
            questionCount: 5,
            locale: locale
        )

        XCTAssertTrue(prepared === localFallback)
        XCTAssertTrue(backend.randomSelectionModes.isEmpty)
        XCTAssertTrue(backend.seeds.isEmpty)
    }

    func testBackendRandomQuestionFailureDoesNotReturnBundledFallback() async {
        let backend = RecordingBackendContentAPI(
            questionError: URLError(.timedOut)
        )
        let repository = ThemeCatalogRepository(backendContentAPI: backend)
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        let didRefresh = await repository.refreshBackendCatalog(locale: locale)
        let localFallback = QuizTheme(
            id: RandomQuizSelection.themeID,
            theme: L10n.Home.randomSelection,
            themeDescription: L10n.Home.feelingLucky,
            questions: Self.localQuestions(count: 5)
        )
        XCTAssertTrue(didRefresh)

        do {
            _ = try await repository.prepareRandomQuiz(
                selectionMode: .randomBalanced,
                localFallback: localFallback,
                questionCount: 5,
                locale: locale
            )
            XCTFail("Backend catalog mode must not fall back to bundled random questions")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
        XCTAssertEqual(backend.randomSelectionModes, [.randomBalanced])
        XCTAssertEqual(backend.seeds.count, 1)
    }

    private func makeContentAPI() -> HTTPBackendContentAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BackendTestURLProtocol.self]
        return HTTPBackendContentAPI(
            configuration: BackendConfiguration(
                baseURL: URL(string: "https://backend.example/api")!
            ),
            session: URLSession(configuration: configuration)
        )
    }

    private static func response(
        for request: URLRequest,
        data: Data
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            data
        )
    }

    private static func questionJSON(index: Int) -> [String: Any] {
        [
            "questionId": "question-\(index)",
            "questionVersion": 1,
            "question": "Question \(index)",
            "answers": ["A\(index)", "B\(index)", "C\(index)", "D\(index)"],
            "correctAnswer": "B\(index)",
            "explanation": ""
        ]
    }

    private static func localQuestions(count: Int) -> [QuizQuestion] {
        (0..<count).map { index in
            QuizQuestion(
                question: "Local \(index)",
                answers: ["A\(index)", "B\(index)", "C\(index)", "D\(index)"],
                correctAnswer: "B\(index)"
            )
        }
    }
}

final class ProgressSessionProvider: BackendAccessTokenProviding {
    var session: AuthSession? = ProgressSessionProvider.session("A")
    static func session(_ userID: String) -> AuthSession {
        AuthSession(userID: userID, accessToken: "token-" + userID, expiresAt: .distantFuture, teamPlayerID: userID)
    }
    func currentSession() -> AuthSession? { session }
    func validAccessToken() -> String? { session?.accessToken }
}

final class ProgressOutboxSpy: QuestionAnswerOutboxing {
    var synchronizedUsers: [String] = []
    var beforeFetch: (() async throws -> Void)?
    func enqueue(_ event: QuestionAnswerEvent) {}
    func synchronize() async {}
    func synchronizeBeforeFetchingQuestions(for userID: String) async throws {
        synchronizedUsers.append(userID)
        try await beforeFetch?()
    }
}

actor ProgressUploadGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuations.append($0) }
    }
    func open() {
        isOpen = true
        continuations.forEach { $0.resume() }
        continuations.removeAll()
    }
}

struct ProgressAuthenticationRecoverer: BackendAuthenticationRecovering {
    let operation: () -> String
    func reauthenticate(afterRejectedAccessToken accessToken: String) async throws -> String { operation() }
}
