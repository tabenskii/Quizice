import Foundation

/// Resolves production transports while preserving the offline fallback services.
enum BackendServiceFactory {
    static func authAPI(bundle: Bundle) -> AuthAPI {
        guard let configuration = BackendConfiguration.load(bundle: bundle) else {
            AppLog.auth.error("[Auth] Backend configuration is unavailable")
            return UnavailableAuthAPI()
        }
        return HTTPAuthAPI(configuration: configuration, metrics: AppMetricaAnalyticsTracker.shared)
    }

    static func aiQuizThemeService(accessProvider: AIQuizAccessProviding) -> AIQuizThemeServiceProtocol {
        guard let configuration = BackendConfiguration.load() else {
            return YandexAIQuizThemeService(apiKey: nil)
        }
        return BackendAIQuizThemeService(
            configuration: configuration,
            metrics: AppMetricaAnalyticsTracker.shared,
            accessProvider: accessProvider
        )
    }
}
