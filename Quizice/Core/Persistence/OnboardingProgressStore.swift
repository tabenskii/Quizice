import Foundation

protocol OnboardingProgressStoring: AnyObject {
    var needsOnboarding: Bool { get }
    var preferenceUserID: String? { get }
    var preferredThemeIDs: Set<String> { get }

    func complete(preferredThemeIDs: Set<String>)
    func storedPreferredThemeIDs(locale: String) -> [String]?
    func orderedPreferredThemeIDs(locale: String) -> [String]
    func complete(preferredThemeIDs: [String], locale: String)
    func hasPendingThemePreferences(locale: String) -> Bool
    func complete(preferredThemeIDs: [String], visibleThemeIDs: Set<String>, initiallySelected: Set<String>, locale: String)
}

extension OnboardingProgressStoring {
    var preferenceUserID: String? { nil }
    func complete(preferredThemeIDs: [String], visibleThemeIDs: Set<String>, initiallySelected: Set<String>, locale: String) {
        complete(preferredThemeIDs: preferredThemeIDs, locale: locale)
    }
}

final class OnboardingProgressStore: OnboardingProgressStoring {
    static let shared = OnboardingProgressStore(userIDProvider: {
        StoredBackendAccessTokenProvider().currentSession()?.userID
    })

    enum Keys {
        static let completedVersion = "quizice.onboarding.completedVersion"
        static let preferredThemeIDs = "quizice.onboarding.preferredThemeIDs"
        static let legacyPreferencesMigrationLocale = "quizice.onboarding.preferencesMigrationLocale"
        static let localizedPreferredThemeIDsPrefix = "quizice.onboarding.preferredThemeIDs."
        static let pendingThemePreferencesPrefix = "quizice.onboarding.themePreferencesPending."

        static func preferredThemeIDs(locale: String) -> String {
            localizedPreferredThemeIDsPrefix + locale
        }

        static func pendingThemePreferences(locale: String) -> String {
            pendingThemePreferencesPrefix + locale
        }
    }

    static let currentVersion = 1

    private let userDefaults: UserDefaults
    private let userIDProvider: () -> String?
    let favoritesStore: GlobalFavoritesStore

    init(userDefaults: UserDefaults = .standard, userIDProvider: @escaping () -> String? = { nil }) {
        self.userDefaults = userDefaults
        self.userIDProvider = userIDProvider
        favoritesStore = GlobalFavoritesStore(defaults: userDefaults)
    }

    var preferenceUserID: String? { userIDProvider() }

    var needsOnboarding: Bool {
        userDefaults.integer(forKey: Keys.completedVersion) < Self.currentVersion
    }

    var preferredThemeIDs: Set<String> {
        Set(orderedPreferredThemeIDs(locale: AppLocalizationStore.shared.resolvedLanguageCode))
    }

    func complete(preferredThemeIDs: Set<String>) {
        complete(
            preferredThemeIDs: preferredThemeIDs.sorted(),
            locale: AppLocalizationStore.shared.resolvedLanguageCode
        )
    }

    func orderedPreferredThemeIDs(locale: String) -> [String] {
        storedPreferredThemeIDs(locale: locale) ?? []
    }

    func storedPreferredThemeIDs(locale: String) -> [String]? {
        favoritesStore.favorites(for: userIDProvider())
    }

    func complete(preferredThemeIDs: [String], locale: String) {
        let previous = Set(orderedPreferredThemeIDs(locale: locale))
        complete(preferredThemeIDs: preferredThemeIDs,
                 visibleThemeIDs: previous.union(preferredThemeIDs), initiallySelected: previous, locale: locale)
    }

    func complete(preferredThemeIDs: [String], visibleThemeIDs: Set<String>, initiallySelected: Set<String>, locale: String) {
        favoritesStore.select(preferredThemeIDs, initiallySelected: initiallySelected,
                              visibleIDs: visibleThemeIDs, for: userIDProvider())
        userDefaults.set(Self.currentVersion, forKey: Keys.completedVersion)
    }

    func hasPendingThemePreferences(locale: String) -> Bool {
        favoritesStore.hasPending(for: userIDProvider())
    }

    /// Removes favorites for the deleted account in every language. Guest
    /// snapshots can contain copies claimed by that account, so erase those too.
    /// Onboarding completion, language, appearance and other accounts are kept.
    func eraseData(for userID: String) {
        favoritesStore.eraseData(for: userID)
        let suffix = ".user." + Data(userID.utf8).base64EncodedString()
        let preferencePrefixes = [
            Keys.localizedPreferredThemeIDsPrefix,
            Keys.pendingThemePreferencesPrefix,
            "quizice.preferences.revision.",
            "quizice.preferences.unclaimedGuest."
        ]
        for key in userDefaults.dictionaryRepresentation().keys {
            let isPreference = preferencePrefixes.contains { key.hasPrefix($0) }
            let isDeletedAccount = key.hasSuffix(suffix)
            let isGuest = !key.contains(".user.")
            if isPreference && (isDeletedAccount || isGuest) {
                userDefaults.removeObject(forKey: key)
            }
        }
        userDefaults.removeObject(forKey: Keys.preferredThemeIDs)
        userDefaults.removeObject(forKey: Keys.legacyPreferencesMigrationLocale)
    }

}
