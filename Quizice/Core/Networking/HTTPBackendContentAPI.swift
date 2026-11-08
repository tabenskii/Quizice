import Foundation

final class HTTPBackendContentAPI: BackendContentAPI {
    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let requestTimeout: TimeInterval
    private let metrics: BackendRequestMetricRecording
    private let accessTokenProvider: BackendAccessTokenProviding
    private let authenticationRecoverer: BackendAuthenticationRecovering?
    private let clock = ContinuousClock()

    // Content responses (themes, preferences, question batches) are a few
    // kilobytes at most. Anything larger indicates a misbehaving upstream or
    // an active attack; refuse the body before JSON decoding balloons memory.
    private static let maxResponseBytes = 10 * 1024 * 1024

    init(
        configuration: BackendConfiguration,
        session: URLSession = .shared,
        requestTimeout: TimeInterval = 15,
        metrics: BackendRequestMetricRecording = NoopBackendRequestMetricRecorder(),
        accessTokenProvider: BackendAccessTokenProviding = NoopBackendAccessTokenProvider(),
        authenticationRecoverer: BackendAuthenticationRecovering? = nil
    ) {
        baseURL = configuration.baseURL
        self.session = session
        self.requestTimeout = requestTimeout
        self.metrics = metrics
        self.accessTokenProvider = accessTokenProvider
        self.authenticationRecoverer = authenticationRecoverer
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    // An expired session still identifies the player. Send its token through
    // the existing 401 recovery path instead of silently fetching as a guest.
    private var requestAccessToken: String? {
        accessTokenProvider.validAccessToken() ?? accessTokenProvider.currentSession()?.accessToken
    }

    func fetchThemes(locale: String) async throws -> BackendThemeCatalogResponse {
        guard Self.isSupported(locale: locale) else {
            throw BackendContentError.invalidRequest
        }
        let url = try makeURL(
            pathComponents: ["v1", "themes"],
            queryItems: [URLQueryItem(name: "locale", value: locale)]
        )
        return try await get(
            url: url,
            operation: .themes,
            accessToken: requestAccessToken,
            validate: { BackendContentResponseValidator.isValid($0, requestedLocale: locale) }
        )
    }

    func fetchFavorites() async throws -> BackendFavoritesSnapshot {
        guard let token = requestAccessToken else { throw BackendContentError.unauthenticated }
        return try await get(url: makeURL(pathComponents: ["v2", "me", "favorites"], queryItems: []),
                             operation: .themePreferences, accessToken: token,
                             validate: Self.validFavorites)
    }

    func patchFavorites(_ mutation: FavoriteMutation, session: AuthSession) async throws -> BackendFavoritesSnapshot {
        guard accessTokenProvider.currentSession()?.userID == session.userID else { throw BackendContentError.unauthenticated }
        guard mutation.addThemeIds.count <= 100, mutation.removeThemeIds.count <= 100,
              BackendContentResponseValidator.normalizedThemeIDs(mutation.addThemeIds) == mutation.addThemeIds,
              BackendContentResponseValidator.normalizedThemeIDs(mutation.removeThemeIds) == mutation.removeThemeIds,
              Set(mutation.addThemeIds).isDisjoint(with: mutation.removeThemeIds) else { throw BackendContentError.invalidRequest }
        var request = URLRequest(url: try makeURL(pathComponents: ["v2", "me", "favorites"], queryItems: []), timeoutInterval: requestTimeout)
        request.httpMethod = "PATCH"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = try encoder.encode(mutation)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: BackendConfiguration.authorizationHeader)
        return try await perform(request: request, operation: .themePreferences,
                                 validate: { Self.validFavorites($0) && $0.mutationId == mutation.mutationId },
                                 expectedUserID: session.userID)
    }

    private static func validFavorites(_ response: BackendFavoritesSnapshot) -> Bool {
        response.revision >= 0 && BackendContentResponseValidator.normalizedThemeIDs(response.favoriteThemeIds) == response.favoriteThemeIds
    }

