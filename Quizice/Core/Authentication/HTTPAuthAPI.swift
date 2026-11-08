import Foundation

final class HTTPAuthAPI: AuthAPI {
    private enum Endpoint {
        static let gameCenterAuth = "v1/auth/game-center"
        static let statisticsSync = "v1/me/statistics/sync"
    }

    private struct AuthResponse: Decodable {
        let userId: String
        let accessToken: String
        let expiresAt: Date
    }

    private struct RecreateAccountRequest: Encodable {
        let teamPlayerId: String
        let bundleId: String
        let publicKeyUrl: String
        let signature: String
        let salt: String
        let timestamp: String
        let recreateDeletedAccount = true

        init(identity: GameCenterIdentity) {
            teamPlayerId = identity.teamPlayerId
            bundleId = identity.bundleId
            publicKeyUrl = identity.publicKeyUrl
            signature = identity.signature
            salt = identity.salt
            timestamp = identity.timestamp
        }
    }

#if DEBUG
    private struct DevAuthRequest: Encodable {
        let developerUserId: UUID
    }
#endif

    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let requestTimeout: TimeInterval
    private let now: () -> Date
    private let metrics: BackendRequestMetricRecording
    private let clock = ContinuousClock()

    init(
        configuration: BackendConfiguration,
        session: URLSession = .shared,
        requestTimeout: TimeInterval = 15,
        now: @escaping () -> Date = Date.init,
        metrics: BackendRequestMetricRecording = NoopBackendRequestMetricRecorder()
    ) {
        baseURL = configuration.baseURL
        self.session = session
        self.requestTimeout = requestTimeout
        self.now = now
        self.metrics = metrics
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            try Self.decodeISO8601Date(from: decoder)
        }
    }

    func authenticate(identity: GameCenterIdentity) async throws -> AuthSession {
        try await post(
            path: Endpoint.gameCenterAuth,
            body: identity,
            accessToken: nil,
            operation: .authentication
        ) { [now] (response: AuthResponse) in
            guard
                response.userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                response.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                response.expiresAt > now()
            else {
                throw BackendAPIError.contractViolation
            }
            return AuthSession(
                userID: response.userId,
                accessToken: response.accessToken,
                expiresAt: response.expiresAt,
                teamPlayerID: identity.teamPlayerId
            )
        }
    }

    func authenticate(identity: GameCenterIdentity, recreateDeletedAccount: Bool) async throws -> AuthSession {
        guard recreateDeletedAccount else { return try await authenticate(identity: identity) }
        return try await post(path: Endpoint.gameCenterAuth, body: RecreateAccountRequest(identity: identity),
                              accessToken: nil, operation: .authentication) { [now] (response: AuthResponse) in
            guard !response.userId.isEmpty, !response.accessToken.isEmpty, response.expiresAt > now() else {
                throw BackendAPIError.contractViolation
            }
            return AuthSession(userID: response.userId, accessToken: response.accessToken,
                               expiresAt: response.expiresAt, teamPlayerID: identity.teamPlayerId)
        }
    }

    /// No automatic retry or reauthentication: a lost response must reuse the
    /// same deletion key, never create a replacement account as a side effect.
    func deleteAccount(accessToken: String, idempotencyKey: String) async throws {
        guard !accessToken.isEmpty, UUID(uuidString: idempotencyKey) != nil else {
            throw BackendAPIError.contractViolation
        }
        try Task.checkCancellation()
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/me/account"))
        request.httpMethod = "DELETE"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: BackendConfiguration.authorizationHeader)
        request.setValue(idempotencyKey, forHTTPHeaderField: "X-Idempotency-Key")
        let startedAt = clock.now
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                record(.accountDeletion, result: .cancelled, startedAt: startedAt)
                throw CancellationError()
            }
            record(.accountDeletion, result: .transportError, startedAt: startedAt)
            throw BackendAPIError.transport((error as? URLError)?.code ?? .unknown)
        }
        guard let http = response as? HTTPURLResponse else { throw BackendAPIError.invalidResponse }
        guard http.statusCode == 204 else {
            let envelope = try? decoder.decode(BackendErrorEnvelope.self, from: data)
            record(.accountDeletion, result: .httpError, startedAt: startedAt,
                   statusCode: http.statusCode, responseBytes: data.count)
            if http.statusCode == 401 { throw AccountDeletionError.sessionExpired }
            if (200..<300).contains(http.statusCode) { throw BackendAPIError.contractViolation }
            throw BackendAPIError.httpStatus(http.statusCode, envelope)
        }
        // Once a 204 has arrived, finish local cleanup even if the view vanished.
        record(.accountDeletion, result: .success, startedAt: startedAt, statusCode: http.statusCode)
    }

