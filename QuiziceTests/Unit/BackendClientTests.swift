import XCTest
@testable import Quizice

final class BackendClientTests: XCTestCase {
    override func tearDown() {
        BackendTestURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testThemeCatalogUsesLocaleEnvelopeAndRecordsDecodedLatency() async throws {
        let metrics = BackendMetricSpy()
        let api = makeContentAPI(metrics: metrics, accessToken: "catalog-token")
        BackendTestURLProtocol.requestHandler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(request.url?.path, "/api/v1/themes")
            XCTAssertEqual(request.url?.query, "locale=ru")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "X-Quizice-Authorization"),
                "Bearer catalog-token"
            )
#if DEBUG
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
#endif
            let body = Data(
                ##"{"locale":"ru","themes":[{"id":"music","name":"Музыка","description":"Описание","sfSymbol":"music.note.list","emoji":"🎵","colorHex":"#FF8252","isFavorite":true}]}"##.utf8
            )
            return Self.response(for: request, data: body)
        }

        let response = try await api.fetchThemes(locale: "ru")

        XCTAssertEqual(response.locale, "ru")
        XCTAssertEqual(response.themes.map(\.id), ["music"])
        XCTAssertEqual(response.themes.map(\.sfSymbol), ["music.note.list"])
        XCTAssertEqual(response.themes.map(\.emoji), ["🎵"])
        XCTAssertEqual(response.themes.map(\.colorHex), ["#FF8252"])
        XCTAssertEqual(response.themes.map(\.isFavorite), [true])
        XCTAssertEqual(response.themes.first?.countries, [])
        XCTAssertEqual(metrics.values.count, 1)
        XCTAssertEqual(metrics.values.first?.operation, .themes)
        XCTAssertEqual(metrics.values.first?.result, .success)
        XCTAssertEqual(metrics.values.first?.statusCode, 200)
        XCTAssertGreaterThanOrEqual(metrics.values.first?.durationMilliseconds ?? -1, 0)
    }

    func testThemePreferencesGETUsesBearerAndPreservesServerOrder() async throws {
        let api = makeContentAPI(accessToken: "preferences-token")
        BackendTestURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/me/theme-preferences")
            XCTAssertEqual(request.url?.query, "locale=ru")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "X-Quizice-Authorization"),
                "Bearer preferences-token"
            )
            let body = Data(
                ##"{"locale":"ru","favoriteThemeIds":["space","music","cinema"]}"##.utf8
            )
            return Self.response(for: request, data: body)
        }

        let response = try await api.fetchThemePreferences(locale: "ru")

        XCTAssertEqual(response.favoriteThemeIds, ["space", "music", "cinema"])
    }

    func testThemePreferencesPUTReplacesOrderedSelection() async throws {
        let api = makeContentAPI(accessToken: "preferences-token")
        BackendTestURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.path, "/api/v1/me/theme-preferences")
            XCTAssertNil(request.url?.query)
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "X-Quizice-Authorization"),
                "Bearer preferences-token"
            )
            let body = try XCTUnwrap(Self.bodyData(from: request))
            let payload = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            XCTAssertEqual(payload["locale"] as? String, "ru")
            XCTAssertEqual(
                payload["favoriteThemeIds"] as? [String],
                ["space", "music", "cinema"]
            )
            return Self.response(for: request, data: body)
        }

        let response = try await api.replaceThemePreferences(
            locale: "ru",
            favoriteThemeIDs: ["space", "music", "cinema"]
        )

        XCTAssertEqual(response.favoriteThemeIds, ["space", "music", "cinema"])
    }

    func testThemePreferencesFailBeforeNetworkWithoutValidSession() async {
        let api = makeContentAPI()

        await assertBackendContentError(.unauthenticated) {
            try await api.fetchThemePreferences(locale: "ru")
        }
    }

    func testQuestionBatchSendsCountLocaleAndSeedAndValidatesQuestions() async throws {
        let api = makeContentAPI()
        let seed = "550e8400-e29b-41d4-a716-446655440000"
        BackendTestURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/themes/history_culture/questions")
            let query = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems)
            XCTAssertEqual(
                Dictionary(uniqueKeysWithValues: query.compactMap { item in
                    item.value.map { (item.name, $0) }
                }),
                ["count": "5", "locale": "fr", "seed": seed]
            )
            let questions = (0..<5).map(Self.questionJSON)
            let body = try JSONSerialization.data(withJSONObject: [
                "locale": "fr",
                "seed": seed,
                "questions": questions
            ])
            return Self.response(for: request, data: body)
        }

        let response = try await api.fetchQuestions(
            themeID: "history_culture",
            count: 5,
            locale: "fr",
            seed: seed
        )

        XCTAssertEqual(response.questions.count, 5)
        XCTAssertEqual(response.questions.first?.questionId, "question-0")
        XCTAssertEqual(response.questions.first?.questionVersion, 1)
        XCTAssertEqual(response.questions.first?.correctAnswer, "B0")
    }

    func testOldBareArrayContractFailsClosed() async {
        let api = makeContentAPI()
        BackendTestURLProtocol.requestHandler = { request in
            let body = Data(
                #"[{"id":"music","name":"Music","description":"Description"}]"#.utf8
            )
            return Self.response(for: request, data: body)
        }

        await assertBackendContentError(.decoding) {
            try await api.fetchThemes(locale: "en")
        }
    }

    func testMismatchedQuestionLocaleOrSeedIsRejected() async {
        let metrics = BackendMetricSpy()
        let api = makeContentAPI(metrics: metrics)
        let requestedSeed = "550e8400-e29b-41d4-a716-446655440000"
        BackendTestURLProtocol.requestHandler = { request in
            let body = try JSONSerialization.data(withJSONObject: [
                "locale": "en",
                "seed": "550e8400-e29b-41d4-a716-446655440001",
                "questions": (0..<5).map(Self.questionJSON)
            ])
            return Self.response(for: request, data: body)
        }

        await assertBackendContentError(.contractViolation) {
            try await api.fetchQuestions(
                themeID: "music",
                count: 5,
                locale: "ru",
                seed: requestedSeed
            )
        }
        XCTAssertEqual(metrics.values.count, 1)
        XCTAssertEqual(metrics.values.first?.result, .contractError)
    }

    func testBundledCatalogUsesBundledQuestionsWithoutCallingBackend() async throws {
        let backend = RecordingBackendContentAPI()
        let repository = ThemeCatalogRepository(
            backendContentAPI: backend,
            seedGenerator: { "seed-1" }
        )
        repository.themes = [Self.localTheme(questionCount: 15)]

        let prepared = try await repository.prepareQuiz(
            themeID: "music",
            questionCount: 5,
            difficulty: .hard,
            locale: "en"
        )

        XCTAssertEqual(prepared.stableID, "music")
        XCTAssertEqual(prepared.questions.count, 5)
        XCTAssertTrue(prepared.questions.allSatisfy { $0.question.hasPrefix("Local") })
        XCTAssertEqual(prepared.questionOrigin, .bundled)
        XCTAssertNil(prepared.difficulty, "Bundled questions have no difficulty labels to filter by")
        XCTAssertEqual(backend.themeRequestCount, 0)
        XCTAssertTrue(backend.seeds.isEmpty)
    }

    func testBackendCatalogReplacesTheEntireBundledCatalogInBackendOrder() async {
        let remoteThemes = (0..<14).map { index in
            BackendThemeDTO(
                id: "remote-\(index)",
                name: "Remote \(index)",
                description: "Description \(index)",
                sfSymbol: "star.fill",
                emoji: "⭐️",
                colorHex: "#4F46E5",
                isFavorite: index < 2
            )
        }
        let backend = RecordingBackendContentAPI(catalogThemes: remoteThemes)
        let repository = ThemeCatalogRepository(backendContentAPI: backend)
        repository.themes = (0..<4).map { index in
            QuizTheme(
                id: "local-\(index)",
                theme: "Local \(index)",
                themeDescription: "Local Description",
                questions: []
            )
        }
        let locale = AppLocalizationStore.shared.resolvedLanguageCode

        let didRefresh = await repository.refreshBackendCatalog(locale: locale)

        XCTAssertTrue(didRefresh)
        XCTAssertEqual(repository.catalogOrigin, .backend)
        XCTAssertEqual(repository.themes?.map(\.stableID), remoteThemes.map(\.id))
        XCTAssertEqual(repository.themes?.map(\.theme), remoteThemes.map(\.name))
        XCTAssertEqual(repository.themes?.count, 14)
        XCTAssertTrue(repository.themes?.allSatisfy(\.questions.isEmpty) == true)
        XCTAssertTrue(repository.themes?.allSatisfy { $0.questionOrigin == .backend } == true)
        XCTAssertTrue(repository.themes?.allSatisfy { $0.sfSymbolName == "star.fill" } == true)
    }

    func testBackendCatalogQuestionFailureDoesNotReturnBundledQuestions() async {
        let backend = RecordingBackendContentAPI(
            questionError: URLError(.timedOut)
        )
        let repository = ThemeCatalogRepository(backendContentAPI: backend)
        repository.themes = [Self.localTheme(questionCount: 15)]
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        let didRefresh = await repository.refreshBackendCatalog(locale: locale)
        XCTAssertTrue(didRefresh)

        do {
            _ = try await repository.prepareQuiz(
                themeID: "music",
                questionCount: 5,
                locale: locale
            )
            XCTFail("Backend catalog mode must not fall back to bundled questions")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
        XCTAssertEqual(backend.seeds.count, 1)
    }

    func testEachQuizPreparationUsesANewLowercaseUUIDSeed() async throws {
        let backend = RecordingBackendContentAPI()
        let repository = ThemeCatalogRepository(backendContentAPI: backend)
        repository.themes = [Self.localTheme(questionCount: 15)]
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        let didRefresh = await repository.refreshBackendCatalog(locale: locale)
        XCTAssertTrue(didRefresh)

        let prepared = try await repository.prepareQuiz(themeID: "music", questionCount: 5, locale: locale)
        _ = try await repository.prepareQuiz(themeID: "music", questionCount: 5, locale: locale)

        XCTAssertEqual(prepared.questionOrigin, .backend)
        XCTAssertEqual(backend.seeds.count, 2)
        XCTAssertNotEqual(backend.seeds[0], backend.seeds[1])
        XCTAssertTrue(backend.seeds.allSatisfy { UUID(uuidString: $0) != nil })
        XCTAssertTrue(backend.seeds.allSatisfy { $0 == $0.lowercased() })
    }

    func testCatalogOriginRemainsBackendWhenSubsequentRefreshFails() async {
        let backend = SequencedCatalogBackendContentAPI()
        let repository = ThemeCatalogRepository(backendContentAPI: backend)
        repository.themes = [Self.localTheme(questionCount: 15)]
        let locale = AppLocalizationStore.shared.resolvedLanguageCode

        let firstRefreshSucceeded = await repository.refreshBackendCatalog(locale: locale)
        let secondRefreshSucceeded = await repository.refreshBackendCatalog(locale: locale)

        XCTAssertTrue(firstRefreshSucceeded)
        XCTAssertFalse(secondRefreshSucceeded)
        XCTAssertEqual(repository.catalogOrigin, .backend)
        XCTAssertEqual(repository.themes?.first?.theme, "Remote Music")
    }

    func testBackendCatalogPublishesNewThemesAndPreparesTheirQuestionsRemotely() async throws {
        let backend = RecordingBackendContentAPI(
            catalogThemes: [
                BackendThemeDTO(
                    id: "music",
                    name: "Remote Music",
                    description: "Known theme",
                    sfSymbol: "music.note.list",
                    emoji: "🎵",
                    colorHex: "#FF8252",
                    isFavorite: true
                ),
                BackendThemeDTO(
                    id: "space",
                    name: "Space",
                    description: "Backend-only theme",
                    sfSymbol: "globe",
                    emoji: "🚀",
                    colorHex: "#4F46E5",
                    isFavorite: false
                )
            ]
        )
        let repository = ThemeCatalogRepository(backendContentAPI: backend)
        repository.themes = [Self.localTheme(questionCount: 15)]
        let locale = AppLocalizationStore.shared.resolvedLanguageCode

        let didRefresh = await repository.refreshBackendCatalog(locale: locale)
        let themes = try XCTUnwrap(repository.themes)

        XCTAssertTrue(didRefresh)
        XCTAssertEqual(themes.map(\.stableID), ["music", "space"])
        XCTAssertTrue(themes[0].questions.isEmpty)
        XCTAssertEqual(themes[0].questionOrigin, .backend)
        XCTAssertTrue(themes[1].questions.isEmpty)
        XCTAssertEqual(themes[1].questionOrigin, .backend)
        XCTAssertEqual(themes[1].sfSymbolName, "globe")
        XCTAssertEqual(themes[1].emoji, "🚀")
        XCTAssertEqual(themes[1].colorHex, "#4F46E5")
        XCTAssertTrue(themes[0].isFavorite)
        XCTAssertFalse(themes[1].isFavorite)

        let prepared = try await repository.prepareQuiz(
            themeID: "space",
            questionCount: 5,
            locale: locale
        )

        XCTAssertEqual(prepared.stableID, "space")
        XCTAssertEqual(prepared.questions.count, 5)
        XCTAssertEqual(prepared.questionOrigin, .backend)
    }

    func testPendingLocalThemePreferencesArePUTInTheirSavedOrder() async {
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        let (store, defaults, suiteName) = makePreferenceStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        store.complete(preferredThemeIDs: ["space", "music"], locale: locale)
        let backend = ThemePreferencesBackendContentAPI(
            catalogThemes: Self.preferenceCatalog
        )
        let repository = ThemeCatalogRepository(
            backendContentAPI: backend,
            preferenceStore: store
        )

        _ = await repository.refreshBackendCatalog(locale: locale)
        let didSynchronize = await repository.synchronizeThemePreferences(locale: locale)

        XCTAssertTrue(didSynchronize)
        XCTAssertEqual(backend.fetchedPreferenceLocales, [])
        XCTAssertEqual(backend.replacedPreferences.count, 1)
        XCTAssertEqual(backend.replacedPreferences.first?.locale, locale)
        XCTAssertEqual(backend.replacedPreferences.first?.themeIDs, ["space", "music"])
        XCTAssertEqual(
            store.orderedPreferredThemeIDs(locale: locale),
            ["space", "music"]
        )
        XCTAssertFalse(store.hasPendingThemePreferences(locale: locale))
        XCTAssertEqual(repository.themes?.map(\.stableID), ["space", "music", "cinema"])
        XCTAssertEqual(repository.themes?.map(\.isFavorite), [true, true, false])
    }

    func testRemoteThemePreferencesBecomeLocalSourceOfTruthWhenNothingIsPending() async {
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        let (store, defaults, suiteName) = makePreferenceStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let backend = ThemePreferencesBackendContentAPI(
            catalogThemes: Self.preferenceCatalog,
            remoteFavoriteThemeIDs: ["cinema", "music"]
        )
        let repository = ThemeCatalogRepository(
            backendContentAPI: backend,
            preferenceStore: store
        )

        _ = await repository.refreshBackendCatalog(locale: locale)
        let didSynchronize = await repository.synchronizeThemePreferences(locale: locale)

        XCTAssertTrue(didSynchronize)
        XCTAssertEqual(backend.fetchedPreferenceLocales, [locale])
        XCTAssertTrue(backend.replacedPreferences.isEmpty)
        XCTAssertEqual(
            store.orderedPreferredThemeIDs(locale: locale),
            ["cinema", "music"]
        )
        XCTAssertEqual(repository.themes?.map(\.stableID), ["cinema", "music", "space"])
        XCTAssertEqual(repository.themes?.map(\.isFavorite), [true, true, false])
    }

    func testOfflinePreferenceSyncKeepsPendingLocalSelectionForRetry() async {
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        let (store, defaults, suiteName) = makePreferenceStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        store.complete(preferredThemeIDs: ["space"], locale: locale)
        let backend = ThemePreferencesBackendContentAPI(
            catalogThemes: Self.preferenceCatalog
        )
        backend.preferencesError = BackendContentError.transport(.notConnectedToInternet)
        let repository = ThemeCatalogRepository(
            backendContentAPI: backend,
            preferenceStore: store
        )

        _ = await repository.refreshBackendCatalog(locale: locale)
        let didSynchronize = await repository.synchronizeThemePreferences(locale: locale)

        XCTAssertFalse(didSynchronize)
        XCTAssertEqual(backend.replacedPreferences.first?.themeIDs, ["space"])
        XCTAssertEqual(store.orderedPreferredThemeIDs(locale: locale), ["space"])
        XCTAssertTrue(store.hasPendingThemePreferences(locale: locale))
    }

    func testBackendAIRejectsGuestBeforeCreatingNetworkRequest() async {
        let session = makeSession()
        let staleSession = AuthSession(
            userID: "previous-user",
            accessToken: "still-valid-stale-token",
            expiresAt: Date(timeIntervalSince1970: 4_000_000_000),
            teamPlayerID: "previous-team"
        )
        let api = BackendAIQuizThemeService(
            configuration: Self.configuration,
            session: session,
            sessionStore: BackendMemorySessionStore(session: staleSession),
            accessProvider: BackendAIQuizAccessStub(isAvailable: false)
        )
        BackendTestURLProtocol.requestHandler = { request in
            XCTFail("Guest must not call the AI endpoint: \(request)")
            throw URLError(.cancelled)
        }

        do {
            _ = try await api.generateQuizTheme(configuration: Self.aiConfiguration)
            XCTFail("Expected authenticationRequired")
        } catch let error as YandexAIQuizThemeServiceError {
            XCTAssertEqual(error, .authenticationRequired)
            XCTAssertEqual(AIQuizGenerationAlert(error: error).kind, .authentication)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testBackendAIExpiredSessionInvalidatesAuthenticationWithoutNetworkRequest() async {
        let session = makeSession()
        let store = BackendMemorySessionStore(
            session: AuthSession(
                userID: "user-1",
                accessToken: "expiring-token",
                expiresAt: Date(timeIntervalSince1970: 1_020),
                teamPlayerID: "team-1"
            )
        )
        let access = BackendAIQuizAccessStub(isAvailable: true)
        let notificationCenter = NotificationCenter()
        var invalidationCount = 0
        let observer = notificationCenter.addObserver(
            forName: .backendAuthenticationInvalidated,
            object: nil,
            queue: nil
        ) { _ in
            invalidationCount += 1
        }
        defer { notificationCenter.removeObserver(observer) }
        let api = BackendAIQuizThemeService(
            configuration: Self.configuration,
            session: session,
            sessionStore: store,
            now: { Date(timeIntervalSince1970: 1_000) },
            accessProvider: access,
            notificationCenter: notificationCenter
        )
        BackendTestURLProtocol.requestHandler = { request in
            XCTFail("An expiring session must be refreshed before AI networking: \(request)")
            throw URLError(.cancelled)
        }

        await assertAIError(.authenticationRequired) {
            try await api.generateQuizTheme(configuration: Self.aiConfiguration)
        }

        XCTAssertNil(store.session)
        XCTAssertFalse(access.isAIQuizAvailable)
        XCTAssertEqual(invalidationCount, 1)
    }

    func testBackendAIUnauthorizedResponseInvalidatesAuthenticationOnce() async {
        let session = makeSession()
        let storedSession = AuthSession(
            userID: "user-1",
            accessToken: "expired-server-token",
            expiresAt: Date(timeIntervalSince1970: 4_000_000_000),
            teamPlayerID: "team-1"
        )
        let store = BackendMemorySessionStore(session: storedSession)
        let access = BackendAIQuizAccessStub(isAvailable: true)
        let notificationCenter = NotificationCenter()
        var invalidationCount = 0
        let observer = notificationCenter.addObserver(
            forName: .backendAuthenticationInvalidated,
            object: nil,
            queue: nil
        ) { _ in
            invalidationCount += 1
        }
        defer { notificationCenter.removeObserver(observer) }
        let api = BackendAIQuizThemeService(
            configuration: Self.configuration,
            session: session,
            sessionStore: store,
            now: { Date(timeIntervalSince1970: 1_000) },
            accessProvider: access,
            notificationCenter: notificationCenter
        )
        var requestCount = 0
        BackendTestURLProtocol.requestHandler = { request in
            requestCount += 1
            return Self.response(
                for: request,
                statusCode: 401,
                data: Data(#"{"requestId":"request-1","code":"unauthorized","message":"expired"}"#.utf8)
            )
        }

        await assertAIError(.authenticationRequired) {
            try await api.generateQuizTheme(configuration: Self.aiConfiguration)
        }

        XCTAssertEqual(requestCount, 1)
        XCTAssertNil(store.session)
        XCTAssertFalse(access.isAIQuizAvailable)
        XCTAssertEqual(invalidationCount, 1)
    }

    func testBackendAIForbiddenResponseDisablesAIWithoutClearingAuthentication() async {
        let session = makeSession()
        let storedSession = AuthSession(
            userID: "user-1",
            accessToken: "valid-token",
            expiresAt: Date(timeIntervalSince1970: 4_000_000_000),
            teamPlayerID: "team-1"
        )
        let store = BackendMemorySessionStore(session: storedSession)
        let access = BackendAIQuizAccessStub(isAvailable: true)
        let notificationCenter = NotificationCenter()
        var invalidationCount = 0
        let observer = notificationCenter.addObserver(
            forName: .backendAuthenticationInvalidated,
            object: nil,
            queue: nil
        ) { _ in
            invalidationCount += 1
        }
        defer { notificationCenter.removeObserver(observer) }
        let api = BackendAIQuizThemeService(
            configuration: Self.configuration,
            session: session,
            sessionStore: store,
            now: { Date(timeIntervalSince1970: 1_000) },
            accessProvider: access,
            notificationCenter: notificationCenter
        )
        BackendTestURLProtocol.requestHandler = { request in
            Self.response(
                for: request,
                statusCode: 403,
                data: Data(#"{"requestId":"request-2","code":"forbidden","message":"forbidden"}"#.utf8)
            )
        }

        await assertAIError(.httpStatus(403)) {
            try await api.generateQuizTheme(configuration: Self.aiConfiguration)
        }

        XCTAssertEqual(store.session, storedSession)
        XCTAssertFalse(access.isAIQuizAvailable)
        XCTAssertEqual(invalidationCount, 0)
    }

    func testPersonalizedQuestionStrategiesMapToProgressModeAndBearer() async throws {
        let seed = "550e8400-e29b-41d4-a716-446655440000"
        for (strategy, expectedMode) in [
            (QuestionRepeatStrategy.hideAnswered, "all_answered"),
            (.retryIncorrect, "correct_only")
        ] {
            let api = makeContentAPI(accessToken: "progress-token")
            BackendTestURLProtocol.requestHandler = { request in
                let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
                XCTAssertEqual(items?.first(where: { $0.name == "progressMode" })?.value, expectedMode)
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Quizice-Authorization"), "Bearer progress-token")
                let body = try JSONSerialization.data(withJSONObject: [
                    "locale": "ru",
                    "seed": seed,
                    "progressMode": expectedMode,
                    "availableCount": 1,
                    "questions": [Self.questionJSON(index: 0)]
                ])
                return Self.response(for: request, data: body)
            }
            let response = try await api.fetchQuestions(
                themeID: "music",
                count: 5,
                locale: "ru",
                difficulty: .medium,
                seed: seed,
                strategy: strategy
            )
            XCTAssertEqual(response.questions.count, 1)
            XCTAssertEqual(response.availableCount, 1)
        }
    }

    func testGuestRepeatStrategyAlwaysFallsBackToShowAll() {
        XCTAssertEqual(
            QuestionRepeatStrategy.hideAnswered.effective(hasValidBackendSession: false),
            .showAll
        )
        XCTAssertEqual(
            QuestionRepeatStrategy.retryIncorrect.effective(hasValidBackendSession: false),
            .showAll
        )
        XCTAssertEqual(
            QuestionRepeatStrategy.hideAnswered.effective(hasValidBackendSession: true),
            .hideAnswered
        )
    }

    func testShowAllOmitsProgressModeAndAllowsEmptyGuestBatch() async throws {
        let seed = "550e8400-e29b-41d4-a716-446655440000"
        let api = makeContentAPI()
        BackendTestURLProtocol.requestHandler = { request in
            XCTAssertFalse(request.url?.query?.contains("progressMode") ?? false)
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Quizice-Authorization"))
            let body = Data(
                "{\"locale\":\"ru\",\"seed\":\"\(seed)\",\"availableCount\":0,\"questions\":[]}".utf8
            )
            return Self.response(for: request, data: body)
        }
        let response = try await api.fetchQuestions(
            themeID: "music",
            count: 5,
            locale: "ru",
            difficulty: .medium,
            seed: seed,
            strategy: .showAll
        )
        XCTAssertTrue(response.questions.isEmpty)
    }

    func testQuestionAnswerBatchUsesBearerAndEncodesTimeoutAsNull() async throws {
        let eventID = UUID()
        let api = makeContentAPI(accessToken: "answer-token")
        BackendTestURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/me/question-answers")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Quizice-Authorization"), "Bearer answer-token")
            let body = try XCTUnwrap(Self.bodyData(from: request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let events = try XCTUnwrap(json["events"] as? [[String: Any]])
            XCTAssertTrue(events[0]["answer"] is NSNull)
            return Self.response(
                for: request,
                data: Data("{\"processedEventIds\":[\"\(eventID.uuidString)\"]}".utf8)
            )
        }
        let response = try await api.submitQuestionAnswers([
            QuestionAnswerEvent(
                eventId: eventID,
                questionId: "music:0001",
                questionVersion: 1,
                locale: "ru",
                answer: nil,
                answeredAt: Date(timeIntervalSince1970: 1_000)
            )
        ])
        XCTAssertEqual(response.processedEventIds, [eventID])
    }

    func testProtectedRequestReauthenticatesAndRetriesExactlyOnceAfter401() async throws {
        let recoverer = BackendAuthenticationRecovererSpy(refreshedToken: "fresh-token")
        let api = makeContentAPI(
            accessToken: "rejected-token",
            authenticationRecoverer: recoverer
        )
        var authorizationHeaders: [String?] = []
        BackendTestURLProtocol.requestHandler = { request in
            authorizationHeaders.append(request.value(forHTTPHeaderField: "X-Quizice-Authorization"))
            if authorizationHeaders.count == 1 {
                return Self.response(
                    for: request,
                    statusCode: 401,
                    data: Data(#"{"code":"unauthorized"}"#.utf8)
                )
            }
            return Self.response(
                for: request,
                data: Data(#"{"locale":"ru","favoriteThemeIds":["music"]}"#.utf8)
            )
        }

        let response = try await api.fetchThemePreferences(locale: "ru")

        XCTAssertEqual(response.favoriteThemeIds, ["music"])
        XCTAssertEqual(authorizationHeaders, ["Bearer rejected-token", "Bearer fresh-token"])
        XCTAssertEqual(recoverer.rejectedTokens, ["rejected-token"])
    }

    func testSecond401DoesNotStartAnotherAuthenticationCycle() async {
        let recoverer = BackendAuthenticationRecovererSpy(refreshedToken: "fresh-token")
        let api = makeContentAPI(
            accessToken: "rejected-token",
            authenticationRecoverer: recoverer
        )
        var requestCount = 0
        BackendTestURLProtocol.requestHandler = { request in
            requestCount += 1
            return Self.response(
                for: request,
                statusCode: 401,
                data: Data(#"{"code":"unauthorized"}"#.utf8)
            )
        }

        await assertBackendContentError(.httpStatus(401, nil)) {
            try await api.fetchThemePreferences(locale: "ru")
        }

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(recoverer.rejectedTokens, ["rejected-token"])
    }

    func testAnswerOutboxRetriesTheSameEventIDAndDeletesOnlyProcessedEvents() async {
        let processedID = UUID()
        let pendingID = UUID()
        let api = QuestionAnswerBackendContentAPI(submitResults: [
            .failure(BackendContentError.transport(.notConnectedToInternet)),
            .success(QuestionAnswerBatchResponse(processedEventIds: [processedID])),
            .success(QuestionAnswerBatchResponse(processedEventIds: []))
        ])
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuiziceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: testDirectory) }
        let fileURL = testDirectory
            .appendingPathComponent("outbox.json")
        let outbox = PersistentQuestionAnswerOutbox(
            api: api,
            fileURL: fileURL,
            automaticallySynchronizesOnEnqueue: false,
            sessionProvider: { AuthSession(userID: "A", accessToken: "token-A", expiresAt: .distantFuture, teamPlayerID: "A") },
            retryDelay: 0
        )
        let processedEvent = QuestionAnswerEvent(
            eventId: processedID,
            questionId: "music:1",
            questionVersion: 1,
            locale: "ru",
            answer: "A",
            answeredAt: Date(timeIntervalSince1970: 1_000)
        )
        let pendingEvent = QuestionAnswerEvent(
            eventId: pendingID,
            questionId: "music:2",
            questionVersion: 1,
            locale: "ru",
            answer: "B",
            answeredAt: Date(timeIntervalSince1970: 2_000)
        )
        outbox.enqueue(processedEvent)
        outbox.enqueue(pendingEvent)

        await outbox.synchronize()

        XCTAssertEqual(api.submittedBatches.count, 3)
        XCTAssertEqual(api.submittedBatches[0].map(\.eventId), [processedID, pendingID])
        XCTAssertEqual(api.submittedBatches[1].map(\.eventId), [processedID, pendingID])
        XCTAssertEqual(api.submittedBatches[2].map(\.eventId), [pendingID])
        XCTAssertEqual(outbox.pendingEvents().map(\.eventId), [pendingID])
    }

}

extension BackendClientTests {
    private func progressEvent(_ id: String = "music:1") -> QuestionAnswerEvent {
        QuestionAnswerEvent(eventId: UUID(), questionId: id, questionVersion: 1,
                            locale: "ru", answer: "A", answeredAt: Date(timeIntervalSince1970: 1234))
    }

    func testAnswerOutboxSeparatesAccountsAcrossRestartAndKeepsLateResponsesScoped() async throws {
        let provider = ProgressSessionProvider()
        let first = progressEvent()
        let second = progressEvent("music:2")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let api = QuestionAnswerBackendContentAPI(submitResults: [])
        api.onSubmit = { events in
            provider.session = ProgressSessionProvider.session("B")
            return QuestionAnswerBatchResponse(processedEventIds: events.map(\.eventId))
        }
        let outbox = PersistentQuestionAnswerOutbox(api: api, fileURL: url,
            automaticallySynchronizesOnEnqueue: false, sessionProvider: { provider.session }, retryDelay: 0)
        outbox.enqueue(first)
        provider.session = ProgressSessionProvider.session("B")
        outbox.enqueue(second)
        let restored = PersistentQuestionAnswerOutbox(api: api, fileURL: url,
            automaticallySynchronizesOnEnqueue: false, sessionProvider: { provider.session }, retryDelay: 0)
        provider.session = ProgressSessionProvider.session("A")
        await restored.synchronize()
        XCTAssertEqual(api.submittedBatches.map { $0.map(\.eventId) }, [[first.eventId]])
        XCTAssertEqual(api.submittedSessions.map(\.userID), ["A"])
        XCTAssertEqual(restored.pendingEvents(), [second])
        await restored.synchronize()
        XCTAssertEqual(api.submittedSessions.map(\.userID), ["A", "B"])
        XCTAssertTrue(restored.pendingEvents().isEmpty)
    }

    func testOwnerlessLegacyAnswersArePreservedButNeverAssignedToCurrentAccount() async throws {
        let event = progressEvent()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([event]).write(to: url)
        let api = QuestionAnswerBackendContentAPI(submitResults: [])
        let outbox = PersistentQuestionAnswerOutbox(api: api, fileURL: url,
            automaticallySynchronizesOnEnqueue: false,
            sessionProvider: { ProgressSessionProvider.session("B") })
        await outbox.synchronize()
        XCTAssertTrue(api.submittedBatches.isEmpty)
        XCTAssertEqual(outbox.pendingEvents(), [event])
    }

    func testDeletionDuringAnswerUploadDiscardsItsLateResponseAndStopsRetries() async throws {
        let removed = progressEvent("deleted")
        let kept = progressEvent("another-account")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let api = QuestionAnswerBackendContentAPI(submitResults: [])
        let outbox = PersistentQuestionAnswerOutbox(api: api, fileURL: url,
            automaticallySynchronizesOnEnqueue: false,
            sessionProvider: { ProgressSessionProvider.session("A") }, retryDelay: 0)
        outbox.enqueue(removed, for: "A")
        outbox.enqueue(kept, for: "B")
        api.onSubmit = { events in
            try outbox.eraseData(for: "A")
            return QuestionAnswerBatchResponse(processedEventIds: events.map(\.eventId))
        }

        await outbox.synchronize()
        await outbox.synchronize()

        XCTAssertEqual(api.submittedBatches.count, 1)
        XCTAssertEqual(outbox.pendingEvents(), [kept])
        XCTAssertTrue(outbox.rejectedEvents().isEmpty)
        XCTAssertNil(outbox.currentUserID)
    }

    func testPermanentAnswerFailureIsIsolatedAndHealthyEventsContinue() async throws {
        for status in [409, 422] {
            let good = progressEvent("good")
            let bad = progressEvent("bad")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: url) }
            let api = QuestionAnswerBackendContentAPI(submitResults: [])
            api.onSubmit = { events in
                if events.contains(where: { $0.eventId == bad.eventId }) {
                    throw BackendContentError.httpStatus(status,
                        BackendErrorEnvelope(code: "question_version_conflict", message: "Invalid version"))
                }
                return QuestionAnswerBatchResponse(processedEventIds: events.map(\.eventId))
            }
            let outbox = PersistentQuestionAnswerOutbox(api: api, fileURL: url,
                automaticallySynchronizesOnEnqueue: false,
                sessionProvider: { ProgressSessionProvider.session("A") }, retryDelay: 0)
            outbox.enqueue(bad)
            outbox.enqueue(good)
            try await outbox.synchronizeBeforeFetchingQuestions(for: "A")
            XCTAssertEqual(api.submittedBatches.map { $0.map(\.eventId) }, [[bad.eventId, good.eventId], [bad.eventId], [good.eventId]])
            XCTAssertTrue(outbox.pendingEvents().isEmpty)
            XCTAssertEqual(outbox.rejectedEvents().first?.ownedEvent.event, bad)
            XCTAssertEqual(outbox.rejectedEvents().first?.status, status)
            await outbox.synchronize()
            XCTAssertEqual(api.submittedBatches.count, 3)
        }
    }

    func testTransientAnswerFailureRetriesSamePayloadAndBlocksPersonalizedFetch() async throws {
        let event = progressEvent()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let api = QuestionAnswerBackendContentAPI(submitResults: [])
        api.onSubmit = { _ in throw BackendContentError.httpStatus(503, nil) }
        let outbox = PersistentQuestionAnswerOutbox(api: api, fileURL: url,
            automaticallySynchronizesOnEnqueue: false,
            sessionProvider: { ProgressSessionProvider.session("A") }, retryDelay: 0)
        outbox.enqueue(event)
        do {
            try await outbox.synchronizeBeforeFetchingQuestions(for: "A")
            XCTFail("A fetch must not continue with unconfirmed answers")
        } catch {}
        XCTAssertEqual(api.submittedBatches, [[event], [event], [event]])
        XCTAssertEqual(outbox.pendingEvents(), [event])
    }

    func testUnauthorizedAnswerKeepsQueueWithoutRetryingAsAnotherAccount() async {
        let event = progressEvent()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let provider = ProgressSessionProvider()
        let api = QuestionAnswerBackendContentAPI(submitResults: [])
        api.onSubmit = { _ in
            provider.session = ProgressSessionProvider.session("B")
            throw BackendContentError.httpStatus(401, nil)
        }
        let outbox = PersistentQuestionAnswerOutbox(api: api, fileURL: url,
            automaticallySynchronizesOnEnqueue: false, sessionProvider: { provider.session }, retryDelay: 0)
        outbox.enqueue(event)
        await outbox.synchronize()
        await outbox.synchronize()
        XCTAssertEqual(api.submittedSessions.map(\.userID), ["A"])
        XCTAssertEqual(outbox.pendingEvents(), [event])
    }

    func testPersonalizedQuizSynchronizesBeforeEachThemeAndRandomFetch() async throws {
        let backend = RecordingBackendContentAPI()
        let outbox = ProgressOutboxSpy()
        let provider = ProgressSessionProvider()
        var syncCount = 0
        outbox.beforeFetch = { syncCount += 1 }
        backend.onQuestions = { XCTAssertEqual(syncCount, backend.seeds.count) }
        let repository = ThemeCatalogRepository(backendContentAPI: backend,
            accessTokenProvider: provider, answerOutbox: outbox, repeatStrategyProvider: { .hideAnswered })
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        _ = await repository.refreshBackendCatalog(locale: locale)
        _ = try await repository.prepareQuiz(themeID: "music", questionCount: 5, locale: locale)
        for mode in CrossThemeQuestionSelectionMode.allCases {
            _ = try await repository.prepareRandomQuiz(selectionMode: mode, localFallback: Self.localTheme(questionCount: 5), questionCount: 5, locale: locale)
        }
        XCTAssertEqual(outbox.synchronizedUsers, ["A", "A", "A"])
        outbox.beforeFetch = { throw BackendContentError.httpStatus(503, nil) }
        do {
            _ = try await repository.prepareQuiz(themeID: "music", questionCount: 5, locale: locale)
            XCTFail("Must not fetch after failed synchronization")
        } catch {}
        XCTAssertEqual(backend.seeds.count, 3)
    }

    func testFilteredQuestionCountsPreserveEveryIssuedQuestion() async throws {
        let backend = RecordingBackendContentAPI()
        let repository = ThemeCatalogRepository(backendContentAPI: backend,
            accessTokenProvider: NoopBackendAccessTokenProvider(), answerOutbox: NoopQuestionAnswerOutbox())
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        _ = await repository.refreshBackendCatalog(locale: locale)
        for count in 0...15 {
            backend.returnedQuestionCount = count
            let theme = try await repository.prepareQuiz(themeID: "music", questionCount: 15, locale: locale)
            XCTAssertEqual(theme.questions.count, count)
        }
    }

    func testQuestionResponseForPreviousAccountIsRejected() async throws {
        let provider = ProgressSessionProvider()
        let backend = RecordingBackendContentAPI()
        backend.onQuestions = { provider.session = ProgressSessionProvider.session("B") }
        let repository = ThemeCatalogRepository(backendContentAPI: backend,
            accessTokenProvider: provider, answerOutbox: ProgressOutboxSpy(), repeatStrategyProvider: { .hideAnswered })
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        _ = await repository.refreshBackendCatalog(locale: locale)
        do {
            _ = try await repository.prepareQuiz(themeID: "music", questionCount: 5, locale: locale)
            XCTFail("Do not deliver A's personalized response to B")
        } catch { XCTAssertTrue(error is QuestionAnswerSyncError) }
    }
}

extension BackendClientTests {
    func testConcurrentSyncSharesUploadAndKeepsAnswersEnqueuedDuringRequest() async throws {
        let first = progressEvent()
        let second = progressEvent("music:2")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let started = expectation(description: "First upload started")
        let gate = ProgressUploadGate()
        let api = QuestionAnswerBackendContentAPI(submitResults: [])
        api.onSubmit = { events in
            if events.contains(first) {
                started.fulfill()
                await gate.wait()
            }
            return QuestionAnswerBatchResponse(processedEventIds: events.map(\.eventId))
        }
        let outbox = PersistentQuestionAnswerOutbox(api: api, fileURL: url,
            automaticallySynchronizesOnEnqueue: false,
            sessionProvider: { ProgressSessionProvider.session("A") }, retryDelay: 0)
        outbox.enqueue(first)
        let automatic = Task { await outbox.synchronize() }
        await fulfillment(of: [started], timeout: 2)
        outbox.enqueue(second)
        let beforeFetch = Task { try await outbox.synchronizeBeforeFetchingQuestions(for: "A") }
        await gate.open()
        await automatic.value
        try await beforeFetch.value
        XCTAssertEqual(api.submittedBatches, [[first], [second]])
        XCTAssertTrue(outbox.pendingEvents().isEmpty)
    }

    func testHTTPAnswerRetryCannotUseRefreshedTokenOfAnotherUser() async throws {
        let provider = ProgressSessionProvider()
        let originalSession = try XCTUnwrap(provider.session)
        let recoverer = ProgressAuthenticationRecoverer {
            provider.session = ProgressSessionProvider.session("B")
            return "token-B"
        }
        let api = HTTPBackendContentAPI(configuration: Self.configuration, session: makeSession(),
            accessTokenProvider: provider, authenticationRecoverer: recoverer)
        var requests = 0
        BackendTestURLProtocol.requestHandler = { request in
            requests += 1
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Quizice-Authorization"), "Bearer token-A")
            return Self.response(for: request, statusCode: 401, data: Data())
        }
        await assertBackendContentError(.unauthenticated) {
            try await api.submitQuestionAnswers([self.progressEvent()], session: originalSession)
        }
        XCTAssertEqual(requests, 1)
    }
}

extension BackendClientTests {
    func testCountryIsIndependentOfLocaleOnAllQuestionRoutes() async throws {
        let api = makeContentAPI()
        let seed = "550e8400-e29b-41d4-a716-446655440000"
        for locale in ["de", "en", "es", "fr", "it", "ru"] {
            for country in QuestionCountryStore.supportedCodes.sorted() {
                for route in ["themes/politics_business/questions", "questions/random", "questions/random_balanced"] {
                    BackendTestURLProtocol.requestHandler = { request in
                        XCTAssertEqual(request.url?.path, "/api/v1/\(route)")
                        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                        let values = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })
                        XCTAssertEqual(values["locale"], locale)
                        XCTAssertEqual(values["country"], country)
                        XCTAssertEqual(values["difficulty"], "hard")
                        XCTAssertEqual(values["seed"], seed)
                        return Self.response(for: request, data: try JSONSerialization.data(withJSONObject: [
                            "locale": locale, "seed": seed, "country": country,
                            "availableCount": 19, "questions": (0..<5).map(Self.questionJSON)
                        ]))
                    }
                    let response: BackendQuestionBatchResponse
                    if route.hasPrefix("themes") {
                        response = try await api.fetchQuestions(
                            themeID: "politics_business", count: 5, locale: locale,
                            difficulty: .hard, seed: seed, strategy: .showAll, country: country
                        )
                    } else {
                        response = try await api.fetchRandomQuestions(
                            selectionMode: route == "questions/random" ? .random : .randomBalanced,
                            count: 5, locale: locale, difficulty: .hard, seed: seed,
                            strategy: .showAll, country: country
                        )
                    }
                    XCTAssertEqual(response.country, country)
                    XCTAssertEqual(response.availableCount, 19)
                    XCTAssertEqual(response.questions.count, 5)
                }
            }
        }
    }

    func testInternationalSelectionOmitsCountryAndAcceptsExhaustedPool() async throws {
        let api = makeContentAPI()
        let seed = "550e8400-e29b-41d4-a716-446655440000"
        BackendTestURLProtocol.requestHandler = { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertFalse(query.contains { $0.name == "country" })
            return Self.response(for: request, data: try JSONSerialization.data(withJSONObject: [
                "locale": "ru", "seed": seed, "availableCount": 0, "questions": []
            ]))
        }
        let response = try await api.fetchQuestions(
            themeID: "politics_business", count: 5, locale: "ru", difficulty: .medium,
            seed: seed, strategy: .showAll, country: nil
        )
        XCTAssertNil(response.country)
        XCTAssertTrue(response.questions.isEmpty)
    }

    func testInvalidCountryIsRejectedBeforeSendingRequest() async {
        let api = makeContentAPI()
        BackendTestURLProtocol.requestHandler = { _ in
            XCTFail("Invalid country must not reach the server")
            throw URLError(.badURL)
        }
        for country in ["", "us", "GB", " US "] {
            await assertBackendContentError(.invalidRequest) {
                try await api.fetchQuestions(
                    themeID: "politics_business", count: 5, locale: "ru", difficulty: .medium,
                    seed: "550e8400-e29b-41d4-a716-446655440000", strategy: .showAll, country: country
                )
            }
        }
    }

    func testCountryEchoMismatchIsRejected() async {
        let api = makeContentAPI()
        let seed = "550e8400-e29b-41d4-a716-446655440000"
        for responseCountry in [nil, "RU"] as [String?] {
            BackendTestURLProtocol.requestHandler = { request in
                var body: [String: Any] = ["locale": "ru", "seed": seed, "questions": (0..<5).map(Self.questionJSON)]
                body["country"] = responseCountry
                return Self.response(for: request, data: try JSONSerialization.data(withJSONObject: body))
            }
            await assertBackendContentError(.contractViolation) {
                try await api.fetchQuestions(
                    themeID: "politics_business", count: 5, locale: "ru", difficulty: .medium,
                    seed: seed, strategy: .showAll, country: "US"
                )
            }
        }
    }

    func testCountryPreferencePersistsIndependentlyAndClearsForInternational() {
        let suite = "QuestionCountry.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QuestionCountryStore(defaults: defaults)
        XCTAssertNil(store.country)
        store.country = "US"
        defaults.set("ru", forKey: AppLocalizationStore.Keys.language)
        XCTAssertEqual(QuestionCountryStore(defaults: defaults).country, "US")
        store.country = nil
        XCTAssertNil(QuestionCountryStore(defaults: defaults).country)
        defaults.set("GB", forKey: QuestionCountryStore.defaultsKey)
        XCTAssertNil(store.country)
    }

    @MainActor
    func testRepositoryUsesCountryForEachNewRoundAndRejectsStaleBatch() async throws {
        let backend = RecordingBackendContentAPI(catalogThemes: [BackendThemeDTO(
            id: "politics_business", name: "Politics", description: "Description",
            sfSymbol: "globe", emoji: "🌍", colorHex: "#FF8252", isFavorite: false,
            countries: ["DE", "US", "ES", "FR", "IT", "RU"]
        )])
        var country: String? = "US"
        let repository = ThemeCatalogRepository(backendContentAPI: backend, countryProvider: { country })
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        let refreshed = await repository.refreshBackendCatalog(locale: locale)
        XCTAssertTrue(refreshed)
        for choice in ["US", "DE", nil] as [String?] {
            country = choice
            let prepared = try await repository.prepareQuiz(themeID: "politics_business", questionCount: 5, locale: locale)
            XCTAssertEqual(backend.requestedCountries.last!, choice)
            XCTAssertEqual(prepared.countries, ["DE", "US", "ES", "FR", "IT", "RU"])
        }
        country = "US"
        backend.onQuestions = { country = "FR" }
        do {
            _ = try await repository.prepareQuiz(themeID: "politics_business", questionCount: 5, locale: locale)
            XCTFail("A response for the previous country must be discarded")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
}

extension BackendClientTests {
    func testCountryCatalogDecodesSupportedCodes() async throws {
        let api = makeContentAPI()
        BackendTestURLProtocol.requestHandler = { request in
            let data = try JSONSerialization.data(withJSONObject: [
                "locale": "ru", "themes": [[
                    "id": "politics_business", "name": "Политика и бизнес", "description": "Описание",
                    "sfSymbol": "globe", "emoji": "🌍", "colorHex": "#FF8252", "isFavorite": false,
                    "countries": ["DE", "US", "ES", "FR", "IT", "RU"]
                ]]
            ])
            return Self.response(for: request, data: data)
        }
        let catalog = try await api.fetchThemes(locale: "ru")
        XCTAssertEqual(catalog.themes.first?.countries, ["DE", "US", "ES", "FR", "IT", "RU"])
    }

    @MainActor
    func testRepositoryUsesSavedCountryInBothRandomModesButOmitsItForMusic() async throws {
        let backend = RecordingBackendContentAPI()
        let repository = ThemeCatalogRepository(backendContentAPI: backend, countryProvider: { "US" })
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        let refreshed = await repository.refreshBackendCatalog(locale: locale)
        XCTAssertTrue(refreshed)
        _ = try await repository.prepareQuiz(themeID: "music", questionCount: 5, locale: locale)
        XCTAssertNil(backend.requestedCountries.last!)
        for mode in CrossThemeQuestionSelectionMode.allCases {
            _ = try await repository.prepareRandomQuiz(
                selectionMode: mode, localFallback: Self.localTheme(questionCount: 5),
                questionCount: 5, locale: locale
            )
            XCTAssertEqual(backend.requestedCountries.last!, "US")
        }
        XCTAssertEqual(backend.randomSelectionModes, CrossThemeQuestionSelectionMode.allCases)
    }
}

extension BackendClientTests {
    @MainActor
    func testCatalogRetriesWhenAuthenticationChangesTheAccountDuringStartup() async {
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        for initialUserID in [nil, "A"] as [String?] {
            let (_, defaults, suiteName) = makePreferenceStore()
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let provider = ProgressSessionProvider()
            provider.session = initialUserID.map(ProgressSessionProvider.session)
            let store = OnboardingProgressStore(userDefaults: defaults, userIDProvider: { provider.session?.userID })
            let backend = ThemePreferencesBackendContentAPI(catalogThemes: Self.preferenceCatalog)
            let repository = ThemeCatalogRepository(backendContentAPI: backend, preferenceStore: store,
                                                   accessTokenProvider: provider)
            let requestStarted = expectation(description: "Catalog request before account change")
            let gate = ProgressUploadGate()
            var requestPrincipals: [String?] = []
            backend.beforeCatalogResponse = {
                let isFirstRequest = await MainActor.run {
                    requestPrincipals.append(provider.session?.userID)
                    return requestPrincipals.count == 1
                }
                if isFirstRequest {
                    requestStarted.fulfill()
                    await gate.wait()
                }
            }
            let refresh = Task { await repository.refreshBackendCatalog(locale: locale) }
            await fulfillment(of: [requestStarted], timeout: 1)
            provider.session = ProgressSessionProvider.session("B")
            await gate.open()

            let applied = await refresh.value

            XCTAssertTrue(applied)
            XCTAssertEqual(requestPrincipals, [initialUserID, "B"])
            XCTAssertEqual(backend.fetchedCatalogLocales, [locale, locale])
            XCTAssertEqual(repository.catalogOrigin, .backend)
            XCTAssertEqual(repository.themes?.map(\.stableID), Self.preferenceCatalog.map(\.id))
        }
    }

    @MainActor
    func testCatalogAccountChangeRetryIsLimitedToOneAttempt() async {
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        let (store, defaults, suiteName) = makePreferenceStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let provider = ProgressSessionProvider()
        let backend = ThemePreferencesBackendContentAPI(catalogThemes: Self.preferenceCatalog)
        let repository = ThemeCatalogRepository(backendContentAPI: backend, preferenceStore: store,
                                               accessTokenProvider: provider)
        backend.beforeCatalogResponse = {
            await MainActor.run {
                provider.session = ProgressSessionProvider.session("changed-\(backend.fetchedCatalogLocales.count)")
            }
        }

        let applied = await repository.refreshBackendCatalog(locale: locale)

        XCTAssertFalse(applied)
        XCTAssertEqual(backend.fetchedCatalogLocales, [locale, locale])
        XCTAssertEqual(repository.catalogOrigin, .bundled)
        XCTAssertNil(repository.themes)
    }

    @MainActor
    func testCancelledCatalogRefreshDoesNotRetryAfterAccountChange() async {
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        let (store, defaults, suiteName) = makePreferenceStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let provider = ProgressSessionProvider()
        provider.session = nil
        let backend = ThemePreferencesBackendContentAPI(catalogThemes: Self.preferenceCatalog)
        let repository = ThemeCatalogRepository(backendContentAPI: backend, preferenceStore: store,
                                               accessTokenProvider: provider)
        let requestStarted = expectation(description: "Catalog request awaiting response")
        let gate = ProgressUploadGate()
        backend.beforeCatalogResponse = {
            requestStarted.fulfill()
            await gate.wait()
        }
        let refresh = Task { await repository.refreshBackendCatalog(locale: locale) }
        await fulfillment(of: [requestStarted], timeout: 1)
        provider.session = ProgressSessionProvider.session("B")
        refresh.cancel()
        await gate.open()

        let applied = await refresh.value

        XCTAssertFalse(applied)
        XCTAssertEqual(backend.fetchedCatalogLocales, [locale])
        XCTAssertEqual(repository.catalogOrigin, .bundled)
        XCTAssertNil(repository.themes)
    }

    @MainActor
    func testCatalogFailuresDoNotRetryWhenTheAccountIsUnchanged() async {
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        let (store, defaults, suiteName) = makePreferenceStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        for error in [BackendContentError.transport(.notConnectedToInternet), .contractViolation] {
            let backend = ThemePreferencesBackendContentAPI(catalogThemes: Self.preferenceCatalog)
            backend.catalogError = error
            let repository = ThemeCatalogRepository(backendContentAPI: backend, preferenceStore: store,
                                                   accessTokenProvider: ProgressSessionProvider())

            let applied = await repository.refreshBackendCatalog(locale: locale)

            XCTAssertFalse(applied)
            XCTAssertEqual(backend.fetchedCatalogLocales, [locale])
        }
    }

    func testDeletionInvalidatesInFlightFavoriteAndCatalogResponses() async {
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        let (_, defaults, suiteName) = makePreferenceStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let provider = ProgressSessionProvider()
        let store = OnboardingProgressStore(userDefaults: defaults, userIDProvider: { provider.session?.userID })
        let backend = ThemePreferencesBackendContentAPI(catalogThemes: Self.preferenceCatalog,
                                                       remoteFavoriteThemeIDs: ["music"])
        let repository = ThemeCatalogRepository(backendContentAPI: backend, preferenceStore: store,
                                               accessTokenProvider: provider)
        _ = await repository.refreshBackendCatalog(locale: locale)
        // The account identifier deliberately remains the same. Generation
        // checks must still reject pre-deletion results before auth finishes.
        backend.beforeAsyncPreferencesResponse = {
            await MainActor.run {
                store.eraseData(for: "A")
                do { try repository.eraseCachedPersonalization() }
                catch { XCTFail("Cache erasure failed: \(error)") }
            }
        }

        let preferencesApplied = await repository.synchronizeThemePreferences(locale: locale)

        XCTAssertFalse(preferencesApplied)
        XCTAssertNil(store.storedPreferredThemeIDs(locale: locale))
        XCTAssertEqual(repository.themes?.filter(\.isFavorite).count, 0)
        backend.beforeCatalogResponse = {
            await MainActor.run {
                do { try repository.eraseCachedPersonalization() }
                catch { XCTFail("Cache erasure failed: \(error)") }
            }
        }
        let catalogApplied = await repository.refreshBackendCatalog(locale: locale)
        XCTAssertFalse(catalogApplied)
        XCTAssertNil(store.storedPreferredThemeIDs(locale: locale))
        XCTAssertEqual(repository.themes?.filter(\.isFavorite).count, 0)
    }

    func testPreferenceResponseCannotOverwriteANewerLocalChoice() async {
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        let (store, defaults, suiteName) = makePreferenceStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let backend = ThemePreferencesBackendContentAPI(catalogThemes: Self.preferenceCatalog,
                                                       remoteFavoriteThemeIDs: ["music"])
        let repository = ThemeCatalogRepository(backendContentAPI: backend, preferenceStore: store)
        _ = await repository.refreshBackendCatalog(locale: locale)
        store.complete(preferredThemeIDs: ["music"], locale: locale)
        backend.beforePreferencesResponse = { store.complete(preferredThemeIDs: ["space"], locale: locale) }
        let applied = await repository.synchronizeThemePreferences(locale: locale)
        XCTAssertFalse(applied)
        XCTAssertEqual(store.orderedPreferredThemeIDs(locale: locale), ["space"])
        XCTAssertTrue(store.hasPendingThemePreferences(locale: locale))
    }

    func testPreferenceResponseFromPreviousAccountIsDiscarded() async {
        let locale = AppLocalizationStore.shared.resolvedLanguageCode
        let (_, defaults, suiteName) = makePreferenceStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let provider = ProgressSessionProvider()
        let store = OnboardingProgressStore(userDefaults: defaults, userIDProvider: { provider.session?.userID })
        let backend = ThemePreferencesBackendContentAPI(catalogThemes: Self.preferenceCatalog,
                                                       remoteFavoriteThemeIDs: ["music"])
        let repository = ThemeCatalogRepository(backendContentAPI: backend, preferenceStore: store,
                                               accessTokenProvider: provider)
        _ = await repository.refreshBackendCatalog(locale: locale)
        store.complete(preferredThemeIDs: ["music"], locale: locale)
        backend.beforePreferencesResponse = { provider.session = ProgressSessionProvider.session("B") }
        let applied = await repository.synchronizeThemePreferences(locale: locale)
        XCTAssertFalse(applied)
        XCTAssertNil(store.storedPreferredThemeIDs(locale: locale))
        XCTAssertEqual(repository.themes?.filter(\.isFavorite).count, 0)
        provider.session = ProgressSessionProvider.session("A")
        XCTAssertEqual(store.orderedPreferredThemeIDs(locale: locale), ["music"])
        XCTAssertTrue(store.hasPendingThemePreferences(locale: locale))
    }

    func testExpiredContentTokenUsesAuthenticationRecoveryInsteadOfGuestFallback() async throws {
        let expired = AuthSession(userID: "A", accessToken: "expired", expiresAt: .distantPast, teamPlayerID: "A")
        let store = BackendMemorySessionStore(session: expired)
        let recoverer = BackendAuthenticationRecovererSpy(refreshedToken: "fresh")
        let api = HTTPBackendContentAPI(configuration: Self.configuration, session: makeSession(),
            accessTokenProvider: StoredBackendAccessTokenProvider(sessionStore: store), authenticationRecoverer: recoverer)
        var calls = 0
        BackendTestURLProtocol.requestHandler = { request in
            calls += 1
            if calls == 1 {
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Quizice-Authorization"), "Bearer expired")
                return Self.response(for: request, statusCode: 401, data: Data("{}".utf8))
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Quizice-Authorization"), "Bearer fresh")
            return Self.response(for: request, data: Data("{\"locale\":\"ru\",\"favoriteThemeIds\":[]}".utf8))
        }
        _ = try await api.fetchThemePreferences(locale: "ru")
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(recoverer.rejectedTokens, ["expired"])
    }

    func testPreferencePUTDoesNotRetryUnderReplacementAccount() async {
        let provider = ProgressSessionProvider()
        let recoverer = BackendAuthenticationRecovererSpy(refreshedToken: "B-token")
        let api = HTTPBackendContentAPI(configuration: Self.configuration, session: makeSession(),
            accessTokenProvider: provider, authenticationRecoverer: recoverer)
        var calls = 0
        BackendTestURLProtocol.requestHandler = { request in
            calls += 1
            provider.session = ProgressSessionProvider.session("B")
            return Self.response(for: request, statusCode: 401, data: Data("{}".utf8))
        }
        await assertBackendContentError(.unauthenticated) {
            try await api.replaceThemePreferences(locale: "ru", favoriteThemeIDs: ["music"])
        }
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(recoverer.rejectedTokens.isEmpty)
    }
}
