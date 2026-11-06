import UIKit
import XCTest
@testable import Quizice

@MainActor
final class StatisticsHistoryStoreTests: XCTestCase {
    func testLoadsAllAccountHistoryAndRetriesAfterFailure() async throws {
        let api = HistoryAPIFake()
        let store = makeStore(api)
        store.start()
        await api.waitForRequests(1)
        api.finish(0, result: .failure(BackendContentError.transport(.notConnectedToInternet)))
        await settle()
        XCTAssertEqual(store.state, .failed)
        store.refresh()
        await api.waitForRequests(2)
        api.finish(1, result: .success(response()))
        await settle()
        guard case let .loaded(timeline) = store.state else { return XCTFail("Expected loaded history") }
        XCTAssertEqual(timeline.playedQuizzes, 2)
        XCTAssertEqual(timeline.undatedPlayedQuizzes, 53)
    }

    func testRapidPeriodChangeIgnoresLatePreviousPeriodResponse() async {
        let api = HistoryAPIFake()
        let store = makeStore(api)
        store.start()
        await api.waitForRequests(1)
        store.selectPeriod(.month)
        await api.waitForRequests(2)
        XCTAssertEqual(api.requests.map(\.period), [.week, .month])
        api.finish(1, result: .success(response(period: .month)))
        await settle()
        let current = store.state
        api.finish(0, result: .success(response()))
        await settle()
        XCTAssertEqual(store.state, current)
        XCTAssertEqual(store.period, .month)
    }

    func testAccountSwitchClearsOldDataAndIgnoresLateResponse() async {
        let api = HistoryAPIFake()
        let provider = ProgressSessionProvider()
        let center = NotificationCenter()
        let store = makeStore(api, provider: provider, center: center)
        store.start()
        await api.waitForRequests(1)
        provider.session = ProgressSessionProvider.session("B")
        center.post(name: .statisticsAccountHistoryDidChange, object: nil)
        await api.waitForRequests(2)
        XCTAssertEqual(store.state, .loading)
        XCTAssertEqual(api.requests.map(\.userID), ["A", "B"])
        api.finish(0, result: .success(response()))
        await settle()
        XCTAssertEqual(store.state, .loading)
        api.finish(1, result: .success(response(games: 3)))
        await settle()
        guard case let .loaded(timeline) = store.state else { return XCTFail("Expected B history") }
        XCTAssertEqual(timeline.playedQuizzes, 3)
    }

    func testSyncNotificationRefreshesOpenChartsButDoesNotFetchWhileClosed() async {
        let api = HistoryAPIFake()
        let center = NotificationCenter()
        let store = makeStore(api, center: center)
        store.start()
        await api.waitForRequests(1)
        api.finish(0, result: .success(response()))
        await settle()
        center.post(name: .statisticsAccountHistoryDidChange, object: nil)
        await api.waitForRequests(2)
        store.stop()
        api.finish(1, result: .success(response()))
        center.post(name: .statisticsAccountHistoryDidChange, object: nil)
        await settle()
        XCTAssertEqual(store.state, .idle)
        XCTAssertEqual(api.requests.count, 2)
        store.start()
        await api.waitForRequests(3)
        api.finish(2, result: .success(response()))
        await settle()
        guard case .loaded = store.state else { return XCTFail("Expected reload on reopen") }
    }

    func testForegroundUsesUpdatedTimeZoneAndAccountLossClearsLoadedCharts() async {
        let api = HistoryAPIFake()
        let provider = ProgressSessionProvider()
        let center = NotificationCenter()
        var zone = TimeZone(identifier: "Europe/Moscow")!
        let store = StatisticsHistoryStore(api: api, sessionProvider: provider, notificationCenter: center, timeZone: { zone })
        store.start()
        await api.waitForRequests(1)
        api.finish(0, result: .success(response()))
        await settle()
        zone = TimeZone(identifier: "America/New_York")!
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        await api.waitForRequests(2)
        XCTAssertEqual(api.requests.last?.timeZone, zone.identifier)
        provider.session = nil
        center.post(name: .statisticsAccountHistoryDidChange, object: nil)
        await settle()
        XCTAssertEqual(store.state, .failed)
        api.finish(1, result: .success(response()))
        await settle()
        XCTAssertEqual(store.state, .failed)
    }

    func testGuestAndInvalidContractNeverExposeCharts() async {
        let api = HistoryAPIFake()
        let provider = ProgressSessionProvider()
        provider.session = nil
        let store = makeStore(api, provider: provider)
        store.start()
        XCTAssertEqual(store.state, .failed)
        XCTAssertTrue(api.requests.isEmpty)
        provider.session = ProgressSessionProvider.session("A")
        store.refresh()
        await api.waitForRequests(1)
        api.finish(0, result: .success(response(period: .month)))
        await settle()
        XCTAssertEqual(store.state, .failed)
    }

    private func makeStore(_ api: HistoryAPIFake, provider: ProgressSessionProvider = ProgressSessionProvider(), center: NotificationCenter = NotificationCenter()) -> StatisticsHistoryStore {
        StatisticsHistoryStore(api: api, sessionProvider: provider, notificationCenter: center,
                               timeZone: { TimeZone(identifier: "Europe/Moscow")! })
    }
    private func response(period: StatisticsPeriod = .week, games: Int = 2) -> StatisticsHistoryResponse {
        .init(period: period, timeZone: "Europe/Moscow", periodStart: period == .month ? "2026-10-08" : "2026-10-31",
              periodEnd: "2026-11-07", days: [.init(date: "2026-11-01", playedQuizzes: games, correctAnswers: 5, totalQuestions: 20)],
              undatedPlayedQuizzes: 53)
    }
    private func settle() async { for _ in 0..<30 { await Task.yield() } }
}

@MainActor
private final class HistoryAPIFake: StatisticsHistoryAPI {
    struct Request { let period: StatisticsPeriod; let userID: String; let timeZone: String }
    var requests: [Request] = []
    private var continuations: [Int: CheckedContinuation<StatisticsHistoryResponse, Error>] = [:]
    func fetchStatisticsHistory(period: StatisticsPeriod, timeZone: TimeZone, session: AuthSession) async throws -> StatisticsHistoryResponse {
        let index = requests.count
        requests.append(.init(period: period, userID: session.userID, timeZone: timeZone.identifier))
        return try await withCheckedThrowingContinuation { continuations[index] = $0 }
    }
    func finish(_ index: Int, result: Result<StatisticsHistoryResponse, Error>) { continuations.removeValue(forKey: index)?.resume(with: result) }
    func waitForRequests(_ count: Int) async {
        for _ in 0..<100 where requests.count < count { await Task.yield() }
        XCTAssertEqual(requests.count, count)
    }
}