#if DEBUG
    func authenticateTestAccount(secret: String) async throws -> AuthSession {
        struct Request: Encodable {}
        struct Response: Decodable {
            let userId: UUID
            let developerUserId: UUID
            let accessToken: String
            let expiresAt: Date
        }
        return try await post(
            path: "v1/auth/test-account", body: Request(), accessToken: nil,
            additionalHeaders: ["X-Test-Account-Key": secret], operation: .authentication
        ) { [now] (response: Response) in
            guard !response.accessToken.isEmpty, response.expiresAt > now() else {
                throw BackendAPIError.contractViolation
            }
            return AuthSession(userID: response.userId.uuidString.lowercased(),
                               accessToken: response.accessToken, expiresAt: response.expiresAt,
                               teamPlayerID: "dev:\(response.developerUserId.uuidString.lowercased())")
        }
    }

    func authenticate(developerUserID: UUID, secret: String) async throws -> AuthSession {
        try await post(
            path: "v1/auth/dev",
            body: DevAuthRequest(developerUserId: developerUserID),
            accessToken: nil,
            additionalHeaders: ["X-Dev-Auth-Secret": secret],
            operation: .authentication
        ) { [now] (response: AuthResponse) in
            guard
                UUID(uuidString: response.userId) != nil,
                !response.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                response.expiresAt > now()
            else { throw BackendAPIError.contractViolation }
            return AuthSession(
                userID: response.userId,
                accessToken: response.accessToken,
                expiresAt: response.expiresAt,
                teamPlayerID: "dev:\(developerUserID.uuidString.lowercased())"
            )
        }
    }
