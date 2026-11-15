import Foundation

protocol AIServiceStatusAPI {
    func fetchNotice(locale: String) async throws -> String?
}

/// An advisory request: it never authenticates or starts an AI generation.
final class HTTPAIServiceStatusAPI: AIServiceStatusAPI {
    private struct Response: Decodable {
        let locale: String
        let notice: String?
    }

    private let baseURL: URL
    private let session: URLSession

    init(configuration: BackendConfiguration, session: URLSession = .shared) {
        baseURL = configuration.baseURL
        self.session = session
    }

    func fetchNotice(locale: String) async throws -> String? {
        guard AppLanguagePreference.explicitPreference(for: locale) != nil,
              var components = URLComponents(
                url: baseURL.appendingPathComponent("v1/ai/status"),
                resolvingAgainstBaseURL: false
              ) else { throw BackendContentError.invalidRequest }
        components.queryItems = [URLQueryItem(name: "locale", value: locale)]
        guard let url = components.url else { throw BackendContentError.invalidRequest }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw BackendContentError.invalidResponse }
        guard response.statusCode == 200 else {
            throw BackendContentError.httpStatus(response.statusCode, nil)
        }
        guard data.count <= 16 * 1024 else { throw BackendContentError.contractViolation }
        let status: Response
        do {
            status = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw BackendContentError.decoding
        }
        guard status.locale == locale, (status.notice?.count ?? 0) <= 1_000 else {
            throw BackendContentError.contractViolation
        }
        let notice = status.notice?.trimmingCharacters(in: .whitespacesAndNewlines)
        return notice?.isEmpty == false ? notice : nil
    }
}
