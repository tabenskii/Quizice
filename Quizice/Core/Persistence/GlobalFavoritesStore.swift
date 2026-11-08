import Foundation

extension Notification.Name {
    static let favoritesDidChange = Notification.Name("quizice.favorites.changed")
}

struct FavoriteMutation: Codable, Equatable {
    let mutationId: UUID
    let addThemeIds: [String]
    let removeThemeIds: [String]
}

struct BackendFavoritesSnapshot: Codable, Equatable {
    let favoriteThemeIds: [String]
    let revision: Int64
    var mutationId: UUID?
}

/// One encoded record makes migration, guest claiming and mutation creation atomic.
/// The lock also serializes stores retained by different presenters.
final class GlobalFavoritesStore {
    private struct Account: Codable {
        var baseline: [String] = []
        var revision: Int64?
        var pending: [FavoriteMutation] = []
        var rejected: [FavoriteMutation] = []
        var localRevision = 0
        var hasSelection = false
        var explicitGuestSelection = false
        var explicitGuestThemeIDs: [String]?

        var visible: [String] {
            pending.reduce(baseline) { result, mutation in
                var result = result.filter { !mutation.removeThemeIds.contains($0) }
                result.append(contentsOf: mutation.addThemeIds.filter { !result.contains($0) })
                return result
            }
        }
    }

    private struct State: Codable {
        var accounts: [String: Account] = [:]
        var guest = Account()
        var erasedUsers: Set<String> = []
        var guestLegacyImported: Bool?
    }

    private static let lock = NSRecursiveLock()
    private static let key = "quizice.favorites.global.v2"
    private let defaults: UserDefaults
    private let notifications: NotificationCenter
    private let makeID: () -> UUID

    init(defaults: UserDefaults = .standard, notifications: NotificationCenter = .default,
         makeID: @escaping () -> UUID = UUID.init) {
        self.defaults = defaults
        self.notifications = notifications
        self.makeID = makeID
    }

    func favorites(for userID: String?) -> [String]? {
        read(userID) { $0.hasSelection ? $0.visible : nil }
    }

    func localRevision(for userID: String?) -> Int { read(userID) { $0.localRevision } }
    func nextMutation(for userID: String) -> FavoriteMutation? { read(userID) { $0.pending.first } }
    func hasPending(for userID: String?) -> Bool {
        read(userID) { !$0.pending.isEmpty || $0.explicitGuestSelection }
    }

    /// Compute intents from the editor's original selection. Hidden translations
    /// and remote changes arriving while the editor is open survive.
    func select(_ selected: [String], initiallySelected: Set<String>, visibleIDs: Set<String>, for userID: String?) {
        update(userID) { account in
            let selected = Self.normalized(selected).filter(visibleIDs.contains)
            let additions = selected.filter { !initiallySelected.contains($0) }
            let removals = initiallySelected.intersection(visibleIDs).subtracting(Set(selected)).sorted()
            if userID == nil {
                account.baseline.removeAll { removals.contains($0) }
                account.baseline.append(contentsOf: additions.filter { !account.baseline.contains($0) })
                account.explicitGuestSelection = true
                account.explicitGuestThemeIDs = selected
            } else if !additions.isEmpty || !removals.isEmpty {
                account.pending.append(FavoriteMutation(mutationId: makeID(), addThemeIds: additions, removeThemeIds: removals))
            }
            account.hasSelection = true
            account.localRevision += 1
        }
    }

    func apply(_ snapshot: BackendFavoritesSnapshot, for userID: String, acknowledging mutationID: UUID? = nil) {
        update(userID) { account in
            if let mutationID { account.pending.removeAll { $0.mutationId == mutationID } }
            if snapshot.revision >= (account.revision ?? -1) {
                account.baseline = snapshot.favoriteThemeIds
                account.revision = snapshot.revision
                account.hasSelection = true
            }
            account.localRevision += 1
        }
    }

