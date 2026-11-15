import GameKit
import UIKit

@MainActor
protocol GameCenterLocalPlayer: AnyObject {
    var isAuthenticated: Bool { get }
    var teamPlayerID: String { get }
    var authenticateHandler: ((UIViewController?, Error?) -> Void)? { get set }
    func identitySignature() async throws -> (URL, Data, Data, UInt64)
}

extension GKLocalPlayer: GameCenterLocalPlayer {
    func identitySignature() async throws -> (URL, Data, Data, UInt64) {
        try await fetchItemsForIdentityVerificationSignature()
    }
}

@MainActor
protocol GameCenterAccessPointPresenting: AnyObject {
    var isPresentingGameCenter: Bool { get }
    func trigger(handler: @escaping () -> Void)
}

extension GKAccessPoint: GameCenterAccessPointPresenting {}

@MainActor
final class GameCenterClient: GameCenterAuthenticating {
    private let player: GameCenterLocalPlayer
    private let notificationCenter: NotificationCenter
    private let accessPoint: GameCenterAccessPointPresenting
    private var presentAuthenticationController: ((UIViewController) -> Void)?
    private var authenticationObserver: NSObjectProtocol?
    private var authenticationAttemptID = UUID()
    private var stateChanged: ((GameCenterPlayerState) -> Void)?

    init(
        player: GameCenterLocalPlayer = GKLocalPlayer.local,
        notificationCenter: NotificationCenter = .default,
        accessPoint: GameCenterAccessPointPresenting = GKAccessPoint.shared
    ) {
        self.player = player
        self.accessPoint = accessPoint
        self.notificationCenter = notificationCenter
    }

    deinit {
        if let authenticationObserver {
            notificationCenter.removeObserver(authenticationObserver)
        }
    }

    func start(
        present: @escaping (UIViewController) -> Void,
        stateChanged: @escaping (GameCenterPlayerState) -> Void
    ) {
        let isRetry = self.stateChanged != nil
        self.stateChanged = stateChanged
        presentAuthenticationController = present
        let attemptID = UUID()
        authenticationAttemptID = attemptID
        AppLog.auth.notice("[Auth] Starting Game Center authentication")
        if authenticationObserver == nil {
            authenticationObserver = notificationCenter.addObserver(
                forName: NSNotification.Name.GKPlayerAuthenticationDidChangeNotificationName,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.publishCurrentState()
                }
            }
        }

        if isRetry { player.authenticateHandler = nil }
        player.authenticateHandler = { [weak self] viewController, error in
            Task { @MainActor [weak self] in
                guard let self, self.authenticationAttemptID == attemptID else { return }
                if let error {
                    let diagnostic = error as NSError
                    AppLog.auth.error(
                        "[Auth] Game Center callback failed: domain=\(diagnostic.domain, privacy: .public) code=\(diagnostic.code)"
                    )
                }
                if let viewController {
                    AppLog.auth.notice("[Auth] Presenting Game Center sign-in")
                    self.presentAuthenticationController?(viewController)
                    return
                }
                self.publishCurrentState()
            }
        }
        if isRetry, !player.isAuthenticated {
            // GameKit may suppress another callback after the player cancelled.
            // Keep retry available until it supplies UI or an authenticated player.
            publishCurrentState()
        }
    }

    func signIn(
        present: @escaping (UIViewController) -> Void,
        stateChanged: @escaping (GameCenterPlayerState) -> Void
    ) {
        if self.stateChanged == nil {
            start(present: present, stateChanged: stateChanged)
        } else {
            self.stateChanged = stateChanged
            presentAuthenticationController = present
        }
        publishCurrentState()
        guard !player.isAuthenticated, !accessPoint.isPresentingGameCenter else { return }
        accessPoint.trigger { [weak self] in
            Task { @MainActor [weak self] in self?.publishCurrentState() }
        }
    }

    func fetchIdentity(bundleIdentifier: String) async throws -> GameCenterIdentity {
        guard player.isAuthenticated, player.teamPlayerID.isEmpty == false else {
            throw GameCenterClientError.notAuthenticated
        }
        AppLog.auth.notice("[Auth] Requesting Game Center identity signature")
        let (publicKeyURL, signature, salt, timestamp): (URL, Data, Data, UInt64)
        do {
            (publicKeyURL, signature, salt, timestamp) = try await player.identitySignature()
        } catch {
            let diagnostic = error as NSError
            AppLog.auth.error(
                "[Auth] Game Center identity signature failed: domain=\(diagnostic.domain, privacy: .public) code=\(diagnostic.code)"
            )
            throw error
        }
        AppLog.auth.notice("[Auth] Game Center identity signature received")
        return GameCenterIdentity(
            teamPlayerId: player.teamPlayerID,
            bundleId: bundleIdentifier,
            publicKeyUrl: publicKeyURL.absoluteString,
            signature: signature.base64EncodedString(),
            salt: salt.base64EncodedString(),
            timestamp: String(timestamp)
        )
    }

    private func publishCurrentState() {
        let isAuthenticated = player.isAuthenticated
        let hasTeamPlayerID = !player.teamPlayerID.isEmpty
        AppLog.auth.notice(
            "[Auth] Game Center state: authenticated=\(isAuthenticated) hasTeamPlayerID=\(hasTeamPlayerID)"
        )
        if player.isAuthenticated, player.teamPlayerID.isEmpty == false {
            stateChanged?(.authenticated(teamPlayerID: player.teamPlayerID))
        } else {
            stateChanged?(.unavailable)
        }
    }
}

enum GameCenterClientError: Error, Equatable {
    case notAuthenticated
}
