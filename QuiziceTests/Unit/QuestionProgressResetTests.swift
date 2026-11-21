import Foundation
import XCTest
@testable import Quizice

extension BackendClientTests {
    func testRepeatStrategyDefaultsToHideAnsweredAndPreservesExplicitChoices() {
        let suiteName = "QuestionProgressResetTests.Strategy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(QuestionRepeatStrategyStore(defaults: defaults).strategy, .hideAnswered)
        for strategy in QuestionRepeatStrategy.allCases {
            QuestionRepeatStrategyStore(defaults: defaults).strategy = strategy
            XCTAssertEqual(QuestionRepeatStrategyStore(defaults: defaults).strategy, strategy)
        }
        defaults.set("unknown-future-strategy", forKey: QuestionRepeatStrategyStore.defaultsKey)
        XCTAssertEqual(QuestionRepeatStrategyStore(defaults: defaults).strategy, .hideAnswered)
    }

    func testLegacyQuestionBatchAndAnswerEventDecodeWithoutProgressGeneration() throws {
        let questionData = try JSONSerialization.data(withJSONObject: Self.questionJSON(index: 0))
        let question = try JSONDecoder().decode(BackendQuestionDTO.self, from: questionData)
        XCTAssertNil(question.progressGeneration)
        XCTAssertNil(question.makeModel().progressGeneration)

        let response = try JSONDecoder().decode(BackendQuestionBatchResponse.self, from: Data(
            #"{"locale":"ru","seed":"legacy","questions":[]}"#.utf8
        ))
        XCTAssertFalse(response.isExhausted)
        XCTAssertEqual(response.availableCount, 0)

        let event = QuestionAnswerEvent(eventId: UUID(), questionId: "music:1", questionVersion: 1,
                                        locale: "ru", answer: nil, answeredAt: Date(timeIntervalSince1970: 100))
        let encoded = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(json["progressGeneration"])
        XCTAssertEqual(try JSONDecoder().decode(QuestionAnswerEvent.self, from: encoded), event)
    }

    func testFilteredExhaustionIsAcceptedForEachRequestedProgressMode() async throws {
        let api = makeContentAPI(accessToken: "progress-token")
        let seed = UUID().uuidString.lowercased()
        for strategy in [QuestionRepeatStrategy.hideAnswered, .retryIncorrect] {
            BackendTestURLProtocol.requestHandler = { request in
                let body = try JSONSerialization.data(withJSONObject: [
                    "locale": "ru", "seed": seed, "progressMode": strategy.progressMode!.rawValue,
                    "availableCount": 0, "isExhausted": true, "questions": []
                ])
                return Self.response(for: request, data: body)
            }
            let response = try await api.fetchQuestions(themeID: "music", count: 5, locale: "ru",
                difficulty: .medium, seed: seed, strategy: strategy)
            XCTAssertTrue(response.isExhausted)
            XCTAssertTrue(response.questions.isEmpty)
        }
    }

    func testMalformedOrMismatchedExhaustionIsRejected() async {
        let api = makeContentAPI(accessToken: "progress-token")
        let seed = UUID().uuidString.lowercased()
        let invalidResponses: [[String: Any]] = [
            ["availableCount": 0, "questions": []],
            ["progressMode": "correct_only", "availableCount": 0, "questions": []],
            ["progressMode": "all_answered", "availableCount": 1, "questions": []],
            ["progressMode": "all_answered", "availableCount": 1, "questions": [Self.questionJSON(index: 0)]]
        ]
        for fields in invalidResponses {
            BackendTestURLProtocol.requestHandler = { request in
                var body = fields
                body["locale"] = "ru"
                body["seed"] = seed
                body["isExhausted"] = true
                return Self.response(for: request, data: try JSONSerialization.data(withJSONObject: body))
            }
            await assertBackendContentError(.contractViolation) {
                try await api.fetchQuestions(themeID: "music", count: 5, locale: "ru",
                    difficulty: .medium, seed: seed, strategy: .hideAnswered)
            }
        }
    }