    func fetchThemePreferences(locale: String) async throws -> BackendThemePreferencesResponse {
        guard Self.isSupported(locale: locale) else {
            throw BackendContentError.invalidRequest
        }
        guard let accessToken = requestAccessToken else {
            throw BackendContentError.unauthenticated
        }
        let url = try makeURL(
            pathComponents: ["v1", "me", "theme-preferences"],
            queryItems: [URLQueryItem(name: "locale", value: locale)]
        )
        return try await get(
            url: url,
            operation: .themePreferences,
            accessToken: accessToken,
            validate: { BackendContentResponseValidator.isValid($0, requestedLocale: locale) }
        )
    }

    func replaceThemePreferences(
        locale: String,
        favoriteThemeIDs: [String]
    ) async throws -> BackendThemePreferencesResponse {
        guard Self.isSupported(locale: locale) else {
            throw BackendContentError.invalidRequest
        }
        guard let accessToken = requestAccessToken else {
            throw BackendContentError.unauthenticated
        }
        let normalizedIDs = BackendContentResponseValidator.normalizedThemeIDs(favoriteThemeIDs)
        guard normalizedIDs.count == favoriteThemeIDs.count else {
            throw BackendContentError.invalidRequest
        }
        let url = try makeURL(
            pathComponents: ["v1", "me", "theme-preferences"],
            queryItems: []
        )
        return try await put(
            url: url,
            operation: .themePreferences,
            accessToken: accessToken,
            body: BackendThemePreferencesUpdate(
                locale: locale,
                favoriteThemeIds: normalizedIDs
            ),
            validate: { BackendContentResponseValidator.isValid($0, requestedLocale: locale) }
        )
    }

    func submitQuestionAnswers(_ events: [QuestionAnswerEvent], session: AuthSession) async throws -> QuestionAnswerBatchResponse {
        guard !events.isEmpty, events.count <= 100 else { throw BackendContentError.invalidRequest }
        guard accessTokenProvider.currentSession()?.userID == session.userID else {
            throw BackendContentError.unauthenticated
        }
        let url = try makeURL(pathComponents: ["v1", "me", "question-answers"], queryItems: [])
        return try await post(
            url: url, operation: .questionAnswers, accessToken: session.accessToken,
            body: QuestionAnswerBatchRequest(events: events),
            expectedUserID: session.userID,
            validate: { Set($0.processedEventIds).isSubset(of: Set(events.map(\.eventId))) }
        )
    }

    func submitQuestionAnswers(_ events: [QuestionAnswerEvent]) async throws -> QuestionAnswerBatchResponse {
        guard !events.isEmpty, events.count <= 100 else { throw BackendContentError.invalidRequest }
        guard let accessToken = requestAccessToken else {
            throw BackendContentError.unauthenticated
        }
        let url = try makeURL(
            pathComponents: ["v1", "me", "question-answers"],
            queryItems: []
        )
        return try await post(
            url: url,
            operation: .questionAnswers,
            accessToken: accessToken,
            body: QuestionAnswerBatchRequest(events: events),
            validate: { response in
                let requested = Set(events.map(\.eventId))
                return Set(response.processedEventIds).isSubset(of: requested)
            }
        )
    }

    func fetchQuestions(
        themeID: String,
        count: Int,
        locale: String,
        seed: String
    ) async throws -> BackendQuestionBatchResponse {
        try await fetchQuestionBatch(
            themeID: themeID,
            count: count,
            locale: locale,
            difficulty: nil,
            seed: seed,
            strategy: .showAll
        )
    }

    func fetchQuestions(
        themeID: String,
        count: Int,
        locale: String,
        difficulty: AIQuizDifficulty,
        seed: String
    ) async throws -> BackendQuestionBatchResponse {
        try await fetchQuestionBatch(
            themeID: themeID,
            count: count,
            locale: locale,
            difficulty: difficulty,
            seed: seed,
            strategy: .showAll
        )
    }

    func fetchQuestions(
        themeID: String,
        count: Int,
        locale: String,
        difficulty: AIQuizDifficulty,
        seed: String,
        strategy: QuestionRepeatStrategy
    ) async throws -> BackendQuestionBatchResponse {
        try await fetchQuestionBatch(
            themeID: themeID,
            count: count,
            locale: locale,
            difficulty: difficulty,
            seed: seed,
            strategy: strategy
        )
    }

    func fetchQuestions(
        themeID: String, count: Int, locale: String,
        difficulty: AIQuizDifficulty, seed: String,
        strategy: QuestionRepeatStrategy, country: String?
    ) async throws -> BackendQuestionBatchResponse {
        try await fetchQuestionBatch(
            themeID: themeID, count: count, locale: locale,
            difficulty: difficulty, seed: seed, strategy: strategy, country: country
        )
    }

