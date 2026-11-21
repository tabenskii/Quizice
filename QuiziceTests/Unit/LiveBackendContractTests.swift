import XCTest
@testable import Quizice

final class LiveBackendContractTests: XCTestCase {
    func testHealthReadinessAndReportLatency() async throws {
        try requireLiveTests()
        let endpoints = try liveEndpoints()
        let session = makeSession()
        let healthURL = endpoints.healthURL
        let readinessURL = endpoints.readinessURL
        try await assertStatusJSON(
            url: healthURL,
            expected: ["status": "alive"],
            session: session
        )
        try await assertStatusJSON(
            url: readinessURL,
            expected: ["status": "ready"],
            session: session
        )

        let backendURL = endpoints.apiBaseURL
        let themesURL = try XCTUnwrap(
            URL(string: backendURL.appendingPathComponent("v1/themes").absoluteString + "?locale=en")
        )
        let questionsURL = try XCTUnwrap(
            URL(
                string: backendURL.appendingPathComponent("v1/themes/music/questions").absoluteString
                    + "?count=5&locale=en&difficulty=medium&seed=550e8400-e29b-41d4-a716-446655440000"
            )
        )

        try await reportLatency(operation: "health", url: healthURL, session: session)
        try await reportLatency(operation: "themes", url: themesURL, session: session)
        try await reportLatency(operation: "questions", url: questionsURL, session: session)
    }

    func testFuturePublicContentContract() async throws {
        try requireLiveTests()
        let contentAPI = HTTPBackendContentAPI(
            configuration: BackendConfiguration(baseURL: try liveEndpoints().apiBaseURL),
            session: makeSession()
        )
        let themes = try await contentAPI.fetchThemes(locale: "en")
        XCTAssertFalse(themes.themes.isEmpty)
        let firstTheme = try XCTUnwrap(themes.themes.first)
        let seed = "550e8400-e29b-41d4-a716-446655440000"
        let questions = try await contentAPI.fetchQuestions(
            themeID: firstTheme.id,
            count: 5,
            locale: "en",
            difficulty: .medium,
            seed: seed
        )
        XCTAssertEqual(questions.questions.count, 5)
    }

    func testFutureAIContractRejectsGuestBeforeGeneration() async throws {
        try requireLiveTests()
        let session = makeSession()
        let url = try liveEndpoints().apiBaseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("quizzes")
            .appendingPathComponent("generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "topic": "European geography",
            "count": 5,
            "locale": "en",
            "difficulty": "medium"
        ])

        let (data, response) = try await session.data(for: request)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        guard httpResponse.statusCode == 401 else {
            XCTFail("Guest AI generation must return 401, got \(httpResponse.statusCode)")
            return
        }

        let envelope = try JSONDecoder().decode(BackendErrorEnvelope.self, from: data)
        XCTAssertEqual(envelope.code, "unauthorized")
        XCTAssertFalse(envelope.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let requestID = try XCTUnwrap(envelope.requestId)
        XCTAssertNotNil(UUID(uuidString: requestID))
        XCTAssertEqual(httpResponse.value(forHTTPHeaderField: "X-Request-Id"), requestID)
    }

    private func liveEndpoints() throws -> LiveBackendEndpoints {
        try LiveBackendEndpoints(override: ProcessInfo.processInfo.environment["QUIZICE_LIVE_BACKEND_URL"])
    }

