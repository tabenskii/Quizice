import Foundation
import XCTest
@testable import Quizice

extension BackendClientTests {
    func makeContentAPI(
        metrics: BackendRequestMetricRecording = NoopBackendRequestMetricRecorder(),
        accessToken: String? = nil,
        authenticationRecoverer: BackendAuthenticationRecovering? = nil
    ) -> HTTPBackendContentAPI {
        HTTPBackendContentAPI(
            configuration: Self.configuration,
            session: makeSession(),
            metrics: metrics,
            accessTokenProvider: BackendAccessTokenStub(token: accessToken),
            authenticationRecoverer: authenticationRecoverer
        )
    }

    func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BackendTestURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    func makePreferenceStore() -> (
        store: OnboardingProgressStore,
        defaults: UserDefaults,
        suiteName: String
    ) {
        let suiteName = "BackendClientTests.ThemePreferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (
            OnboardingProgressStore(userDefaults: defaults, userIDProvider: { "A" }),
            defaults,
            suiteName
        )
    }

    func assertBackendContentError<T>(
        _ expected: BackendContentError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as BackendContentError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    func assertAIError<T>(
        _ expected: YandexAIQuizThemeServiceError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as YandexAIQuizThemeServiceError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    static func response(
        for request: URLRequest,
        statusCode: Int = 200,
        data: Data
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            data
        )
    }

    static func questionJSON(index: Int) -> [String: Any] {
        [
            "questionId": "question-\(index)",
            "questionVersion": 1,
            "question": "Question \(index)",
            "answers": ["A\(index)", "B\(index)", "C\(index)", "D\(index)"],
            "correctAnswer": "B\(index)",
            "explanation": ""
        ]
    }

    static func successfulAIResponseData() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "locale": "ru",
            "status": "success",
            "message": "",
            "theme": "Космос",
            "themeDescription": "Описание",
            "questions": (0..<5).map(Self.questionJSON)
        ])
    }

    static let preferenceCatalog = [
        BackendThemeDTO(
            id: "music",
            name: "Music",
            description: "Music description",
            sfSymbol: "music.note.list",
            emoji: "🎵",
            colorHex: "#FF8252",
            isFavorite: false
        ),
        BackendThemeDTO(
            id: "space",
            name: "Space",
            description: "Space description",
            sfSymbol: "globe",
            emoji: "🚀",
            colorHex: "#4F46E5",
            isFavorite: false
        ),
        BackendThemeDTO(
            id: "cinema",
            name: "Cinema",
            description: "Cinema description",
            sfSymbol: "film",
            emoji: "🎬",
            colorHex: "#EF4444",
            isFavorite: false
        )
    ]

    static func localTheme(questionCount: Int) -> QuizTheme {
        QuizTheme(
            id: "music",
            theme: "Music",
            themeDescription: "Description",
            questions: (0..<questionCount).map { index in
                QuizQuestion(
                    question: "Local \(index)",
                    answers: ["A\(index)", "B\(index)", "C\(index)", "D\(index)"],
                    correctAnswer: "B\(index)"
                )
            }
        )
    }

    static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    static let configuration = BackendConfiguration(
        baseURL: URL(string: "https://backend.example/api")!
    )

    static let aiConfiguration = AIQuizGenerationConfiguration(
        theme: " Space ",
        questionCount: 5,
        difficulty: .hard,
        locale: Locale(identifier: "ru")
    )
}