#endif

    func syncStatistics(
        request: StatisticsStore.SyncRequest,
        accessToken: String
    ) async throws -> StatisticsStore.SyncResponse {
        // Statistics sync is a background operation with no user-visible
        // latency. When the network is flaky, retrying with exponential
        // backoff prevents attempts from silently disappearing and being
        // reattempted only on the next launch.
        try await BackendRetry.withExponentialBackoff(
            isRetryable: Self.isRetryableSyncError
        ) {
            try await self.post(
                path: Endpoint.statisticsSync,
                body: request,
                accessToken: accessToken,
                operation: .statisticsSync
            ) { (response: StatisticsStore.SyncResponse) in
                guard Self.isValid(response: response, for: request) else {
                    throw BackendAPIError.contractViolation
                }
                return response
            }
        }
    }

    private static func isRetryableSyncError(_ error: Error) -> Bool {
        switch error {
        case let apiError as BackendAPIError:
            switch apiError {
            case .transport:
                return true
            case let .httpStatus(status, _):
                return status >= 500 && status < 600
            case .unauthorized, .invalidResponse, .encoding, .decoding, .contractViolation, .configurationMissing:
                return false
            }
        default:
            return false
        }
    }

    private func post<Body: Encodable, Response: Decodable, Output>(
        path: String,
        body: Body,
        accessToken: String?,
        additionalHeaders: [String: String] = [:],
        operation: BackendOperation,
        transform: (Response) throws -> Output
    ) async throws -> Output {
        try Task.checkCancellation()
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: BackendConfiguration.authorizationHeader)
        }
        additionalHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw BackendAPIError.encoding
        }

        let startedAt = clock.now
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            record(operation, result: .cancelled, startedAt: startedAt)
            throw CancellationError()
        } catch let error as URLError {
            if Task.isCancelled || error.code == .cancelled {
                record(operation, result: .cancelled, startedAt: startedAt)
                throw CancellationError()
            }
            record(operation, result: .transportError, startedAt: startedAt)
            throw BackendAPIError.transport(error.code)
        } catch {
            if Task.isCancelled {
                record(operation, result: .cancelled, startedAt: startedAt)
                throw CancellationError()
            }
            record(operation, result: .transportError, startedAt: startedAt)
            throw BackendAPIError.transport(.unknown)
        }
        do {
            try Task.checkCancellation()
        } catch {
            record(
                operation,
                result: .cancelled,
                startedAt: startedAt,
                responseBytes: data.count
            )
            throw CancellationError()
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            record(
                operation,
                result: .transportError,
                startedAt: startedAt,
                responseBytes: data.count
            )
            throw BackendAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let envelope = try? decoder.decode(BackendErrorEnvelope.self, from: data)
            record(
                operation,
                result: .httpError,
                startedAt: startedAt,
                statusCode: httpResponse.statusCode,
                responseBytes: data.count
            )
            if httpResponse.statusCode == 401 {
                throw BackendAPIError.unauthorized(envelope)
            }
            throw BackendAPIError.httpStatus(httpResponse.statusCode, envelope)
        }
        let decoded: Response
        do {
            decoded = try decoder.decode(Response.self, from: data)
        } catch {
            record(
                operation,
                result: .decodingError,
                startedAt: startedAt,
                statusCode: httpResponse.statusCode,
                responseBytes: data.count
            )
            throw BackendAPIError.decoding
        }
        do {
            let output = try transform(decoded)
            record(
                operation,
                result: .success,
                startedAt: startedAt,
                statusCode: httpResponse.statusCode,
                responseBytes: data.count
            )
            return output
        } catch is CancellationError {
            record(
                operation,
                result: .cancelled,
                startedAt: startedAt,
                statusCode: httpResponse.statusCode,
                responseBytes: data.count
            )
            throw CancellationError()
        } catch {
            record(
                operation,
                result: .contractError,
                startedAt: startedAt,
                statusCode: httpResponse.statusCode,
                responseBytes: data.count
            )
            throw error
        }
    }

    private func record(
        _ operation: BackendOperation,
        result: BackendRequestResult,
        startedAt: ContinuousClock.Instant,
        statusCode: Int? = nil,
        responseBytes: Int = 0
    ) {
        let components = (clock.now - startedAt).components
        metrics.record(
            BackendRequestMetric(
                operation: operation,
                result: result,
                durationMilliseconds: max(
                    Int(
                        components.seconds * 1_000
                            + components.attoseconds / 1_000_000_000_000_000
                    ),
                    0
                ),
                statusCode: statusCode,
                responseBytes: responseBytes
            )
        )
    }

    private static func decodeISO8601Date(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        let formatter = ISO8601DateFormatter()

        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected an RFC3339/ISO-8601 date."
        )
    }

    private static func isValid(
        response: StatisticsStore.SyncResponse,
        for request: StatisticsStore.SyncRequest
    ) -> Bool {
        let summary = response.summary
        let values = [
            summary.playedQuizzes,
            summary.correctAnswers,
            summary.totalQuestions,
            summary.bestCorrectAnswers,
            summary.bestTotalQuestions
        ]
        guard
            values.allSatisfy({ $0 >= 0 }),
            summary.correctAnswers <= summary.totalQuestions,
            summary.bestCorrectAnswers <= summary.bestTotalQuestions,
            summary.bestCorrectAnswers <= summary.correctAnswers,
            summary.bestTotalQuestions <= summary.totalQuestions
        else {
            return false
        }

        if summary.playedQuizzes == 0 {
            guard values.allSatisfy({ $0 == 0 }) else { return false }
        } else {
            guard summary.totalQuestions > 0 else { return false }
            // Older servers leave the best game at 0/0 until the first correct
            // answer. Accept their acknowledgement only for an all-zero score;
            // preserve the aggregate exactly instead of inventing a best game.
            let hasLegacyZeroBest = summary.correctAnswers == 0
                && summary.bestCorrectAnswers == 0
                && summary.bestTotalQuestions == 0
            guard summary.bestTotalQuestions > 0 || hasLegacyZeroBest else { return false }
        }

        let acceptedIDs = response.acceptedAttemptIds
        let requestIDs = Set(request.attempts.map(\.id))
        return
            Set(acceptedIDs).count == acceptedIDs.count &&
            acceptedIDs.allSatisfy { $0.isEmpty == false } &&
            Set(acceptedIDs) == requestIDs
    }
}

#if DEBUG
extension HTTPAuthAPI: DevAuthAPI {}
#endif

struct UnavailableAuthAPI: AuthAPI {
    func authenticate(identity: GameCenterIdentity) async throws -> AuthSession {
        throw BackendAPIError.configurationMissing
    }

    func syncStatistics(
        request: StatisticsStore.SyncRequest,
        accessToken: String
    ) async throws -> StatisticsStore.SyncResponse {
        throw BackendAPIError.configurationMissing
    }
}
