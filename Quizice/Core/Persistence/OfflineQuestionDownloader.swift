import Foundation

final class OfflineQuestionDownloader {
    private let api: BackendContentAPI?
    private let cache: OfflineQuestionCache
    private let accessTokenProvider: BackendAccessTokenProviding
    private let outbox: QuestionAnswerOutboxing
    @MainActor private var task: Task<Void, Never>?
    @MainActor private var requestID: UUID?
    @MainActor private var scope: String?

    init(api: BackendContentAPI?, cache: OfflineQuestionCache,
         accessTokenProvider: BackendAccessTokenProviding, outbox: QuestionAnswerOutboxing) {
        self.api = api
        self.cache = cache
        self.accessTokenProvider = accessTokenProvider
        self.outbox = outbox
    }

    @MainActor
    func start(locale: String) {
        guard !outbox.isNetworkUnavailable, let api, let session = accessTokenProvider.currentSession(),
              session.expiresAt > Date(), accessTokenProvider.validAccessToken() != nil else { return }
        let nextScope = session.userID + ":" + locale
        if task != nil, scope == nextScope { return }
        cancel()
        let id = UUID()
        requestID = id
        scope = nextScope
        task = Task { [weak self] in
            guard let self else { return }
            defer { if requestID == id { task = nil } }
            guard await cache.needsDownload(locale: locale, userID: session.userID) else { return }
            do {
                let generation = cache.generation(for: session.userID)
                try await outbox.synchronizeBeforeFetchingQuestions(for: session.userID)
                try checkCurrent(id: id, locale: locale, userID: session.userID)
                let pack = try await api.fetchOfflineQuestions(locale: locale, userID: session.userID)
                try checkCurrent(id: id, locale: locale, userID: session.userID)
                try await cache.install(pack, expectedGeneration: generation)
                AppLog.content.notice("Offline question pack saved: locale=\(locale, privacy: .public) count=\(pack.questions.count)")
            } catch {
                AppLog.content.notice("Offline question download deferred")
            }
        }
    }

    @MainActor
    func cancel() { task?.cancel(); task = nil; requestID = nil; scope = nil }

    @MainActor
    private func checkCurrent(id: UUID, locale: String, userID: String) throws {
        try Task.checkCancellation()
        guard requestID == id, accessTokenProvider.currentSession()?.userID == userID,
              AppLocalizationStore.shared.resolvedLanguageCode == locale else { throw CancellationError() }
    }

    @MainActor
    func makeQuiz(metadata: QuizTheme, themeIDs: Set<String>, userID: String,
                                 questionCount: Int, difficulty: AIQuizDifficulty, locale: String,
                                 strategy: QuestionRepeatStrategy, selectedCountry: String?, country: String?,
                                 balanced: Bool = false, countryProvider: () -> String?) async throws -> QuizTheme {
        func validate() throws {
            try Task.checkCancellation()
            guard AppLocalizationStore.shared.resolvedLanguageCode == locale,
                  countryProvider() == selectedCountry else { throw CancellationError() }
            guard let session = accessTokenProvider.currentSession(), session.userID == userID,
                  session.expiresAt > Date() else { throw BackendContentError.unauthenticated }
        }
        try validate()
        let questions = try await cache.questions(locale: locale, userID: userID, themeIDs: themeIDs,
            count: questionCount, difficulty: difficulty, strategy: strategy, country: country, balanced: balanced)
        try validate()
        AppLog.content.notice("Using offline questions: locale=\(locale, privacy: .public) count=\(questions.count)")
        return QuizTheme(id: metadata.id, theme: metadata.theme, themeDescription: metadata.themeDescription,
            questions: questions, sfSymbolName: metadata.sfSymbolName, emoji: metadata.emoji,
            colorHex: metadata.colorHex, isFavorite: metadata.isFavorite, source: .catalog,
            questionOrigin: .backend, difficulty: difficulty, countries: metadata.countries)
    }

    static func permitsFallback(_ error: Error) -> Bool {
        switch error {
        case BackendContentError.transport(let code), BackendAPIError.transport(let code):
            return permitsFallback(URLError(code))
        case let error as URLError:
            return [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
                    .cannotFindHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff].contains(error.code)
        case BackendContentError.timedOut: return true
        case BackendContentError.httpStatus(let status, _), BackendAPIError.httpStatus(let status, _):
            return (500...599).contains(status)
        default: return false
        }
    }
}
