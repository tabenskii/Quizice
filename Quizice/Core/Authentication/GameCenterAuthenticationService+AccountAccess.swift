import Foundation
import UIKit

extension GameCenterAuthenticationService {
    func signIn(present: @escaping (UIViewController) -> Void) {
        requestSignIn(present: present, retryingConnection: false)
    }

    func retryConnection(present: @escaping (UIViewController) -> Void) {
        requestSignIn(present: present, retryingConnection: true)
    }

    var authenticatedAccountID: String? {
        guard case let .authenticated(userID, _) = state else { return nil }
        return userID
    }

    var accountAccessState: AppAccountAccessState {
        if accountOperationInProgress { return .loading }
        switch state {
        case .initializing, .authenticating:
            return .loading
        case .authenticated:
            return .authenticated
        case .deletionPending:
            return .deletionPending
        case .guest:
            return canCreateAccount ? .deleted : .signInRequired
        }
    }
}
