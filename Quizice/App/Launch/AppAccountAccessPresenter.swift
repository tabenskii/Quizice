import SwiftUI
import UIKit

/// Keeps account access above every quiz, onboarding and settings presentation.
@MainActor
final class AppAccountAccessPresenter {
    static let accessibilityIdentifier = "accountStartScreen"

    private let window: UIWindow
    private let accessProvider: any AppAccountAccessProviding
    private let accountManager: any AccountManaging
    private let prepareContentForReveal: (@escaping () -> Void) -> Void
    private let resetContent: (@escaping () -> Void) -> Void
    private let presentSystemContent: (UIViewController) -> Void
    private let model = AccountStartModel()
    private var gateWindow: UIWindow?
    private var isStarted = false
    private var canPrepareContent = false
    private var launchFinished = false
    private var hasAdmittedAccount = false
    private var admittedAccountID: String?
    private var isResettingContent = false
    private var preparationID: UUID?
    private var initialCompletions: [() -> Void] = []
    private var pendingSystemController: UIViewController?
    private var operationTask: Task<Void, Never>?
    private var connectionDeadlineTask: Task<Void, Never>?
    private let waitForConnectionTimeout: @MainActor () async throws -> Void
    private weak var coveredView: UIView?
    private var previousAccessibilityHidden = false
    private var previousInteractionEnabled = true

    init(
        window: UIWindow,
        accessProvider: any AppAccountAccessProviding,
        accountManager: any AccountManaging,
        prepareContentForReveal: @escaping (@escaping () -> Void) -> Void,
        resetContent: @escaping (@escaping () -> Void) -> Void,
        presentSystemContent: @escaping (UIViewController) -> Void,
        waitForConnectionTimeout: @escaping @MainActor () async throws -> Void = {
            try await Task.sleep(nanoseconds: 20_000_000_000)
        }
    ) {
        self.window = window
        self.accessProvider = accessProvider
        self.accountManager = accountManager
        self.prepareContentForReveal = prepareContentForReveal
        self.resetContent = resetContent
        self.presentSystemContent = presentSystemContent
        self.waitForConnectionTimeout = waitForConnectionTimeout
    }

    func start() {
        guard !isStarted, let scene = window.windowScene else { return }
        isStarted = true
        coveredView = window.rootViewController?.view
        previousAccessibilityHidden = coveredView?.accessibilityElementsHidden ?? false
        previousInteractionEnabled = window.isUserInteractionEnabled
        let appearance = AppAppearanceStore.shared.appearance(compatibleWith: window.traitCollection)
        let background = FakeLaunchVisualStyle(appearance: appearance).backgroundColor
        let host = UIHostingController(rootView: AccountStartView(
            model: model, appearance: appearance, onPrimaryAction: { [weak self] in self?.performPrimaryAction() }
        ))
        host.isModalInPresentation = true
        host.view.accessibilityIdentifier = Self.accessibilityIdentifier
        host.view.backgroundColor = background
        host.overrideUserInterfaceStyle = appearance.resolvedInterfaceStyle
        let gate = UIWindow(windowScene: scene)
        gate.windowLevel = UIWindow.Level(rawValue: window.windowLevel.rawValue + 0.5)
        gate.backgroundColor = background
        gate.accessibilityIdentifier = Self.accessibilityIdentifier
        gate.accessibilityViewIsModal = true
        gate.rootViewController = host
        gateWindow = gate
        showGate()
        accessProvider.accountAccessStateDidChange = { [weak self] _ in
            // Service callbacks can arrive before its account scopes finish changing.
            Task { @MainActor [weak self] in self?.refreshAccess() }
        }
        refreshAccess()
    }

    func prepareInitialContent(completion: @escaping () -> Void) {
        guard isStarted else { completion(); return }
        canPrepareContent = true
        initialCompletions.append(completion)
        refreshAccess()
    }

    func launchDidFinish() {
        guard isStarted else { return }
        launchFinished = true
        canPrepareContent = true
        refreshAccess()
        // The launch overlay restores its own accessibility snapshot on dismissal.
        applyContentAccess(isLocked: gateWindow?.isHidden == false)
        if gateWindow?.isHidden == false { gateWindow?.makeKeyAndVisible() }
        if let controller = pendingSystemController {
            pendingSystemController = nil
            presentSystemViewController(controller)
        }
    }

    func presentSystemViewController(_ controller: UIViewController) {
        guard isStarted else { return }
        guard launchFinished else { pendingSystemController = controller; return }
        guard let gateWindow, !gateWindow.isHidden, var presenter = gateWindow.rootViewController else {
            presentSystemContent(controller)
            return
        }
        while let presented = presenter.presentedViewController { presenter = presented }
        guard controller.presentingViewController == nil, presenter !== controller else { return }
        presenter.present(controller, animated: true)
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        accessProvider.accountAccessStateDidChange = nil
        operationTask?.cancel()
        operationTask = nil
        connectionDeadlineTask?.cancel()
        connectionDeadlineTask = nil
        preparationID = nil
        pendingSystemController = nil
        initialCompletions.removeAll()
        gateWindow?.isHidden = true
        gateWindow?.rootViewController = nil
        gateWindow = nil
        applyContentAccess(isLocked: false)
    }

