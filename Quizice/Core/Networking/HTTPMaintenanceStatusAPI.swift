import Foundation

protocol MaintenanceStatusAPI {
    func fetchMaintenanceNotice() async throws -> String?
}

final class HTTPMaintenanceStatusAPI: MaintenanceStatusAPI {
    private struct Status: Decodable {
        let active: Bool
        let message: String
    }

    private let url: URL
    private let session: URLSession

    init(configuration: BackendConfiguration, session: URLSession = .shared) {
        url = configuration.baseURL.appendingPathComponent("v1/maintenance/status")
        self.session = session
    }

    func fetchMaintenanceNotice() async throws -> String? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
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
        return status.active ? message : nil
    }
}
