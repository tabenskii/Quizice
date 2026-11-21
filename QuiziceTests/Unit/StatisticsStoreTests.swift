import XCTest
@testable import Quizice

final class StatisticsStoreTests: XCTestCase {
    private var suiteNames: [String] = []

    override func tearDown() {
        for suiteName in suiteNames {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        suiteNames.removeAll()
        super.tearDown()
    }

    func testFirstRunLoadSummaryReturnsEmpty() {
        let harness = makeHarness()

        XCTAssertEqual(harness.store.loadSummary(), .empty)
        XCTAssertNil(harness.defaults.data(forKey: harness.key))
    }

    func testRecordAttemptPersistsValidAttempts() {
        let harness = makeHarness()

        harness.store.recordAttempt(correctAnswers: 3, totalQuestions: 5)
        harness.store.recordAttempt(correctAnswers: 4, totalQuestions: 4)

        let summary = harness.store.loadSummary()
        XCTAssertEqual(summary.playedQuizzes, 2)
        XCTAssertEqual(summary.correctAnswers, 7)
        XCTAssertEqual(summary.totalQuestions, 9)
        XCTAssertEqual(summary.percentage, 78)
        XCTAssertEqual(summary.bestCorrectAnswers, 4)
        XCTAssertEqual(summary.bestTotalQuestions, 4)
        XCTAssertNotNil(harness.defaults.data(forKey: harness.key))
    }

    func testRecordAttemptIgnoresNonPositiveTotals() {
        let harness = makeHarness()

        harness.store.recordAttempt(correctAnswers: 2, totalQuestions: 0)
        harness.store.recordAttempt(correctAnswers: 2, totalQuestions: -3)

        XCTAssertEqual(harness.store.loadSummary(), .empty)
        XCTAssertNil(harness.defaults.data(forKey: harness.key))
    }

    func testRecordAttemptSanitizesCorrectAnswersOutsideValidRange() {
        let harness = makeHarness()

        harness.store.recordAttempt(correctAnswers: -2, totalQuestions: 5)
        harness.store.recordAttempt(correctAnswers: 8, totalQuestions: 5)

        let summary = harness.store.loadSummary()
        XCTAssertEqual(summary.playedQuizzes, 2)
        XCTAssertEqual(summary.correctAnswers, 5)
        XCTAssertEqual(summary.totalQuestions, 10)
        XCTAssertEqual(summary.percentage, 50)
        XCTAssertEqual(summary.bestCorrectAnswers, 5)
        XCTAssertEqual(summary.bestTotalQuestions, 5)
    }

    func testLoadSummaryReturnsEmptyForCorruptPersistedBytesAndRemovesKey() {
        let harness = makeHarness()
        harness.defaults.set(Data("not-json".utf8), forKey: harness.key)

        XCTAssertEqual(harness.store.loadSummary(), .empty)
        XCTAssertNil(harness.defaults.data(forKey: harness.key))
    }

    func testLoadSummaryReturnsEmptyAndRemovesKeyForMalformedAttemptPayload() throws {
        let harness = makeHarness()
        let malformed = [["correctAnswers": 1]]
        let data = try JSONSerialization.data(withJSONObject: malformed)
        harness.defaults.set(data, forKey: harness.key)

        XCTAssertEqual(harness.store.loadSummary(), .empty)
        XCTAssertNil(harness.defaults.data(forKey: harness.key))
    }

    func testLegacyAttemptArrayMigratesToBoundedAggregate() throws {
        let harness = makeHarness()
        let legacyAttempts = [
            StatisticsStore.Attempt(correctAnswers: 2, totalQuestions: 5),
            StatisticsStore.Attempt(correctAnswers: 4, totalQuestions: 4)
        ]
        harness.defaults.set(try JSONEncoder().encode(legacyAttempts), forKey: harness.key)

        XCTAssertEqual(
            harness.store.loadSummary(),
            StatisticsSummary(
                playedQuizzes: 2,
                correctAnswers: 6,
                totalQuestions: 9,
                bestCorrectAnswers: 4,
                bestTotalQuestions: 4
            )
        )

        let migratedData = try XCTUnwrap(harness.defaults.data(forKey: harness.key))
        XCTAssertThrowsError(try JSONDecoder().decode([StatisticsStore.Attempt].self, from: migratedData))
    }

    func testPreviousAggregateMigratesIntoIdempotentLegacySyncPayload() throws {
        let harness = makeHarness()
        let legacyJSON: [String: Int] = [
            "playedQuizzes": 3,
            "correctAnswers": 9,
            "totalQuestions": 15,
            "bestCorrectAnswers": 4,
            "bestTotalQuestions": 5
        ]
        harness.defaults.set(
            try JSONSerialization.data(withJSONObject: legacyJSON),
            forKey: harness.key
        )

        XCTAssertEqual(harness.store.loadSummary().playedQuizzes, 3)
        harness.store.activateAuthenticatedUser("user-1")
        let request = harness.store.makeSyncRequest(for: "user-1")
        let reloaded = StatisticsStore(userDefaults: harness.defaults, key: harness.key)

        XCTAssertEqual(request.legacySummary?.correctAnswers, 9)
        XCTAssertEqual(reloaded.makeSyncRequest(for: "user-1").migrationId, request.migrationId)
    }

    func testPendingAttemptKeepsStableIdentityAcrossStoreReload() {
        let harness = makeHarness()
        harness.store.recordAttempt(correctAnswers: 3, totalQuestions: 5)
        harness.store.activateAuthenticatedUser("user-1")

        let firstRequest = harness.store.makeSyncRequest(for: "user-1")
        let reloadedStore = StatisticsStore(userDefaults: harness.defaults, key: harness.key)
        let secondRequest = reloadedStore.makeSyncRequest(for: "user-1")

        XCTAssertEqual(firstRequest, secondRequest)
        XCTAssertEqual(firstRequest.attempts.count, 1)
    }

    func testGuestAttemptsMoveOnlyToSelectedAuthenticatedUser() {
        let harness = makeHarness()
        harness.store.recordAttempt(correctAnswers: 4, totalQuestions: 5)

        harness.store.activateAuthenticatedUser("user-a")
        XCTAssertEqual(harness.store.loadSummary().correctAnswers, 4)

        harness.store.activateGuest()
        XCTAssertEqual(harness.store.loadSummary(), .empty)
        harness.store.recordAttempt(correctAnswers: 1, totalQuestions: 5)
        harness.store.activateAuthenticatedUser("user-b")
        XCTAssertEqual(harness.store.loadSummary().correctAnswers, 1)

        harness.store.activateAuthenticatedUser("user-a")
        XCTAssertEqual(harness.store.loadSummary().correctAnswers, 4)
    }

    func testDeletingAccountErasesItsHistoryAndRecoveryBytesButKeepsOtherAccountsAndSettings() {
        let harness = makeHarness()
        harness.store.activateAuthenticatedUser("user-a")
        harness.store.recordAttempt(correctAnswers: 4, totalQuestions: 5)
        let deletedKey = harness.defaults.dictionaryRepresentation().keys.first {
            $0.hasPrefix(harness.key + ".user.")
        }!
        harness.defaults.set(Data("old damaged history".utf8), forKey: deletedKey + ".corrupt")
        harness.store.activateAuthenticatedUser("user-b")
        harness.store.recordAttempt(correctAnswers: 2, totalQuestions: 5)
        harness.defaults.set("ru", forKey: "language-setting")
        harness.store.activateAuthenticatedUser("user-a")

        harness.store.eraseData(for: "user-a")

        XCTAssertNil(harness.store.activeUserID)
        XCTAssertEqual(harness.store.loadSummary(), .empty)
        XCTAssertNil(harness.defaults.object(forKey: deletedKey))
        XCTAssertNil(harness.defaults.object(forKey: deletedKey + ".corrupt"))
        XCTAssertFalse(harness.store.hasPendingSync(for: "user-a"))
        let reopened = StatisticsStore(userDefaults: harness.defaults, key: harness.key)
        reopened.activateAuthenticatedUser("user-b")
        XCTAssertEqual(reopened.loadSummary().correctAnswers, 2)
        XCTAssertEqual(harness.defaults.string(forKey: "language-setting"), "ru")
    }

    func testDeletedAccountCannotBeRestoredByLateResultFromAnotherStoreInstance() {
        let harness = makeHarness()
        let oldPresenterStore = StatisticsStore(userDefaults: harness.defaults, key: harness.key)
        harness.store.activateAuthenticatedUser("deleted-user")
        harness.store.recordAttempt(correctAnswers: 4, totalQuestions: 5)
        let oldRequest = oldPresenterStore.makeSyncRequest(for: "deleted-user")

        harness.store.eraseData(for: "deleted-user")
        oldPresenterStore.recordAttempt(correctAnswers: 5, totalQuestions: 5,
                                        accessibilityMode: false, for: "deleted-user")
        oldPresenterStore.applySyncResponse(.init(
            summary: StatisticsStore.summary(from: [.init(correctAnswers: 4, totalQuestions: 5)]),
            acceptedAttemptIds: oldRequest.attempts.map(\.id), legacySummaryAccepted: true),
            for: "deleted-user")
        oldPresenterStore.activateAuthenticatedUser("deleted-user")

        XCTAssertNil(oldPresenterStore.activeUserID)
        XCTAssertEqual(oldPresenterStore.loadSummary(), .empty)
        XCTAssertFalse(oldPresenterStore.hasPendingSync(for: "deleted-user"))
        XCTAssertTrue(oldPresenterStore.makeSyncRequest(for: "deleted-user").attempts.isEmpty)
        let reopened = StatisticsStore(userDefaults: harness.defaults, key: harness.key)
        reopened.activateAuthenticatedUser("new-user")
        reopened.recordAttempt(correctAnswers: 2, totalQuestions: 5)
        XCTAssertEqual(reopened.loadSummary().correctAnswers, 2)
    }

    func testApplyingSyncResponseKeepsOnlyUnacknowledgedAttemptsPending() {
        let harness = makeHarness()
        harness.store.recordAttempt(correctAnswers: 4, totalQuestions: 5)
        harness.store.recordAttempt(correctAnswers: 2, totalQuestions: 5)
        harness.store.activateAuthenticatedUser("user-1")
        let request = harness.store.makeSyncRequest(for: "user-1")

        harness.store.applySyncResponse(
            StatisticsStore.SyncResponse(
                summary: StatisticsSummary(
                    playedQuizzes: 1,
                    correctAnswers: 4,
                    totalQuestions: 5,
                    bestCorrectAnswers: 4,
                    bestTotalQuestions: 5
                ),
                acceptedAttemptIds: [request.attempts[0].id],
                legacySummaryAccepted: true
            ),
            for: "user-1"
        )

        let remaining = harness.store.makeSyncRequest(for: "user-1")
        XCTAssertEqual(remaining.attempts.map(\.id), [request.attempts[1].id])
        XCTAssertEqual(harness.store.loadSummary().playedQuizzes, 2)
        XCTAssertEqual(harness.store.loadSummary().correctAnswers, 6)
    }

    func testRejectedLegacySummaryIsTerminalAndDoesNotRemainPending() throws {
        let harness = makeHarness()
        let legacyJSON: [String: Int] = [
            "playedQuizzes": 3,
            "correctAnswers": 9,
            "totalQuestions": 15,
            "bestCorrectAnswers": 4,
            "bestTotalQuestions": 5
        ]
        harness.defaults.set(
            try JSONSerialization.data(withJSONObject: legacyJSON),
            forKey: harness.key
        )
        _ = harness.store.loadSummary()
        harness.store.activateAuthenticatedUser("user-1")
        XCTAssertNotNil(harness.store.makeSyncRequest(for: "user-1").legacySummary)

        harness.store.applySyncResponse(
            StatisticsStore.SyncResponse(
                summary: .empty,
                acceptedAttemptIds: [],
                legacySummaryAccepted: false
            ),
            for: "user-1"
        )

        XCTAssertNil(harness.store.makeSyncRequest(for: "user-1").legacySummary)
        XCTAssertFalse(harness.store.hasPendingSync(for: "user-1"))
        XCTAssertEqual(harness.store.loadSummary(), .empty)
    }

    func testRecordAttemptPreservesAccessibilityModeInSyncPayload() throws {
        let harness = makeHarness()
        harness.store.recordAttempt(correctAnswers: 5, totalQuestions: 5, accessibilityMode: true)
        harness.store.recordAttempt(correctAnswers: 2, totalQuestions: 5, accessibilityMode: false)
        harness.store.activateAuthenticatedUser("user-a11y")

        let request = harness.store.makeSyncRequest(for: "user-a11y")
        let modes = request.attempts.map(\.accessibilityMode)
        XCTAssertEqual(modes, [true, false])
    }

    func testDecodingLegacyPendingAttemptWithoutAccessibilityFlagDefaultsToFalse() throws {
        let harness = makeHarness()
        // Simulate a PendingAttempt persisted before the accessibilityMode field
        // existed — must round-trip cleanly so we don't silently drop sync work
        // for users upgrading from a prior build.
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let legacyState: [String: Any] = [
            "baseline": [
                "playedQuizzes": 0,
                "correctAnswers": 0,
                "totalQuestions": 0,
                "bestCorrectAnswers": 0,
                "bestTotalQuestions": 0
            ],
            "pendingAttempts": [[
                "id": "legacy-attempt-1",
                "correctAnswers": 3,
                "totalQuestions": 5,
                "completedAt": referenceDate.timeIntervalSinceReferenceDate
                // no accessibilityMode field
            ]],
            "migrationId": "legacy-migration"
        ]
        let userSuffix = Data("user-legacy".utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        let userKey = "\(harness.key).user.\(userSuffix)"
        harness.defaults.set(
            try JSONSerialization.data(withJSONObject: legacyState),
            forKey: userKey
        )

        let request = harness.store.makeSyncRequest(for: "user-legacy")
        XCTAssertEqual(request.attempts.count, 1)
        XCTAssertEqual(request.attempts.first?.accessibilityMode, false)
        XCTAssertEqual(request.attempts.first?.correctAnswers, 3)
    }

    func testUnsupportedAttemptsStayLocalWithoutBlockingValidUploads() {
        let harness = makeHarness()
        harness.store.recordAttempt(correctAnswers: 3, totalQuestions: 3)
        harness.store.recordAttempt(correctAnswers: 4, totalQuestions: 5)
        harness.store.activateAuthenticatedUser("A")
        let request = harness.store.makeSyncRequest(for: "A")
        XCTAssertEqual(request.attempts.map(\.totalQuestions), [5])
        harness.store.applySyncResponse(.init(
            summary: .init(playedQuizzes: 1, correctAnswers: 4, totalQuestions: 5, bestCorrectAnswers: 4, bestTotalQuestions: 5),
            acceptedAttemptIds: request.attempts.map(\.id), legacySummaryAccepted: false), for: "A")
        let restored = StatisticsStore(userDefaults: harness.defaults, key: harness.key)
        XCTAssertFalse(restored.hasPendingSync(for: "A"))
        XCTAssertEqual(restored.loadSummary().playedQuizzes, 2)
        XCTAssertEqual(restored.loadSummary().totalQuestions, 8)
    }

    func testEmptySyncKeepsMigrationIDAcrossRestart() {
        let harness = makeHarness()
        let first = harness.store.makeSyncRequest(for: "A")
        let restored = StatisticsStore(userDefaults: harness.defaults, key: harness.key)
        XCTAssertEqual(restored.makeSyncRequest(for: "A"), first)
    }

    func testServerBestWinsTiesAgainstPendingResults() {
        let harness = makeHarness()
        harness.store.activateAuthenticatedUser("A")
        harness.store.applySyncResponse(.init(
            summary: .init(playedQuizzes: 1, correctAnswers: 5, totalQuestions: 10, bestCorrectAnswers: 5, bestTotalQuestions: 10),
            acceptedAttemptIds: [], legacySummaryAccepted: false), for: "A")
        harness.store.recordAttempt(correctAnswers: 5, totalQuestions: 5)
        XCTAssertEqual(harness.store.loadSummary().bestTotalQuestions, 10)
        harness.store.recordAttempt(correctAnswers: 8, totalQuestions: 15)
        XCTAssertEqual(harness.store.loadSummary().bestCorrectAnswers, 8)
        XCTAssertEqual(harness.store.loadSummary().bestTotalQuestions, 15)
    }

    private func makeHarness(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> (store: StatisticsStore, defaults: UserDefaults, key: String) {
        let suiteName = "ru.avtabenskiy.QuiziceTests.StatisticsStoreTests.\(UUID().uuidString)"
        suiteNames.append(suiteName)
        UserDefaults.standard.removePersistentDomain(forName: suiteName)

        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected isolated UserDefaults suite to be created", file: file, line: line)
            let fallback = UserDefaults.standard
            let key = "statistics-test-\(UUID().uuidString)"
            return (StatisticsStore(userDefaults: fallback, key: key), fallback, key)
        }

        let key = "statistics-test-\(UUID().uuidString)"
        return (StatisticsStore(userDefaults: defaults, key: key), defaults, key)
    }
}

extension StatisticsStoreTests {
    func testRemoteSummaryNotifiesObserversAfterPersistingVisibleAccountData() {
        let suite = "StatisticsStoreTests.notifications.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = NotificationCenter()
        let store = StatisticsStore(userDefaults: defaults, notificationCenter: center)
        store.activateAuthenticatedUser("A")
        let summary = StatisticsSummary(playedQuizzes: 1, correctAnswers: 4, totalQuestions: 5,
                                        bestCorrectAnswers: 4, bestTotalQuestions: 5)
        var observed: [StatisticsSummary] = []
        let observer = center.addObserver(forName: .statisticsDidChange, object: nil, queue: nil) { _ in
            observed.append(store.loadSummary())
        }
        defer { center.removeObserver(observer) }
        let response = StatisticsStore.SyncResponse(summary: summary, acceptedAttemptIds: [], legacySummaryAccepted: false)
        store.applySyncResponse(response, for: "A")
        store.applySyncResponse(response, for: "A")
        XCTAssertEqual(observed, [summary])
        store.activateGuest()
        XCTAssertEqual(observed.last, .empty)
    }
}
