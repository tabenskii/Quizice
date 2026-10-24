import XCTest
@testable import Quizice

final class AIServiceStatusAPITests: XCTestCase {
    override func tearDown() {
        BackendTestURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testFetchesLocalizedNoticeWithoutAuthenticationOrCachedResponse() async throws {
        BackendTestURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/ai/status")
            XCTAssertEqual(request.url?.query, "locale=ru")
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(request.timeoutInterval, 5)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: BackendConfiguration.authorizationHeader))
            return Self.response(request, body: #"{"locale":"ru","notice":"  Сейчас вопросы создаются с задержкой.  "}"#)
        }
        let notice = try await makeAPI().fetchNotice(locale: "ru")
        XCTAssertEqual(notice, "Сейчас вопросы создаются с задержкой.")
    }

    func testNullMissingAndBlankNoticeAreHidden() async throws {
        for body in [
            #"{"locale":"ru","notice":null}"#,
            #"{"locale":"ru"}"#,
            #"{"locale":"ru","notice":" \n\t "}"#
        ] {
            BackendTestURLProtocol.requestHandler = { Self.response($0, body: body) }
            let notice = try await makeAPI().fetchNotice(locale: "ru")
            XCTAssertNil(notice)
        }
    }

    func testRejectsWrongLocaleInvalidPayloadAndExcessiveText() async {
        for body in [
            #"{"locale":"en","notice":"Delayed"}"#,
            #"{"locale":"ru","notice":true}"#,
            "{\"locale\":\"ru\",\"notice\":\"\(String(repeating: "a", count: 1_001))\"}",
            "invalid JSON"
        ] {
            BackendTestURLProtocol.requestHandler = { Self.response($0, body: body) }
            do {
                _ = try await makeAPI().fetchNotice(locale: "ru")
                XCTFail("Expected invalid status response to be rejected")
            } catch { }
        }
    }

    func testOlderBackendAndServiceErrorsDoNotRetry() async {
        for status in [404, 503] {
            var requests = 0
            BackendTestURLProtocol.requestHandler = { request in
                requests += 1
                return Self.response(request, status: status, body: #"{"locale":"ru","notice":"unused"}"#)
            }
            do {
                _ = try await makeAPI().fetchNotice(locale: "ru")
                XCTFail("Expected HTTP failure")
            } catch let error as BackendContentError {
                XCTAssertEqual(error, .httpStatus(status, nil))
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(requests, 1)
        }
    }

    func testUnsupportedLocaleDoesNotSendRequest() async {
        BackendTestURLProtocol.requestHandler = { request in
            XCTFail("Unsupported locale must not send a request")
            return Self.response(request, body: "{}")
        }
        do {
            _ = try await makeAPI().fetchNotice(locale: "xx")
            XCTFail("Expected invalid locale")
        } catch let error as BackendContentError {
            XCTAssertEqual(error, .invalidRequest)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeAPI() -> HTTPAIServiceStatusAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BackendTestURLProtocol.self]
        return HTTPAIServiceStatusAPI(
            configuration: BackendConfiguration(baseURL: URL(string: "https://example.invalid/api")!),
            session: URLSession(configuration: configuration)
        )
    }

    private static func response(
        _ request: URLRequest,
        status: Int = 200,
        body: String
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
            Data(body.utf8)
        )
    }
}
