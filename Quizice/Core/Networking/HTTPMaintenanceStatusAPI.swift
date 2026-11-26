import Foundation

struct MaintenanceNotice: Equatable, Sendable {
    let message: String
    let sfSymbol: String?
}

protocol MaintenanceStatusAPI {
    func fetchMaintenanceNotice(locale: String) async throws -> MaintenanceNotice?
}

final class HTTPMaintenanceStatusAPI: MaintenanceStatusAPI {
    private struct Status: Decodable {
        let active: Bool
        let message: String
        let sfSymbol: String?

        private enum CodingKeys: String, CodingKey {
            case active, message, sfSymbol
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            active = try container.decode(Bool.self, forKey: .active)
            message = try container.decode(String.self, forKey: .message)
            sfSymbol = try? container.decode(String.self, forKey: .sfSymbol)
        }
    }

    private let url: URL
    private let session: URLSession

    init(configuration: BackendConfiguration, session: URLSession = .shared) {
        url = configuration.baseURL.appendingPathComponent("v1/maintenance/status")
        self.session = session
    }

    func fetchMaintenanceNotice(locale: String) async throws -> MaintenanceNotice? {
        guard AppLanguagePreference.explicitPreference(for: locale) != nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { throw BackendContentError.invalidRequest }
        components.queryItems = [URLQueryItem(name: "locale", value: locale)]
        guard let requestURL = components.url else { throw BackendContentError.invalidRequest }
        var request = URLRequest(url: requestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw BackendContentError.invalidResponse }
        guard response.statusCode == 200 else {
            throw BackendContentError.httpStatus(response.statusCode, nil)
        }
        guard data.count <= 16 * 1024 else { throw BackendContentError.contractViolation }
        guard let status = try? JSONDecoder().decode(Status.self, from: data) else { throw BackendContentError.decoding }
        let message = status.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard status.message.unicodeScalars.count <= 500, !status.active || !message.isEmpty else {
            throw BackendContentError.contractViolation
        }
        return status.active ? MaintenanceNotice(message: message, sfSymbol: status.sfSymbol) : nil
    }
}
