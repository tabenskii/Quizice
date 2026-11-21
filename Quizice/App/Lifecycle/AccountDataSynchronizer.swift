import Foundation

/// Coalesces lifecycle and screen refreshes; each repository retains its own
/// account/cancellation guards before applying a response.
@MainActor
final class AccountDataSynchronizer {
    private let statistics: @MainActor () async -> Void
    private let answers: @MainActor () async -> Void
    private let favorites: @MainActor () async -> Void
    private var task: Task<Void, Never>?
    private var requestID: UUID?
    private var needsAnotherPass = false

    init(statistics: @escaping @MainActor () async -> Void, answers: @escaping @MainActor () async -> Void,
         favorites: @escaping @MainActor () async -> Void) {
        self.statistics = statistics
        self.answers = answers
        self.favorites = favorites
    }

    convenience init(
        accountManager: AccountManaging?, answerOutbox: QuestionAnswerOutboxing,
        themeRepository: ThemeRepository, favoritesDidRefresh: @escaping @MainActor () -> Void
    ) {
        self.init(
            statistics: { [weak accountManager] in
                await (accountManager as? AccountSynchronizing)?.synchronizeAccountData()
            },
            answers: { await answerOutbox.synchronize() },
            favorites: {
                let locale = AppLocalizationStore.shared.resolvedLanguageCode
                let refreshed = await themeRepository.synchronizeThemePreferences(locale: locale)
                guard !Task.isCancelled else { return }
                if refreshed { favoritesDidRefresh() }
            }
        )
    }

    func refresh(requiringNewPass: Bool = false) async {
        if let task {
            if requiringNewPass { needsAnotherPass = true }
            await task.value
            return
        }
        let id = UUID()
        requestID = id
        let task = Task {
            repeat {
                guard requestID == id, !Task.isCancelled else { return }
                needsAnotherPass = false
                // Authentication recovery must finish before account-owned requests.
                await statistics()
                guard !Task.isCancelled else { return }
                async let answersResult: Void = answers()
                async let favoritesResult: Void = favorites()
                _ = await (answersResult, favoritesResult)
            } while requestID == id && needsAnotherPass && !Task.isCancelled
        }
        self.task = task
        await task.value
        if requestID == id { self.task = nil; requestID = nil }
    }

    func cancel() {
        task?.cancel()
        task = nil
        requestID = nil
    }
}
