import Foundation
import UIKit

protocol StatisticsHistoryAPI {
    func fetchStatisticsHistory(period: StatisticsPeriod, timeZone: TimeZone, session: AuthSession) async throws -> StatisticsHistoryResponse
}

@MainActor
final class StatisticsHistoryStore {
    enum State: Equatable {
        case idle
        case loading
        case loaded(StatisticsTimeline)
        case failed
    }

    private let api: StatisticsHistoryAPI?
    private let sessionProvider: BackendAccessTokenProviding
    private let notificationCenter: NotificationCenter
    private let timeZone: () -> TimeZone
    private var observers: [NSObjectProtocol] = []
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var isActive = false
    private(set) var period = StatisticsPeriod.week
    private(set) var state = State.idle {
        didSet { onChange?() }
    }
    var onChange: (() -> Void)?

    static func live() -> StatisticsHistoryStore {
        let provider = StoredBackendAccessTokenProvider()
        let api = BackendConfiguration.load().map {
            HTTPBackendContentAPI(configuration: $0, metrics: AppMetricaAnalyticsTracker.shared,
                                  accessTokenProvider: provider,
                                  authenticationRecoverer: NotificationBackendAuthenticationRecoverer())
        }
        return StatisticsHistoryStore(api: api, sessionProvider: provider)
    }

    init(api: StatisticsHistoryAPI?, sessionProvider: BackendAccessTokenProviding,
         notificationCenter: NotificationCenter = .default, timeZone: @escaping () -> TimeZone = { .current }) {
        self.api = api
        self.sessionProvider = sessionProvider
        self.notificationCenter = notificationCenter
        self.timeZone = timeZone
        for name in [Notification.Name.statisticsAccountHistoryDidChange, .NSSystemTimeZoneDidChange, UIApplication.didBecomeActiveNotification] {
            observers.append(notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            })
        }
    }

    deinit {
        task?.cancel()
        observers.forEach(notificationCenter.removeObserver)
    }

    func start() {
        isActive = true
        refresh()
    }

    func stop() {
        isActive = false
        task?.cancel()
        generation = UUID()
        state = .idle
    }

    func selectPeriod(_ period: StatisticsPeriod) {
        guard self.period != period else { return }
        self.period = period
        refresh()
    }

    func refresh() {
        task?.cancel()
        let requestID = UUID()
        generation = requestID
        guard isActive else { state = .idle; return }
        guard let api, let session = sessionProvider.currentSession() else { state = .failed; return }
        let requestedPeriod = period
        let requestedTimeZone = timeZone()
        state = .loading
        task = Task { [weak self] in
            do {
                let response = try await api.fetchStatisticsHistory(period: requestedPeriod, timeZone: requestedTimeZone, session: session)
                let timeline = try response.timeline(requestedPeriod: requestedPeriod, timeZone: requestedTimeZone)
                guard let self, !Task.isCancelled, self.generation == requestID,
                      self.sessionProvider.currentSession()?.userID == session.userID else { return }
                self.state = .loaded(timeline)
            } catch {
                guard let self, !Task.isCancelled, self.generation == requestID,
                      self.sessionProvider.currentSession()?.userID == session.userID else { return }
                self.state = .failed
            }
        }
    }
}
