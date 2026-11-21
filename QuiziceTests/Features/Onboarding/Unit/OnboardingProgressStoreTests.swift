import XCTest
@testable import Quizice

final class OnboardingProgressStoreTests: XCTestCase {
    func testFreshStoreRequiresOnboarding() {
        withStore { store, _ in
            XCTAssertTrue(store.needsOnboarding)
            XCTAssertNil(store.storedPreferredThemeIDs(locale: "ru"))
        }
    }

    func testCompletionPersistsOneGlobalSelectionAcrossLanguagesAndRestart() {
        withStore { store, defaults in
            store.complete(preferredThemeIDs: ["technology", "music"], locale: "ru")
            let reopened = OnboardingProgressStore(userDefaults: defaults)
            XCTAssertFalse(reopened.needsOnboarding)
            XCTAssertEqual(reopened.orderedPreferredThemeIDs(locale: "en"), ["technology", "music"])
            XCTAssertTrue(reopened.hasPendingThemePreferences(locale: "en"))
        }
    }

    func testLegacyMigrationUnionsOwnedLocalesButUploadsOnlyPendingChoicesOnce() throws {
        try withStore { _, defaults in
            let suffix = ".user." + Data("A".utf8).base64EncodedString()
            defaults.set(["music"], forKey: OnboardingProgressStore.Keys.preferredThemeIDs(locale: "ru") + suffix)
            defaults.set(["space"], forKey: OnboardingProgressStore.Keys.preferredThemeIDs(locale: "en") + suffix)
            defaults.set(true, forKey: OnboardingProgressStore.Keys.pendingThemePreferences(locale: "en") + suffix)
            defaults.set(["unowned"], forKey: OnboardingProgressStore.Keys.preferredThemeIDs(locale: "fr"))
            let store = GlobalFavoritesStore(defaults: defaults)
            XCTAssertEqual(Set(store.favorites(for: "A") ?? []), ["music", "space"])
            let mutation = try XCTUnwrap(store.nextMutation(for: "A"))
            XCTAssertEqual(mutation.addThemeIds, ["space"])
            XCTAssertEqual(mutation.removeThemeIds, [])
            let reopened = GlobalFavoritesStore(defaults: defaults)
            XCTAssertEqual(reopened.nextMutation(for: "A"), mutation)
            reopened.apply(.init(favoriteThemeIds: ["space"], revision: 4), for: "A", acknowledging: mutation.mutationId)
            XCTAssertNil(GlobalFavoritesStore(defaults: defaults).nextMutation(for: "A"))
            XCTAssertNil(store.favorites(for: "B"))
        }
    }

    func testNewGuestChoiceIsClaimedOnceByAddingToExistingAccount() {
        withStore { _, defaults in
            var userID: String? = "A"
            let store = OnboardingProgressStore(userDefaults: defaults, userIDProvider: { userID })
            store.favoritesStore.apply(.init(favoriteThemeIds: ["technology"], revision: 1), for: "A")
            userID = nil
            store.complete(preferredThemeIDs: ["music"], locale: "ru")
            userID = "A"
            XCTAssertEqual(store.orderedPreferredThemeIDs(locale: "en"), ["technology", "music"])
            XCTAssertEqual(store.favoritesStore.nextMutation(for: "A")?.removeThemeIds, [])
            userID = "B"
            XCTAssertNil(store.storedPreferredThemeIDs(locale: "ru"))
        }
    }

    func testUnownedLegacyGuestChoiceIsNeverUploaded() {
        withStore { _, defaults in
            defaults.set(["music"], forKey: OnboardingProgressStore.Keys.preferredThemeIDs(locale: "ru"))
            defaults.set(true, forKey: "quizice.preferences.unclaimedGuest.ru")
            let store = GlobalFavoritesStore(defaults: defaults)
            XCTAssertEqual(store.favorites(for: nil), ["music"])
            XCTAssertNil(store.favorites(for: "A"))
            XCTAssertNil(store.nextMutation(for: "A"))
            let reopened = GlobalFavoritesStore(defaults: defaults)
            XCTAssertEqual(reopened.favorites(for: nil), ["music"])
            XCTAssertNil(reopened.nextMutation(for: "A"))
        }
    }

    func testEditorPreservesHiddenThemesAndRemoteChangesItDidNotEdit() {
        withStore { _, defaults in
            let store = GlobalFavoritesStore(defaults: defaults)
            store.apply(.init(favoriteThemeIds: ["hidden", "music"], revision: 1), for: "A")
            // A remote favorite arrives after the editor opened with only music selected.
            store.apply(.init(favoriteThemeIds: ["hidden", "music", "space"], revision: 2), for: "A")
            store.select([], initiallySelected: ["music"], visibleIDs: ["music", "space"], for: "A")
            XCTAssertEqual(store.favorites(for: "A"), ["hidden", "space"])
            XCTAssertEqual(store.nextMutation(for: "A")?.removeThemeIds, ["music"])
        }
    }

    func testOldAcknowledgementNeverRollsBackNewerSnapshotOrNewPendingEdits() throws {
        try withStore { _, defaults in
            let store = GlobalFavoritesStore(defaults: defaults)
            store.select(["music"], initiallySelected: [], visibleIDs: ["music"], for: "A")
            let first = try XCTUnwrap(store.nextMutation(for: "A"))
            store.select(["space"], initiallySelected: [], visibleIDs: ["space"], for: "A")
            store.apply(.init(favoriteThemeIds: ["music", "remote"], revision: 5), for: "A")
            store.apply(.init(favoriteThemeIds: ["music"], revision: 3), for: "A", acknowledging: first.mutationId)
            XCTAssertEqual(store.favorites(for: "A"), ["music", "remote", "space"])
            XCTAssertEqual(store.nextMutation(for: "A")?.addThemeIds, ["space"])
        }
    }

    func testDeletingAccountPreventsLateResponsesAndLegacyRemigration() {
        withStore { _, defaults in
            let store = GlobalFavoritesStore(defaults: defaults)
            store.select(["music"], initiallySelected: [], visibleIDs: ["music"], for: "A")
            store.select(["space"], initiallySelected: [], visibleIDs: ["space"], for: "B")
            store.eraseData(for: "A")
            store.apply(.init(favoriteThemeIds: ["music"], revision: 2), for: "A")
            XCTAssertNil(GlobalFavoritesStore(defaults: defaults).favorites(for: "A"))
            XCTAssertNil(store.nextMutation(for: "A"))
            XCTAssertEqual(store.favorites(for: "B"), ["space"])
        }
    }

    func testInvalidThemeIsIsolatedWithoutDroppingHealthyMutations() throws {
        try withStore { _, defaults in
            let store = GlobalFavoritesStore(defaults: defaults)
            store.select(["retired", "music"], initiallySelected: [], visibleIDs: ["retired", "music"], for: "A")
            let batch = try XCTUnwrap(store.nextMutation(for: "A"))
            store.reject(batch, for: "A", isolateInvalidThemes: true)
            let rejected = try XCTUnwrap(store.nextMutation(for: "A"))
            XCTAssertNotEqual(batch.mutationId, rejected.mutationId)
            store.reject(rejected, for: "A", isolateInvalidThemes: true)
            XCTAssertEqual(store.nextMutation(for: "A")?.addThemeIds, ["music"])
            XCTAssertEqual(store.favorites(for: "A"), ["music"])
        }
    }

    private func withStore(_ operation: (OnboardingProgressStore, UserDefaults) throws -> Void) rethrows {
        let suite = "OnboardingProgressStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try operation(OnboardingProgressStore(userDefaults: defaults), defaults)
    }
}
