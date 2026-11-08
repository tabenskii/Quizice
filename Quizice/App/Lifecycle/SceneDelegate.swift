import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    private static let gameCenterBannerSettleDelay: TimeInterval = 2.5

    var window: UIWindow?
    private var coordinator: QuizFlowCoordinator?
    private let launchOverlayPresenter = LaunchOverlayPresenter()
    private var authenticationService: GameCenterAuthenticationService?
    private var accountAccessPresenter: AppAccountAccessPresenter?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        AppAppearanceStore.shared.registerInitialDefaults()
        let window = UIWindow(windowScene: windowScene)
        let isRunningTests = ProcessInfo.processInfo.environment["QUIZICE_XCTEST_SMOKE_HOST"] == "1"
            || NSClassFromString("XCTestCase") != nil
        if isRunningTests {
            window.rootViewController = UIViewController()
        } else {
#if DEBUG && targetEnvironment(simulator)
            // Local UI development must not require a real Game Center account.
            // Opt in explicitly when testing the production authentication flow.
            if ProcessInfo.processInfo.environment["QUIZICE_REQUIRE_GAME_CENTER"] != "1" {
                startSimulatorContent(in: window)
                window.makeKeyAndVisible()
                self.window = window
                return
            }
#endif
            let authenticationService = GameCenterAuthenticationService.live()
            self.authenticationService = authenticationService
            let aiRuntimeDependencies = AIQuizRuntimeDependencies.live(
                backendAccessProvider: AIQuizAccessStore.shared
            )
            let coordinator = QuizFlowCoordinator(
                window: window,
                aiQuizThemeService: aiRuntimeDependencies.themeService,
                aiQuizAccessProvider: aiRuntimeDependencies.accessProvider,
                accountManager: authenticationService,
                statisticsHistoryStore: .live()
            )
            coordinator.start()
            self.coordinator = coordinator
            let appearance = AppAppearanceStore.shared.appearance(
                compatibleWith: window.traitCollection
            )
            let accountAccessPresenter = AppAccountAccessPresenter(
                window: window,
                accessProvider: authenticationService,
                accountManager: authenticationService,
                prepareContentForReveal: { [weak coordinator] completion in
                    guard let coordinator else { completion(); return }
                    coordinator.presentInitialOnboardingIfNeeded(completion: completion)
                },
                resetContent: { [weak coordinator] completion in
                    guard let coordinator else { completion(); return }
                    coordinator.resetAccountNavigation(completion: completion)
                },
                presentSystemContent: { [weak coordinator] in coordinator?.presentSystemViewController($0) }
            )
            self.accountAccessPresenter = accountAccessPresenter
            accountAccessPresenter.start()
            launchOverlayPresenter.present(
                in: window,
                appearance: appearance,
                preparation: { [weak coordinator] in await coordinator?.prepareInitialCatalog() },
                prepareContentForReveal: { [weak accountAccessPresenter] completion in
                    guard let accountAccessPresenter else { completion(); return }
                    accountAccessPresenter.prepareInitialContent(completion: completion)
                },
                onDismissed: { [weak coordinator, weak authenticationService, weak accountAccessPresenter] in
                    accountAccessPresenter?.launchDidFinish()
                    guard authenticationService?.accountAccessState == .authenticated else { return }
                    coordinator?.restoreInitialAccessibilityFocusAfterLaunch()
                    // GameKit's welcome banner can temporarily take VoiceOver focus.
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.gameCenterBannerSettleDelay) {
                        [weak coordinator, weak authenticationService] in
                        guard authenticationService?.accountAccessState == .authenticated else { return }
                        coordinator?.restoreInitialAccessibilityFocusAfterLaunch()
                    }
                }
            )
        }
        window.makeKeyAndVisible()
        self.window = window
        authenticationService?.start { [weak accountAccessPresenter] in
            accountAccessPresenter?.presentSystemViewController($0)
        }

    }

#if DEBUG && targetEnvironment(simulator)
    private func startSimulatorContent(in window: UIWindow) {
        StatisticsStore().activateGuest()
        let aiDependencies = AIQuizRuntimeDependencies.live()
        let coordinator = QuizFlowCoordinator(
            window: window,
            aiQuizThemeService: aiDependencies.themeService,
            aiQuizAccessProvider: aiDependencies.accessProvider
        )
        coordinator.start()
        self.coordinator = coordinator
        launchOverlayPresenter.present(
            in: window,
            appearance: AppAppearanceStore.shared.appearance(compatibleWith: window.traitCollection),
            preparation: { [weak coordinator] in await coordinator?.prepareInitialCatalog() },
            prepareContentForReveal: { [weak coordinator] completion in
                guard let coordinator else { completion(); return }
                coordinator.presentInitialOnboardingIfNeeded(completion: completion)
            },
            onDismissed: { [weak coordinator] in
                coordinator?.restoreInitialAccessibilityFocusAfterLaunch()
            }
        )
    }
#endif

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
        launchOverlayPresenter.dismiss(animated: false)
        accountAccessPresenter?.stop()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        authenticationService?.retrySynchronization()
        Task { await PersistentQuestionAnswerOutbox.shared.synchronize() }
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
    }
}