    private func fetchQuestionBatch(
        themeID: String,
        count: Int,
        locale: String,
        difficulty: AIQuizDifficulty?,
        seed: String,
        strategy: QuestionRepeatStrategy,
        country: String? = nil
    ) async throws -> BackendQuestionBatchResponse {
        guard country.map(QuestionCountryStore.supportedCodes.contains) ?? true else {
            throw BackendContentError.invalidRequest
        }
        let normalizedThemeID = themeID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSeed = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedThemeID.isEmpty,
            UUID(uuidString: normalizedSeed)?.uuidString.lowercased() == normalizedSeed,
            QuizQuestionCountPolicy.supportedCounts.contains(count),
            Self.isSupported(locale: locale)
        else {
            throw BackendContentError.invalidRequest
        }

        var queryItems = [
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "locale", value: locale)
        ]
        if let difficulty {
            queryItems.append(
                URLQueryItem(name: "difficulty", value: difficulty.rawValue)
            )
        }
        if let country {
            queryItems.append(URLQueryItem(name: "country", value: country))
        }
        queryItems.append(URLQueryItem(name: "seed", value: normalizedSeed))
        if let progressMode = strategy.progressMode {
            queryItems.append(URLQueryItem(name: "progressMode", value: progressMode.rawValue))
        }
        let url = try makeURL(
            pathComponents: ["v1", "themes", normalizedThemeID, "questions"],
            queryItems: queryItems
        )
        let accessToken = requestAccessToken
        if strategy.progressMode != nil, accessToken == nil {
            throw BackendContentError.unauthenticated
        }
        return try await get(
            url: url,
            operation: .questions,
            accessToken: accessToken,
            validate: {
                BackendContentResponseValidator.isValid(
                    $0,
                    requestedCount: count,
                    requestedLocale: locale,
                    requestedSeed: normalizedSeed,
                    requestedCountry: country
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
        try await fetchRandomQuestionBatch(
            selectionMode: selectionMode,
            count: count,
            locale: locale,
            difficulty: nil,
            seed: seed,
            strategy: .showAll
        )
    }

    func fetchRandomQuestions(
        selectionMode: CrossThemeQuestionSelectionMode,
        count: Int,
        locale: String,
        difficulty: AIQuizDifficulty,
        seed: String
    ) async throws -> BackendQuestionBatchResponse {
        try await fetchRandomQuestionBatch(
            selectionMode: selectionMode,
            count: count,
            locale: locale,
            difficulty: difficulty,
            seed: seed,
            strategy: .showAll
        )
    }

    func fetchRandomQuestions(
        selectionMode: CrossThemeQuestionSelectionMode,
        count: Int,
        locale: String,
        difficulty: AIQuizDifficulty,
        seed: String,
        strategy: QuestionRepeatStrategy
    ) async throws -> BackendQuestionBatchResponse {
        try await fetchRandomQuestionBatch(
            selectionMode: selectionMode,
            count: count,
            locale: locale,
            difficulty: difficulty,
            seed: seed,
            strategy: strategy
        )
    }

    func fetchRandomQuestions(
        selectionMode: CrossThemeQuestionSelectionMode, count: Int, locale: String,
        difficulty: AIQuizDifficulty, seed: String,
        strategy: QuestionRepeatStrategy, country: String?
    ) async throws -> BackendQuestionBatchResponse {
        try await fetchRandomQuestionBatch(
            selectionMode: selectionMode, count: count, locale: locale,
            difficulty: difficulty, seed: seed, strategy: strategy, country: country
        )
    }

    private func fetchRandomQuestionBatch(
        selectionMode: CrossThemeQuestionSelectionMode,
        count: Int,
        locale: String,
        difficulty: AIQuizDifficulty?,
        seed: String,
        strategy: QuestionRepeatStrategy,
        country: String? = nil
    ) async throws -> BackendQuestionBatchResponse {
        guard country.map(QuestionCountryStore.supportedCodes.contains) ?? true else {
            throw BackendContentError.invalidRequest
        }
        let normalizedSeed = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            UUID(uuidString: normalizedSeed)?.uuidString.lowercased() == normalizedSeed,
            QuizQuestionCountPolicy.supportedCounts.contains(count),
            Self.isSupported(locale: locale)
        else {
            throw BackendContentError.invalidRequest
        }

        var queryItems = [
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "locale", value: locale)
        ]
        if let difficulty {
            queryItems.append(
                URLQueryItem(name: "difficulty", value: difficulty.rawValue)
            )
        }
        if let country {
            queryItems.append(URLQueryItem(name: "country", value: country))
        }
        queryItems.append(URLQueryItem(name: "seed", value: normalizedSeed))
        if let progressMode = strategy.progressMode {
            queryItems.append(URLQueryItem(name: "progressMode", value: progressMode.rawValue))
        }
        let url = try makeURL(
            pathComponents: ["v1", "questions", selectionMode.rawValue],
            queryItems: queryItems
        )
        let accessToken = requestAccessToken
        if strategy.progressMode != nil, accessToken == nil {
            throw BackendContentError.unauthenticated
        }
        return try await get(
            url: url,
            operation: .questions,
            accessToken: accessToken,
            validate: {
                BackendContentResponseValidator.isValid(
                    $0,
                    requestedCount: count,
                    requestedLocale: locale,
                    requestedSeed: normalizedSeed,
                    requestedCountry: country
                )
            }
        )
    }

    private func get<Response: Decodable>(
        url: URL,
        operation: BackendOperation,
        accessToken: String? = nil,
        validate: @escaping (Response) -> Bool
    ) async throws -> Response {
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: BackendConfiguration.authorizationHeader)
        }
        return try await perform(
            request: request,
            operation: operation,
            validate: validate,
            expectedUserID: accessToken == nil ? nil : accessTokenProvider.currentSession()?.userID
        )
    }

    private func put<Response: Decodable, Body: Encodable>(
        url: URL,
        operation: BackendOperation,
        accessToken: String,
        body: Body,
        validate: @escaping (Response) -> Bool
    ) async throws -> Response {
        let bodyData: Data
        do {
            bodyData = try encoder.encode(body)
        } catch {
            throw BackendContentError.encoding
        }

        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpMethod = "PUT"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: BackendConfiguration.authorizationHeader)
        return try await perform(
            request: request,
            operation: operation,
            validate: validate,
            expectedUserID: accessTokenProvider.currentSession()?.userID
        )
    }

    private func post<Response: Decodable, Body: Encodable>(
        url: URL,
        operation: BackendOperation,
        accessToken: String,
        body: Body,
        expectedUserID: String? = nil,
        validate: @escaping (Response) -> Bool
    ) async throws -> Response {
        let bodyData: Data
        do {
            encoder.dateEncodingStrategy = .iso8601
            bodyData = try encoder.encode(body)
        } catch {
            throw BackendContentError.encoding
        }
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: BackendConfiguration.authorizationHeader)
        return try await perform(request: request, operation: operation, validate: validate, expectedUserID: expectedUserID)
    }

    private func perform<Response: Decodable>(
        request: URLRequest,
        operation: BackendOperation,
        validate: @escaping (Response) -> Bool,
        expectedUserID: String? = nil,
        allowsAuthenticationRetry: Bool = true
    ) async throws -> Response {
        let startedAt = clock.now
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                record(
                    operation: operation,
                    result: .transportError,
                    startedAt: startedAt,
                    statusCode: nil,
                    responseBytes: data.count
                )
                throw BackendContentError.invalidResponse
            }
            guard data.count <= Self.maxResponseBytes else {
                record(
                    operation: operation,
                    result: .contractError,
                    startedAt: startedAt,
                    statusCode: httpResponse.statusCode,
                    responseBytes: data.count
                )
                throw BackendContentError.contractViolation
            }
            // If a WAF or captive portal intercepts the request it typically
            // returns HTML with a 200 code. Refuse anything that is not JSON
            // before feeding it to the decoder.
            if (200..<300).contains(httpResponse.statusCode) {
                let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased()
                if let contentType, !contentType.contains("application/json") {
                    record(
                        operation: operation,
                        result: .contractError,
                        startedAt: startedAt,
                        statusCode: httpResponse.statusCode,
                        responseBytes: data.count
                    )
                    throw BackendContentError.contractViolation
                }
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                let envelope = try? decoder.decode(BackendErrorEnvelope.self, from: data)
                record(
                    operation: operation,
                    result: .httpError,
                    startedAt: startedAt,
                    statusCode: httpResponse.statusCode,
                    responseBytes: data.count
                )
                if httpResponse.statusCode == 401,
                   allowsAuthenticationRetry,
                   let authenticationRecoverer,
                   let authorization = request.value(forHTTPHeaderField: BackendConfiguration.authorizationHeader),
                   authorization.hasPrefix("Bearer ") {
                    if let expectedUserID,
                       accessTokenProvider.currentSession()?.userID != expectedUserID {
                        throw BackendContentError.unauthenticated
                    }
                    let rejectedToken = String(authorization.dropFirst("Bearer ".count))
                    let refreshedToken = try await authenticationRecoverer.reauthenticate(
                        afterRejectedAccessToken: rejectedToken
                    )
                    if let expectedUserID,
                       accessTokenProvider.currentSession()?.userID != expectedUserID {
                        throw BackendContentError.unauthenticated
                    }
                    var retryRequest = request
                    retryRequest.setValue(
                        "Bearer \(refreshedToken)",
                        forHTTPHeaderField: BackendConfiguration.authorizationHeader
                    )
                    return try await perform(
                        request: retryRequest,
                        operation: operation,
                        validate: validate,
                        expectedUserID: expectedUserID,
                        allowsAuthenticationRetry: false
                    )
                }
                throw BackendContentError.httpStatus(httpResponse.statusCode, envelope)
            }
            do {
                let decoded = try decoder.decode(Response.self, from: data)
                guard validate(decoded) else {
                    record(
                        operation: operation,
                        result: .contractError,
                        startedAt: startedAt,
                        statusCode: httpResponse.statusCode,
                        responseBytes: data.count
                    )
                    throw BackendContentError.contractViolation
                }
                record(
                    operation: operation,
                    result: .success,
                    startedAt: startedAt,
                    statusCode: httpResponse.statusCode,
                    responseBytes: data.count
                )
                return decoded
            } catch let error as BackendContentError {
                throw error
            } catch {
                record(
                    operation: operation,
                    result: .decodingError,
                    startedAt: startedAt,
                    statusCode: httpResponse.statusCode,
                    responseBytes: data.count
                )
                throw BackendContentError.decoding
            }
        } catch is CancellationError {
            record(
                operation: operation,
                result: .cancelled,
                startedAt: startedAt,
                statusCode: nil,
                responseBytes: 0
            )
            throw CancellationError()
        } catch let error as BackendContentError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            record(
                operation: operation,
                result: .cancelled,
                startedAt: startedAt,
                statusCode: nil,
                responseBytes: 0
            )
            throw CancellationError()
        } catch let error as URLError {
            record(
                operation: operation,
                result: .transportError,
                startedAt: startedAt,
                statusCode: nil,
                responseBytes: 0
            )
            throw BackendContentError.transport(error.code)
        } catch {
            record(
                operation: operation,
                result: .transportError,
                startedAt: startedAt,
                statusCode: nil,
                responseBytes: 0
            )
            throw BackendContentError.transport(.unknown)
        }
    }

    private func makeURL(
        pathComponents: [String],
        queryItems: [URLQueryItem]
    ) throws -> URL {
        let url = pathComponents.reduce(baseURL) { partialURL, component in
            partialURL.appendingPathComponent(component)
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw BackendContentError.invalidRequest
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let result = components.url else {
            throw BackendContentError.invalidRequest
        }
        return result
    }

    private func record(
        operation: BackendOperation,
        result: BackendRequestResult,
        startedAt: ContinuousClock.Instant,
        statusCode: Int?,
        responseBytes: Int
    ) {
        metrics.record(
            BackendRequestMetric(
                operation: operation,
                result: result,
                durationMilliseconds: Self.milliseconds(clock.now - startedAt),
                statusCode: statusCode,
                responseBytes: responseBytes
            )
        )
    }

    private static func isSupported(locale: String) -> Bool {
        AppLanguagePreference.explicitPreference(for: locale) != nil
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        let components = duration.components
        let seconds = components.seconds * 1_000
        let milliseconds = components.attoseconds / 1_000_000_000_000_000
        return max(Int(seconds + milliseconds), 0)
    }
}
