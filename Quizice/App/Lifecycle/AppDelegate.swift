import UIKit
import SwiftData
#if DEBUG
import Pulse
import PulseProxy
#endif

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var modelContainer: ModelContainer?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
#if DEBUG
        NetworkLogger.shared = NetworkLogger {
            $0.sensitiveHeaders = [
                "Authorization",
                BackendConfiguration.authorizationHeader,
                "Cookie",
                "Set-Cookie",
                "X-API-Key",
                "X-Dev-Auth-Secret",
                "X-Test-Account-Key",
                "X-Yandex-API-Key"
            ]
            $0.sensitiveQueryItems = ["api_key", "access_token", "token"]
            $0.sensitiveDataFields = [
                "accessToken",
                "access_token",
                "apiKey",
                "api_key",
                "publicKeyUrl",
                "salt",
                "signature",
                "token"
            ]
        }
        NetworkLogger.enableProxy()
#endif
        ResultMessagesRepository.shared.start()
        AppMetricaAnalyticsTracker.shared.activate()
        modelContainer = makeModelContainer()
        let themeRepository = ThemeCatalogRepository.shared
        if let modelContainer {
            themeRepository.setModelContext(modelContainer.mainContext)
        }
        Task { await PersistentQuestionAnswerOutbox.shared.synchronize() }
        return true
    }

    /// Attempts to build a persistent SwiftData container and, if that fails
    /// (e.g. an incompatible store on disk), falls back to an in-memory one so
    /// the app still launches in a degraded but usable state instead of crashing.
    private func makeModelContainer() -> ModelContainer? {
        let schema = SwiftDataThemeStore.schema
        do {
            return try ModelContainer(for: schema)
        } catch {
            AppLog.persistence.error("Persistent ModelContainer creation failed: \(error, privacy: .public)")
            AppMetricaAnalyticsTracker.shared.reportOperationalError(error, context: .persistentStore)
        }

        do {
            let inMemoryConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: inMemoryConfiguration)
        } catch {
            AppLog.persistence.error("In-memory ModelContainer creation failed: \(error, privacy: .public)")
            AppMetricaAnalyticsTracker.shared.reportOperationalError(error, context: .inMemoryStore)
            return nil
        }
    }
    
    // MARK: UISceneSession Lifecycle
    
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
    
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
    
    
}