    private func requireLiveTests() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["QUIZICE_RUN_LIVE_BACKEND_TESTS"] == "1",
            "Set QUIZICE_RUN_LIVE_BACKEND_TESTS=1 to probe the deployed backend."
        )
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }

    private func reportLatency(
        operation: String,
        url: URL,
        session: URLSession
    ) async throws {
        // This production smoke is deliberately report-only: stable latency gates
        // belong to the production-like backend load suite documented in the handoff.
        let firstSample = try await timedGET(url: url, session: session)
        var samples: [Double] = []
        for _ in 0..<10 {
            samples.append(try await timedGET(url: url, session: session))
        }
        let sorted = samples.sorted()
        let median = percentile(0.5, sortedSamples: sorted)
        let p95 = percentile(0.95, sortedSamples: sorted)
        print(
            "LIVE_BACKEND_LATENCY operation=\(operation) samples=10 "
                + "first_ms=\(String(format: "%.1f", firstSample)) "
                + "median_ms=\(String(format: "%.1f", median)) "
                + "p95_ms=\(String(format: "%.1f", p95)) "
                + "max_ms=\(String(format: "%.1f", sorted.last ?? 0))"
        )
    }

    private func assertStatusJSON(
        url: URL,
        expected: [String: String],
        session: URLSession
    ) async throws {
        let (data, response) = try await session.data(from: url)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 200)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(json, expected)
    }

    private func timedGET(url: URL, session: URLSession) async throws -> Double {
        let clock = ContinuousClock()
        let startedAt = clock.now
        let (_, response) = try await session.data(from: url)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 200)
        let components = (clock.now - startedAt).components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    private func percentile(_ percentile: Double, sortedSamples: [Double]) -> Double {
        guard !sortedSamples.isEmpty else { return 0 }
        let index = Int(
            (Double(sortedSamples.count - 1) * min(max(percentile, 0), 1)).rounded(.up)
        )
        return sortedSamples[index]
    }
}

private struct LiveBackendEndpoints {
    enum ConfigurationError: Error { case invalidOverride }

    let apiBaseURL: URL
    let healthURL: URL
    let readinessURL: URL

    init(override: String?) throws {
        let value = override
            ?? "https://bbav8b1v6032q53l8360.containers.yandexcloud.net/api"
        guard !value.contains(where: \.isWhitespace),
              var components = URLComponents(string: value),
              let host = components.host, !host.isEmpty,
              components.scheme == "https"
                || (components.scheme == "http" && ["localhost", "127.0.0.1", "[::1]"].contains(host)),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.split(separator: "/").last == "api",
              let apiBaseURL = components.url else {
            throw ConfigurationError.invalidOverride
        }
        self.apiBaseURL = apiBaseURL
        components.path = ""
        guard let origin = components.url else { throw ConfigurationError.invalidOverride }
        healthURL = origin.appendingPathComponent("health")
        readinessURL = origin.appendingPathComponent("readiness")
    }
}

final class LiveBackendEndpointConfigurationTests: XCTestCase {
    func testOverrideKeepsHealthReadinessAndContentOnSameOrigin() throws {
        for baseURL in ["https://staging.example.com:8443/service/api", "http://127.0.0.1:8000/api"] {
            let endpoints = try LiveBackendEndpoints(override: baseURL)
            let expected = try XCTUnwrap(URLComponents(string: baseURL))
            XCTAssertEqual(endpoints.apiBaseURL.absoluteString, baseURL)
            for endpoint in [endpoints.healthURL, endpoints.readinessURL] {
                let actual = try XCTUnwrap(URLComponents(url: endpoint, resolvingAgainstBaseURL: false))
                XCTAssertEqual(actual.scheme, expected.scheme)
                XCTAssertEqual(actual.host, expected.host)
                XCTAssertEqual(actual.port, expected.port)
            }
            XCTAssertEqual(endpoints.healthURL.path, "/health")
            XCTAssertEqual(endpoints.readinessURL.path, "/readiness")
        }
    }

    func testInvalidOverrideFailsInsteadOfProbingProduction() {
        for value in ["", "/api", "https:", "https://staging.example.com/notapi",
                      "http://staging.example.com/api", "https://user:pass@staging.example.com/api",
                      "https://staging.example.com/api?token=private", "https://staging.example.com/api#fragment"] {
            XCTAssertThrowsError(try LiveBackendEndpoints(override: value), value)
        }
    }
}
