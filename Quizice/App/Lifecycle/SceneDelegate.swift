import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    private static let gameCenterBannerSettleDelay: TimeInterval = 2.5

    var window: UIWindow?
    private var coordinator: QuizFlowCoordinator?
    private let launchOverlayPresenter = LaunchOverlayPresenter()
    private var authenticationService: GameCenterAuthenticationService?
    private var accountAccessPresenter: AppAccountAccessPresenter?
    private var initialPreparationTask: Task<Void, Never>?

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
            window.makeKeyAndVisible()
        } else {
            let authenticationService = GameCenterAuthenticationService.live()
            self.authenticationService = authenticationService
            let aiRuntimeDependencies = AIQuizRuntimeDependencies.live(
                backendAccessProvider: AIQuizAccessStore.shared
            )
            let coordinator = QuizFlowCoordinator(
                window: window,
                aiQuizThemeService: aiRuntimeDependencies.themeService,
                aiQuizAccessProvider: aiRuntimeDependencies.accessProvider,
                accountManager: authenticationService
            )
            coordinator.start()
            self.coordinator = coordinator
            let appearance = AppAppearanceStore.shared.appearance(
                compatibleWith: window.traitCollection
            )
            startLaunch(in: window, coordinator: coordinator,
                        authenticationService: authenticationService, appearance: appearance)
        }
        self.window = window
    }

    func startLaunch(
        in window: UIWindow,
        coordinator: QuizFlowCoordinator,
        authenticationService: GameCenterAuthenticationService,
        appearance: AppAppearance
    ) {
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
        initialPreparationTask?.cancel()
        // Keep preparation alive when sign-in UI or the deadline reveals the app.
        // Game Center cannot block catalog loading; account changes are checked by the repository.
        let preparationTask = Task { @MainActor [weak coordinator, weak authenticationService] in
            async let authentication: Void? = authenticationService?.waitForInitialAuthentication()
            await coordinator?.prepareInitialCatalog()
            await authentication
        }
        initialPreparationTask = preparationTask
        launchOverlayPresenter.present(
            in: window,
            appearance: appearance,
            preparation: { await preparationTask.value },
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
        window.makeKeyAndVisible()
        authenticationService.start { [weak accountAccessPresenter, weak launchOverlayPresenter] controller in
            // Queue first: dismissing the splash flushes the request above the
            // account gate, where required user interaction remains accessible.
            accountAccessPresenter?.presentSystemViewController(controller)
            launchOverlayPresenter?.dismiss(animated: false)
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
        initialPreparationTask?.cancel()
        initialPreparationTask = nil
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
