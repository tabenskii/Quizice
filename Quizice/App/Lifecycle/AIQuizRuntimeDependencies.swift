import Foundation

struct AIQuizRuntimeDependencies {
    let accessProvider: AIQuizAccessProviding
    let themeService: AIQuizThemeServiceProtocol

    static func live(
        backendConfiguration: BackendConfiguration? = BackendConfiguration.load(),
        backendAccessProvider: AIQuizAccessProviding = AIQuizAccessStore.shared,
        usesDebugBackendAuthentication: Bool = false,
        metrics: BackendRequestMetricRecording = AppMetricaAnalyticsTracker.shared
    ) -> AIQuizRuntimeDependencies {
#if DEBUG
        DebugYandexAIAPIKeyStore.cacheEnvironmentAPIKeyIfPresent()
#if targetEnvironment(simulator)
        let isDebugSimulator = true
#else
        let isDebugSimulator = false
#endif
        return resolve(
            usesDirectAI: !usesDebugBackendAuthentication
                && (isDebugSimulator || DebugAIRuntimeSettings.isDirectAIEnabled),
            backendConfiguration: backendConfiguration,
            backendAccessProvider: backendAccessProvider,
            directAPIKeyProvider: DebugYandexAIAPIKeyStore.resolveAPIKey,
            directUnauthorizedHandler: DebugYandexAIAPIKeyStore.removeRejectedAPIKey,
            metrics: metrics
        )
#else
        return resolve(
            usesDirectAI: false,
            backendConfiguration: backendConfiguration,
            backendAccessProvider: backendAccessProvider,
            directAPIKeyProvider: { nil },
            directUnauthorizedHandler: {},
            metrics: metrics
        )
#endif
    }

    static func resolve(
        usesDirectAI: Bool,
        backendConfiguration: BackendConfiguration?,
        backendAccessProvider: AIQuizAccessProviding,
        directAPIKeyProvider: () -> String?,
        directUnauthorizedHandler: @escaping () -> Void,
        metrics: BackendRequestMetricRecording = NoopBackendRequestMetricRecorder()
    ) -> AIQuizRuntimeDependencies {
        if usesDirectAI {
            AppLog.quiz.notice("🧪 DIRECT AI: local Debug API key service selected")
            return AIQuizRuntimeDependencies(
                accessProvider: AlwaysAvailableAIQuizAccessProvider(),
                themeService: YandexAIQuizThemeService(
                    apiKey: directAPIKeyProvider(),
                    onUnauthorized: directUnauthorizedHandler
                )
            )
        }

        guard let backendConfiguration else {
            return AIQuizRuntimeDependencies(
                accessProvider: backendAccessProvider,
                themeService: UnavailableAIQuizThemeService()
            )
        }

        return AIQuizRuntimeDependencies(
            accessProvider: backendAccessProvider,
            themeService: BackendAIQuizThemeService(
                configuration: backendConfiguration,
                metrics: metrics,
                accessProvider: backendAccessProvider
            )
        )
    }
}

#if DEBUG
enum DebugAIRuntimeSettings {
    static let useDirectAIKey = "quizice.debug.ai.use-direct-service"

    static var isDirectAIEnabled: Bool {
        UserDefaults.standard.bool(forKey: useDirectAIKey)
    }
}
#endif

private final class AlwaysAvailableAIQuizAccessProvider: AIQuizAccessProviding {
    let isAIQuizAvailable = true
}

private final class UnavailableAIQuizThemeService: AIQuizThemeServiceProtocol {
    func generateQuizTheme(
        configuration: AIQuizGenerationConfiguration
    ) async throws -> QuizTheme {
        throw YandexAIQuizThemeServiceError.authenticationRequired
    }
}