    private func refreshAccess() {
        guard isStarted else { return }
        let state = accessProvider.accountAccessState
        model.state = state
        model.needsGameCenterSignIn = accessProvider.needsGameCenterSignIn
        if state != .loading {
            connectionDeadlineTask?.cancel()
            connectionDeadlineTask = nil
        }
        guard state == .authenticated else {
            preparationID = nil
            showGate()
            if state != .loading, hasAdmittedAccount {
                resetPreviousAccountContent()
            }
            if state == .loading {
                scheduleConnectionDeadline()
                if model.errorMessage != nil { finishInitialPreparation() }
            } else {
                finishInitialPreparation()
            }
            return
        }
        model.errorMessage = nil
        pendingSystemController = nil
        if hasAdmittedAccount, admittedAccountID != accessProvider.authenticatedAccountID {
            showGate()
            resetPreviousAccountContent()
        }
        guard canPrepareContent, !isResettingContent else { return }
        guard gateWindow?.isHidden == false else { finishInitialPreparation(); return }
        guard preparationID == nil else { return }
        let id = UUID()
        preparationID = id
        prepareContentForReveal { [weak self] in
            guard let self, self.isStarted, self.preparationID == id,
                  self.accessProvider.accountAccessState == .authenticated,
                  !self.isResettingContent else { return }
            self.preparationID = nil
            self.hasAdmittedAccount = true
            self.admittedAccountID = self.accessProvider.authenticatedAccountID
            self.gateWindow?.isHidden = true
            if self.launchFinished {
                self.applyContentAccess(isLocked: false)
                self.window.makeKeyAndVisible()
            }
            self.finishInitialPreparation()
        }
    }

    private func resetPreviousAccountContent() {
        hasAdmittedAccount = false
        admittedAccountID = nil
        isResettingContent = true
        resetContent { [weak self] in
            guard let self, self.isStarted else { return }
            self.isResettingContent = false
            self.refreshAccess()
        }
    }

    private func showGate() {
        let wasHidden = gateWindow?.isHidden != false
        gateWindow?.isHidden = false
        applyContentAccess(isLocked: true)
        if launchFinished, wasHidden { gateWindow?.makeKeyAndVisible() }
    }

    private func applyContentAccess(isLocked: Bool) {
        window.isUserInteractionEnabled = isLocked ? false : previousInteractionEnabled
        coveredView?.accessibilityElementsHidden = isLocked ? true : previousAccessibilityHidden
    }

    private func finishInitialPreparation() {
        let completions = initialCompletions
        initialCompletions.removeAll()
        completions.forEach { $0() }
    }

    private func scheduleConnectionDeadline() {
        guard connectionDeadlineTask == nil, model.errorMessage == nil else { return }
        connectionDeadlineTask = Task { @MainActor [weak self, waitForConnectionTimeout] in
            do { try await waitForConnectionTimeout() } catch { return }
            guard let self, self.isStarted, !Task.isCancelled,
                  self.accessProvider.accountAccessState == .loading else { return }
            self.connectionDeadlineTask = nil
            self.model.errorMessage = L10n.AccountStart.connectionFailedMessage
            self.finishInitialPreparation()
        }
    }

    private func performPrimaryAction() {
        guard operationTask == nil else { return }
        let state = accessProvider.accountAccessState
        let canRetryConnection = state == .loading && model.errorMessage != nil
        model.errorMessage = nil
        if state == .signInRequired || canRetryConnection {
            let present: (UIViewController) -> Void = { [weak self] in self?.presentSystemViewController($0) }
            if canRetryConnection { accessProvider.retryConnection(present: present) }
            else { accessProvider.signIn(present: present) }
            return
        }
        guard state == .deleted || state == .deletionPending else { return }
        operationTask = Task { @MainActor [weak self] in
            guard let self, self.isStarted, !Task.isCancelled else { return }
            defer { self.operationTask = nil }
            do {
                if state == .deleted { try await self.accountManager.createAccount() }
                else { try await self.accountManager.deleteAccount() }
            } catch {
                guard self.isStarted, !Task.isCancelled else { return }
                if state == .deleted {
                    self.model.errorMessage = L10n.Settings.Account.creationFailedMessage
                } else {
                    switch error {
                    case GameCenterClientError.notAuthenticated, GameCenterAuthenticationError.playerChanged:
                        self.model.errorMessage = L10n.AccountStart.deletionSignInRequired
                    case AccountDeletionError.localCleanupFailed:
                        self.model.errorMessage = L10n.Settings.Account.cleanupRequiredMessage
                    case AccountDeletionError.sessionExpired:
                        self.model.errorMessage = L10n.Settings.Account.sessionExpiredMessage
                    default:
                        self.model.errorMessage = L10n.Settings.Account.deletionFailedMessage
                    }
                }
            }
            self.refreshAccess()
        }
    }
}