    func testShowAllCannotAcceptAnExhaustedPersonalizedResponse() async {
        let api = makeContentAPI(accessToken: "progress-token")
        let seed = UUID().uuidString.lowercased()
        BackendTestURLProtocol.requestHandler = { request in
            let body = try JSONSerialization.data(withJSONObject: [
                "locale": "ru", "seed": seed, "progressMode": "all_answered",
                "availableCount": 0, "isExhausted": true, "questions": []
            ])
            return Self.response(for: request, data: body)
        }
        await assertBackendContentError(.contractViolation) {
            try await api.fetchQuestions(themeID: "music", count: 5, locale: "ru",
                difficulty: .medium, seed: seed, strategy: .showAll)
        }
    }

    func testProgressResetPOSTBindsThemeIdempotencyKeyAndAccount() async throws {
        let provider = ProgressSessionProvider()
        let currentSession = try XCTUnwrap(provider.session)
        let resetID = UUID()
        let api = makeProgressResetAPI(provider: provider)
        BackendTestURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/me/themes/music/question-progress/reset")
            XCTAssertNil(request.url?.query)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Quizice-Authorization"), "Bearer token-A")
            let body = try XCTUnwrap(Self.bodyData(from: request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(Set(json.keys), ["resetId"])
            XCTAssertEqual((json["resetId"] as? String).flatMap(UUID.init(uuidString:)), resetID)
            return Self.response(for: request, data: Self.progressResetResponseData(resetID: resetID))
        }

        let response = try await api.resetQuestionProgress(themeID: "music", resetID: resetID, session: currentSession)

        XCTAssertEqual(response.themeId, "music")
        XCTAssertEqual(response.resetId, resetID)
        XCTAssertEqual(response.resetAt, "2026-10-24T12:00:00Z")
    }

    func testProgressResetRejectsGuestAndAccountMismatchBeforeNetwork() async {
        let provider = ProgressSessionProvider()
        let api = makeProgressResetAPI(provider: provider)
        BackendTestURLProtocol.requestHandler = { request in
            XCTFail("Must not reset progress under another account")
            return Self.response(for: request, data: Data())
        }
        for replacement in [nil, ProgressSessionProvider.session("B")] {
            provider.session = replacement
            await assertBackendContentError(.unauthenticated) {
                try await api.resetQuestionProgress(themeID: "music", resetID: UUID(),
                    session: ProgressSessionProvider.session("A"))
            }
        }
    }

    func testProgressResetValidatesResponseThemeResetIDAndTimestamp() async {
        let provider = ProgressSessionProvider()
        let api = makeProgressResetAPI(provider: provider)
        let resetID = UUID()
        let invalidResponses = [
            Self.progressResetResponseData(resetID: resetID, themeID: "space"),
            Self.progressResetResponseData(resetID: UUID()),
            Self.progressResetResponseData(resetID: resetID, resetAt: "not-a-date")
        ]
        for body in invalidResponses {
            BackendTestURLProtocol.requestHandler = { Self.response(for: $0, data: body) }
            await assertBackendContentError(.contractViolation) {
                try await api.resetQuestionProgress(themeID: "music", resetID: resetID,
                    session: ProgressSessionProvider.session("A"))
            }
        }
    }

    func testProgressResetRejectsUnsafeThemeIDsAndReservedGenerationBeforeNetwork() async {
        let api = makeProgressResetAPI(provider: ProgressSessionProvider())
        BackendTestURLProtocol.requestHandler = { request in
            XCTFail("Invalid reset input must be rejected before network access")
            return Self.response(for: request, data: Data())
        }
        for themeID in ["", " ", "../music", "music/space", "music\n"] {
            await assertBackendContentError(.invalidRequest) {
                try await api.resetQuestionProgress(themeID: themeID, resetID: UUID(),
                    session: ProgressSessionProvider.session("A"))
            }
        }
        await assertBackendContentError(.invalidRequest) {
            try await api.resetQuestionProgress(themeID: "music",
                resetID: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
                session: ProgressSessionProvider.session("A"))
        }
    }

    func testProgressResetRetriesSameIdempotencyKeyAfterAuthenticationRecovery() async throws {
        let provider = ProgressSessionProvider()
        let recoverer = BackendAuthenticationRecovererSpy(refreshedToken: "fresh-token-A")
        let api = makeProgressResetAPI(provider: provider, recoverer: recoverer)
        let resetID = UUID()
        var headers: [String?] = []
        var resetIDs: [UUID] = []
        BackendTestURLProtocol.requestHandler = { request in
            headers.append(request.value(forHTTPHeaderField: "X-Quizice-Authorization"))
            let body = try XCTUnwrap(Self.bodyData(from: request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
            resetIDs.append(try XCTUnwrap(json["resetId"].flatMap(UUID.init(uuidString:))))
            return Self.response(for: request, statusCode: headers.count == 1 ? 401 : 200,
                data: headers.count == 1 ? Data("{}".utf8) : Self.progressResetResponseData(resetID: resetID))
        }

        _ = try await api.resetQuestionProgress(themeID: "music", resetID: resetID,
            session: ProgressSessionProvider.session("A"))

        XCTAssertEqual(headers, ["Bearer token-A", "Bearer fresh-token-A"])
        XCTAssertEqual(resetIDs, [resetID, resetID])
        XCTAssertEqual(recoverer.rejectedTokens, ["token-A"])
    }

    func testProgressResetDoesNotRetryAfterAccountChangesDuringRecovery() async {
        let provider = ProgressSessionProvider()
        let recoverer = ProgressAuthenticationRecoverer {
            provider.session = ProgressSessionProvider.session("B")
            return "token-B"
        }
        let api = makeProgressResetAPI(provider: provider, recoverer: recoverer)
        var calls = 0
        BackendTestURLProtocol.requestHandler = { request in
            calls += 1
            return Self.response(for: request, statusCode: 401, data: Data("{}".utf8))
        }

        await assertBackendContentError(.unauthenticated) {
            try await api.resetQuestionProgress(themeID: "music", resetID: UUID(),
                session: ProgressSessionProvider.session("A"))
        }

        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testOnlyExplicitFilteredExhaustionProducesProgressComplete() async throws {
        let backend = ProgressResetBackendStub()
        let provider = ProgressSessionProvider()
        let repository = makeProgressResetRepository(backend: backend, provider: provider)
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        let refreshed = await repository.refreshBackendCatalog(locale: locale)
        XCTAssertTrue(refreshed)

        backend.isExhausted = false
        let empty = try await repository.prepareQuiz(themeID: "music", questionCount: 5, locale: locale)
        XCTAssertTrue(empty.questions.isEmpty)

        backend.isExhausted = true
        do {
            _ = try await repository.prepareQuiz(themeID: "music", questionCount: 5, locale: locale)
            XCTFail("An exhausted filtered theme must offer progress reset")
        } catch {
            XCTAssertEqual(error as? QuizPreparationError, .progressComplete(userID: "A"))
        }
    }

    @MainActor
    func testRepositoryFlushesPendingAnswersBeforeResetAndKeepsIdempotencyKey() async throws {
        let backend = ProgressResetBackendStub()
        let provider = ProgressSessionProvider()
        let outbox = ProgressOutboxSpy()
        let repository = makeProgressResetRepository(backend: backend, provider: provider, outbox: outbox)
        _ = await repository.refreshBackendCatalog(locale: AppLocalizationStore.shared.resolvedLanguageCode)
        var operations: [String] = []
        outbox.beforeFetch = { operations.append("flush") }
        backend.beforeReset = { operations.append("reset") }
        let resetID = UUID()

        try await repository.resetQuestionProgress(themeID: "music", resetID: resetID, expectedUserID: "A")

        XCTAssertEqual(operations, ["flush", "reset"])
        XCTAssertEqual(outbox.synchronizedUsers, ["A"])
        XCTAssertEqual(backend.resetCalls.map(\.resetID), [resetID])
        XCTAssertEqual(backend.resetCalls.map(\.themeID), ["music"])
        XCTAssertEqual(backend.resetCalls.map(\.session.userID), ["A"])
    }

    @MainActor
    func testRepositoryDoesNotResetWhenPendingAnswerUploadFails() async {
        let backend = ProgressResetBackendStub()
        let provider = ProgressSessionProvider()
        let outbox = ProgressOutboxSpy()
        let repository = makeProgressResetRepository(backend: backend, provider: provider, outbox: outbox)
        _ = await repository.refreshBackendCatalog(locale: AppLocalizationStore.shared.resolvedLanguageCode)
        outbox.beforeFetch = { throw BackendContentError.transport(.notConnectedToInternet) }

        await assertBackendContentError(.transport(.notConnectedToInternet)) {
            try await repository.resetQuestionProgress(themeID: "music", resetID: UUID(), expectedUserID: "A")
        }

        XCTAssertTrue(backend.resetCalls.isEmpty)
    }

    @MainActor
    func testRepositoryRejectsAccountChangesBeforeResetAndAfterFlushing() async {
        for changeDuringFlush in [false, true] {
            let backend = ProgressResetBackendStub()
            let provider = ProgressSessionProvider()
            let outbox = ProgressOutboxSpy()
            let repository = makeProgressResetRepository(backend: backend, provider: provider, outbox: outbox)
            _ = await repository.refreshBackendCatalog(locale: AppLocalizationStore.shared.resolvedLanguageCode)
            if changeDuringFlush {
                outbox.beforeFetch = { provider.session = ProgressSessionProvider.session("B") }
            } else {
                provider.session = ProgressSessionProvider.session("B")
            }

            do {
                try await repository.resetQuestionProgress(themeID: "music", resetID: UUID(), expectedUserID: "A")
                XCTFail("The reset must remain bound to the account that saw the alert")
            } catch {
                XCTAssertTrue(error is QuestionAnswerSyncError || error as? BackendContentError == .unauthenticated)
            }

            XCTAssertTrue(backend.resetCalls.isEmpty)
            XCTAssertEqual(outbox.synchronizedUsers, changeDuringFlush ? ["A"] : [])
        }
    }

    @MainActor
    func testRepositoryRejectsResetSuccessAfterAccountChanges() async {
        let backend = ProgressResetBackendStub()
        let provider = ProgressSessionProvider()
        let repository = makeProgressResetRepository(backend: backend, provider: provider)
        _ = await repository.refreshBackendCatalog(locale: AppLocalizationStore.shared.resolvedLanguageCode)
        backend.beforeReset = { provider.session = ProgressSessionProvider.session("B") }

        do {
            try await repository.resetQuestionProgress(themeID: "music", resetID: UUID(), expectedUserID: "A")
            XCTFail("Do not restart the old user's quiz under the new account")
        } catch {
            XCTAssertTrue(error is QuestionAnswerSyncError || error as? BackendContentError == .unauthenticated)
        }

        XCTAssertEqual(backend.resetCalls.count, 1)
    }

    @MainActor
    func testCancelledResetAfterFlushingDoesNotReachBackend() async {
        let backend = ProgressResetBackendStub()
        let provider = ProgressSessionProvider()
        let outbox = ProgressOutboxSpy()
        let repository = makeProgressResetRepository(backend: backend, provider: provider, outbox: outbox)
        _ = await repository.refreshBackendCatalog(locale: AppLocalizationStore.shared.resolvedLanguageCode)
        let gate = ProgressUploadGate()
        let flushing = expectation(description: "Flushing answers before reset")
        outbox.beforeFetch = {
            flushing.fulfill()
            await gate.wait()
        }
        let task = Task {
            try await repository.resetQuestionProgress(themeID: "music", resetID: UUID(), expectedUserID: "A")
        }
        await fulfillment(of: [flushing], timeout: 2)
        task.cancel()
        await gate.open()

        do {
            try await task.value
            XCTFail("Cancelled confirmation must not reset progress")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertTrue(backend.resetCalls.isEmpty)
    }

    func testProgressGenerationSurvivesQuestionMappingAndRoundSnapshot() throws {
        let generation = UUID()
        var json = Self.questionJSON(index: 0)
        json["progressGeneration"] = generation.uuidString
        let dto = try JSONDecoder().decode(BackendQuestionDTO.self,
            from: JSONSerialization.data(withJSONObject: json))
        let question = dto.makeModel(locale: "ru")
        let theme = QuizTheme(id: "music", theme: "Music", themeDescription: "Music questions", questions: [question])
        let snapshot = theme.roundSnapshot()

        question.progressGeneration = UUID()

        XCTAssertEqual(dto.progressGeneration, generation)
        XCTAssertEqual(snapshot.questions.first?.progressGeneration, generation)
        XCTAssertEqual(snapshot.questions.map(QuestionModel.init(quizQuestion:)).first?.progressGeneration, generation)
    }

    func testProgressGenerationSurvivesPersistentOutboxAndUpload() async throws {
        let generation = UUID()
        let event = QuestionAnswerEvent(eventId: UUID(), questionId: "music:1", questionVersion: 1,
            locale: "ru", answer: "A", answeredAt: Date(timeIntervalSince1970: 100), progressGeneration: generation)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("reset-generation-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let provider = ProgressSessionProvider()
        let api = QuestionAnswerBackendContentAPI(submitResults: [.success(QuestionAnswerBatchResponse(processedEventIds: [event.eventId]))])
        let original = PersistentQuestionAnswerOutbox(api: api, fileURL: file,
            automaticallySynchronizesOnEnqueue: false, sessionProvider: { provider.session })
        original.enqueue(event)
        let restored = PersistentQuestionAnswerOutbox(api: api, fileURL: file,
            automaticallySynchronizesOnEnqueue: false, sessionProvider: { provider.session })

        XCTAssertEqual(restored.pendingEvents(), [event])
        try await restored.synchronizeBeforeFetchingQuestions(for: "A")

        XCTAssertEqual(api.submittedBatches.first?.first?.progressGeneration, generation)
        XCTAssertTrue(restored.pendingEvents().isEmpty)
    }

    @MainActor
    func testPresenterEchoesIssuedGenerationAfterCatalogMutation() throws {
        let generation = UUID()
        let question = BackendQuestionDTO(questionId: "music:1", questionVersion: 1,
            progressGeneration: generation, question: "Which answer?", answers: ["A", "B", "C", "D"],
            correctAnswer: "A", explanation: nil).makeModel(locale: "ru")
        let session = ProgressResetQuizSession()
        session.chosenTheme = ThemeModel(quizTheme: QuizTheme(id: "music", theme: "Music",
            themeDescription: "Music questions", questions: [question]))
        let suiteName = "QuestionProgressResetTests.Presenter.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let outbox = ProgressResetAnswerOutbox()
        let view = ProgressResetQuestionView()
        let presenter = QuizQuestionPresenter(session: session,
            statisticsStore: StatisticsStore(userDefaults: defaults, key: "attempts"), answerOutbox: outbox)
        presenter.view = view
        presenter.viewDidLoad()
        question.progressGeneration = UUID()
        let answer = try XCTUnwrap(view.question?.answers.first { $0.title == "A" })

        presenter.checkAnswer(optionID: answer.id)

        XCTAssertEqual(outbox.events.count, 1)
        XCTAssertEqual(outbox.events.first?.progressGeneration, generation)
        XCTAssertEqual(outbox.events.first?.answer, "A")
    }

    private func makeProgressResetAPI(
        provider: BackendAccessTokenProviding,
        recoverer: BackendAuthenticationRecovering? = nil
    ) -> HTTPBackendContentAPI {
        HTTPBackendContentAPI(configuration: Self.configuration, session: makeSession(),
            accessTokenProvider: provider, authenticationRecoverer: recoverer)
    }

    private func makeProgressResetRepository(
        backend: ProgressResetBackendStub,
        provider: ProgressSessionProvider,
        outbox: QuestionAnswerOutboxing = ProgressOutboxSpy()
    ) -> ThemeCatalogRepository {
        ThemeCatalogRepository(backendContentAPI: backend, accessTokenProvider: provider,
            answerOutbox: outbox, repeatStrategyProvider: { .hideAnswered }, countryProvider: { nil })
    }

    private static func progressResetResponseData(
        resetID: UUID,
        themeID: String = "music",
        resetAt: String = "2026-10-24T12:00:00Z"
    ) -> Data {
        Data("{\"themeId\":\"\(themeID)\",\"resetId\":\"\(resetID.uuidString)\",\"resetAt\":\"\(resetAt)\"}".utf8)
    }
}

private final class ProgressResetQuizSession: QuizSessionManaging {
    var themes: [QuizTheme]?
    var chosenTheme: ThemeModel?
    var questionsCount = 5
    var startup1st = false
    func loadTheme(themeID: String) -> Bool { false }
}

private final class ProgressResetAnswerOutbox: QuestionAnswerOutboxing {
    private(set) var events: [QuestionAnswerEvent] = []
    func enqueue(_ event: QuestionAnswerEvent) { events.append(event) }
    func synchronize() async {}
}

private final class ProgressResetQuestionView: QuizQuestionViewControllerProtocol {
    var presenter: QuizQuestionPresenterProtocol?
    private(set) var question: QuizQuestionViewModel?
    func updateProgress(_ progress: Float) {}
    func showTimeExpired() {}
    func hideTimerBar() {}
    func loadQuestionToView(_ viewModel: QuizQuestionViewModel) { question = viewModel }
    func showQuestionUnavailable(themeName: String?, message: String) {}
    func correctAnswerTapped(isTrue: Bool) {}
    func showResults(_ result: QuizResultState) {}
}

private final class ProgressResetBackendStub: BackendContentAPI {
    struct ResetCall {
        let themeID: String
        let resetID: UUID
        let session: AuthSession
    }

    var isExhausted = true
    var beforeReset: (() async throws -> Void)?
    private(set) var resetCalls: [ResetCall] = []

    func fetchThemes(locale: String) async throws -> BackendThemeCatalogResponse {
        BackendThemeCatalogResponse(locale: locale, themes: [
            BackendThemeDTO(id: "music", name: "Music", description: "Music questions",
                            sfSymbol: "music.note", emoji: "🎵", colorHex: "#FF8252", isFavorite: false)
        ])
    }

    func fetchQuestions(themeID: String, count: Int, locale: String, seed: String) async throws -> BackendQuestionBatchResponse {
        BackendQuestionBatchResponse(locale: locale, seed: seed, progressMode: .allAnswered,
                                     availableCount: 0, isExhausted: isExhausted, questions: [])
    }

    func fetchRandomQuestions(selectionMode: CrossThemeQuestionSelectionMode, count: Int,
                              locale: String, seed: String) async throws -> BackendQuestionBatchResponse {
        throw QuizPreparationError.unavailable
    }

    func resetQuestionProgress(themeID: String, resetID: UUID, session: AuthSession) async throws -> BackendQuestionProgressResetResponse {
        resetCalls.append(ResetCall(themeID: themeID, resetID: resetID, session: session))
        try await beforeReset?()
        return BackendQuestionProgressResetResponse(themeId: themeID, resetId: resetID, resetAt: "2026-10-24T12:00:00Z")
    }
}