    /// Retain terminal failures for diagnosis without blocking healthy edits.
    func reject(_ mutation: FavoriteMutation, for userID: String, isolateInvalidThemes: Bool = false) {
        update(userID) { account in
            account.pending.removeAll { $0.mutationId == mutation.mutationId }
            account.rejected.append(mutation)
            account.rejected = Array(account.rejected.suffix(100))
            if isolateInvalidThemes && mutation.addThemeIds.count + mutation.removeThemeIds.count > 1 {
                let additions = mutation.addThemeIds.map { FavoriteMutation(mutationId: makeID(), addThemeIds: [$0], removeThemeIds: []) }
                let removals = mutation.removeThemeIds.map { FavoriteMutation(mutationId: makeID(), addThemeIds: [], removeThemeIds: [$0]) }
                account.pending.insert(contentsOf: additions + removals, at: 0)
            }
            account.localRevision += 1
        }
    }

    func eraseData(for userID: String) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        var state = load()
        state.accounts.removeValue(forKey: userID)
        state.erasedUsers.insert(userID)
        state.guest = Account()
        save(state)
    }

    private func read<T>(_ userID: String?, _ body: (Account) -> T) -> T {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        var state = load()
        prepare(userID, state: &state)
        save(state)
        return body(userID.flatMap { state.accounts[$0] } ?? (userID == nil ? state.guest : Account()))
    }

    private func update(_ userID: String?, _ body: (inout Account) -> Void) {
        Self.lock.lock()
        var state = load()
        prepare(userID, state: &state)
        if let userID {
            guard !state.erasedUsers.contains(userID) else { Self.lock.unlock(); return }
            var account = state.accounts[userID] ?? Account()
            body(&account)
            state.accounts[userID] = account
        } else {
            body(&state.guest)
        }
        save(state)
        Self.lock.unlock()
        notifications.post(name: .favoritesDidChange, object: userID)
    }

    private func prepare(_ userID: String?, state: inout State) {
        if state.guestLegacyImported != true {
            if !state.guest.hasSelection {
                var legacy = defaults.stringArray(forKey: OnboardingProgressStore.Keys.preferredThemeIDs) ?? []
                for locale in ["de", "en", "es", "fr", "it", "ru"] {
                    legacy += defaults.stringArray(forKey: OnboardingProgressStore.Keys.preferredThemeIDs(locale: locale)) ?? []
                }
                state.guest.baseline = Self.normalized(legacy)
                state.guest.hasSelection = !legacy.isEmpty
            }
            // Old unowned data remains locally visible but is never claimable.
            state.guestLegacyImported = true
        }
        guard let userID, !state.erasedUsers.contains(userID) else { return }
        if state.accounts[userID] == nil {
            var account = Account()
            let suffix = ".user." + Data(userID.utf8).base64EncodedString()
            var pending: [String] = []
            for locale in ["de", "en", "es", "fr", "it", "ru"] {
                let key = OnboardingProgressStore.Keys.preferredThemeIDs(locale: locale) + suffix
                if let ids = defaults.stringArray(forKey: key) {
                    account.hasSelection = true
                    account.baseline = Self.normalized(account.baseline + ids)
                    if defaults.bool(forKey: OnboardingProgressStore.Keys.pendingThemePreferences(locale: locale) + suffix) {
                        pending = Self.normalized(pending + ids)
                    }
                }
            }
            // Legacy lists lack a baseline. Never infer removals from them.
            for start in stride(from: 0, to: pending.count, by: 100) {
                account.pending.append(FavoriteMutation(mutationId: makeID(),
                    addThemeIds: Array(pending[start..<min(start + 100, pending.count)]), removeThemeIds: []))
            }
            state.accounts[userID] = account
        }
        if state.guest.explicitGuestSelection {
            let ids = state.guest.explicitGuestThemeIDs ?? state.guest.visible
            if !ids.isEmpty {
                state.accounts[userID]?.pending.append(FavoriteMutation(mutationId: makeID(), addThemeIds: ids, removeThemeIds: []))
            }
            state.accounts[userID]?.hasSelection = true
            state.guest = Account()
        }
    }

    private func load() -> State {
        guard let data = defaults.data(forKey: Self.key) else { return State() }
        guard let state = try? JSONDecoder().decode(State.self, from: data) else {
            defaults.set(data, forKey: Self.key + ".corrupt")
            return State()
        }
        return state
    }

    private func save(_ state: State) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.key)
    }

    private static func normalized(_ ids: [String]) -> [String] {
        BackendContentResponseValidator.normalizedThemeIDs(ids)
    }
}
