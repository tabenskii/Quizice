import CryptoKit
import Foundation
import SwiftData

final class ThemeCatalogRepository: ThemeRepository {
    enum Content {
        static let dataResourceName = "data"
        static let dataResourceExtension = "json"
        static let localizedDataHashKey = "quizice.localizedDataHashKey"
    }

    static let shared: ThemeCatalogRepository = {
        let environment = ProcessInfo.processInfo.environment
        let isRunningTests = environment["XCTestConfigurationFilePath"] != nil
            || environment["QUIZICE_XCTEST_SMOKE_HOST"] == "1"
            || NSClassFromString("XCTestCase") != nil
        let api = isRunningTests ? nil : BackendConfiguration.load().map {
            HTTPBackendContentAPI(
                configuration: $0,
                metrics: AppMetricaAnalyticsTracker.shared,
                accessTokenProvider: StoredBackendAccessTokenProvider(),
                authenticationRecoverer: NotificationBackendAuthenticationRecoverer()
            )
        }
        return ThemeCatalogRepository(backendContentAPI: api)
    }()

    private var localizationObserver: NSObjectProtocol?
    private var themeStore: SwiftDataThemeStore?
    private let themeDataLoader = LocalizedThemeDataLoader()
    private let backendContentAPI: BackendContentAPI?
    private let preferenceStore: OnboardingProgressStoring
    private let seedGenerator: () -> String
    private let accessTokenProvider: BackendAccessTokenProviding
    private let answerOutbox: QuestionAnswerOutboxing
    private let countryProvider: () -> String?
    private let repeatStrategyProvider: () -> QuestionRepeatStrategy

    private var loadedThemes: [QuizTheme]?
    private var favoritePrincipal: String?
    private var personalizationGeneration = UUID()
    var themes: [QuizTheme]? {
        get {
            let principal = accessTokenProvider.currentSession()?.userID
            if catalogOrigin == .backend, favoritePrincipal != principal {
                favoritePrincipal = principal
                loadedThemes?.sort { $0.stableID < $1.stableID }
                applyFavoriteOrder(preferenceStore.orderedPreferredThemeIDs(
                    locale: AppLocalizationStore.shared.resolvedLanguageCode
                ))
            }
            return loadedThemes
        }
        set {
            loadedThemes = newValue
            favoritePrincipal = accessTokenProvider.currentSession()?.userID
        }
    }
    private(set) var catalogOrigin: QuizCatalogOrigin = .bundled
    var onCatalogReplaced: (() -> Void)?

    init(
        backendContentAPI: BackendContentAPI? = nil,
        preferenceStore: OnboardingProgressStoring = OnboardingProgressStore.shared,
        seedGenerator: @escaping () -> String = { UUID().uuidString.lowercased() },
        accessTokenProvider: BackendAccessTokenProviding = StoredBackendAccessTokenProvider(),
        answerOutbox: QuestionAnswerOutboxing = PersistentQuestionAnswerOutbox.shared,
        repeatStrategyProvider: @escaping () -> QuestionRepeatStrategy = { QuestionRepeatStrategyStore.shared.strategy },
        countryProvider: @escaping () -> String? = { QuestionCountryStore.shared.country }
    ) {
        self.backendContentAPI = backendContentAPI
        self.preferenceStore = preferenceStore
        self.seedGenerator = seedGenerator
        self.accessTokenProvider = accessTokenProvider
        self.answerOutbox = answerOutbox
        self.repeatStrategyProvider = repeatStrategyProvider
        self.countryProvider = countryProvider
        localizationObserver = NotificationCenter.default.addObserver(
            forName: .appLocalizationDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadDataForLocalizationChange()
        }
    }

    deinit {
        if let localizationObserver {
            NotificationCenter.default.removeObserver(localizationObserver)
        }
    }

    func setModelContext(_ context: ModelContext) {
        themeStore = SwiftDataThemeStore(context: context)
    }

    /// Prevents a response started before deletion from restoring favorites.
    /// Catalog questions are public content; only their personalized flags reset.
    @MainActor
    func eraseCachedPersonalization() throws {
        personalizationGeneration = UUID()
        loadedThemes?.forEach { $0.isFavorite = false }
        favoritePrincipal = nil
        try themeStore?.erasePersonalization()
        onCatalogReplaced?()
    }

    func loadData(forceReload: Bool = false) {
        let cachedCatalog = themeStore?.fetchCatalog()
        let currentLocale = AppLocalizationStore.shared.resolvedLanguageCode
        if !forceReload,
           cachedCatalog?.origin == .backend,
           cachedCatalog?.locale == currentLocale,
           let cachedThemes = cachedCatalog?.themes,
           !cachedThemes.isEmpty {
            AppLog.content.debug(
                "Loading \(cachedThemes.count) backend themes from SwiftData"
            )
            themes = cachedThemes
            catalogOrigin = .backend
            applyFavoriteOrder(preferenceStore.orderedPreferredThemeIDs(locale: currentLocale))
            return
        }

        do {
            let loadedData = try themeDataLoader.load()
            let localizedHash = "\(loadedData.languageCode):\(loadedData.hash)"
            let savedHash = UserDefaults.standard.string(forKey: Content.localizedDataHashKey)
            let existingThemes = cachedCatalog?.origin == .bundled
                && cachedCatalog?.locale == loadedData.languageCode
                ? cachedCatalog?.themes ?? []
                : []

            // Guards against a stale/corrupted SwiftData cache (e.g. left over
            // from an older build) where themes were persisted with no usable
            // questions: the JSON hash would still match, so without this
            // check every theme's "Start" button would be permanently
            // disabled until the next forced reload.
            if !forceReload,
               localizedHash == savedHash,
               !existingThemes.isEmpty,
               hasThemeWithUsableQuestions(existingThemes) {
                AppLog.content.debug("JSON unchanged, loading \(existingThemes.count) themes from SwiftData")
                themes = existingThemes
                catalogOrigin = .bundled
                return
            }

            AppLog.content.debug("Localized JSON decoded for language: \(loadedData.languageCode, privacy: .public)")
            themeStore?.replaceThemes(
                with: loadedData.themes,
                locale: loadedData.languageCode,
                catalogOrigin: .bundled
            )
            UserDefaults.standard.set(localizedHash, forKey: Content.localizedDataHashKey)
            themes = loadedData.themes
            catalogOrigin = .bundled
            onCatalogReplaced?()
        } catch {
            AppLog.content.error("Localized data loading error: \(String(describing: error), privacy: .public)")
            AppMetricaAnalyticsTracker.shared.reportOperationalError(error, context: .contentLoad)
        }
    }

    func sha256Hash(for data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func hasThemeWithUsableQuestions(_ themes: [QuizTheme]) -> Bool {
        guard let minimumSupportedCount = QuizQuestionCountPolicy.supportedCounts.min() else {
            return true
        }
        return themes.contains { theme in
            QuizQuestionCountPolicy.usableQuestionCount(in: theme.questions.map(QuestionModel.init(quizQuestion:)))
                >= minimumSupportedCount
        }
    }

    func fetchQuizThemes() -> [QuizTheme] {
        themeStore?.fetchThemes() ?? []
    }

    @discardableResult
    @MainActor
    func refreshBackendCatalog(locale: String) async -> Bool {
        let principal = accessTokenProvider.currentSession()?.userID
        let refreshed = await refreshBackendCatalogOnce(locale: locale)
        guard !refreshed, !Task.isCancelled,
              accessTokenProvider.currentSession()?.userID != principal else { return refreshed }
        // Authentication may finish while the startup catalog request is in
        // flight. Fetch once for the new account after discarding that response.
        return await refreshBackendCatalogOnce(locale: locale)
    }

    @MainActor
    private func refreshBackendCatalogOnce(locale: String) async -> Bool {
        guard let backendContentAPI else { return false }
        let principal = accessTokenProvider.currentSession()?.userID
        let revision = preferenceStore.preferencesRevision(locale: locale)
        let generation = personalizationGeneration
        do {
            let response = try await backendContentAPI.fetchThemes(locale: locale)
            try Task.checkCancellation()

            guard !response.themes.isEmpty else {
                throw BackendContentError.contractViolation
            }

            let backendThemes = response.themes.map { remoteTheme in
                QuizTheme(
                    id: remoteTheme.id,
                    theme: remoteTheme.name,
                    themeDescription: remoteTheme.description,
                    questions: [],
                    sfSymbolName: remoteTheme.sfSymbol,
                    emoji: remoteTheme.emoji,
                    colorHex: remoteTheme.colorHex,
                    isFavorite: remoteTheme.isFavorite,
                    source: .catalog,
                    questionOrigin: .backend,
                    countries: remoteTheme.countries
                )
            }
            let remoteFavoriteIDs = response.themes.filter(\.isFavorite).map(\.id)

            // All mutations of shared state (themes, catalogOrigin,
            // preferenceStore) and the onCatalogReplaced callback run on the
            // main queue. Without this hop, the continuation may resume on a
            // background executor and race with UI readers of `themes`.
            return await MainActor.run {
                guard AppLocalizationStore.shared.resolvedLanguageCode == locale,
                      personalizationGeneration == generation,
                      accessTokenProvider.currentSession()?.userID == principal else { return false }
                // Catalog metadata is shared; account-specific favorites are
                // persisted exclusively in the scoped preference store.
                let cachedThemes = backendThemes.map { theme in
                    QuizTheme(id: theme.id, theme: theme.theme, themeDescription: theme.themeDescription,
                              questions: [], sfSymbolName: theme.sfSymbolName, emoji: theme.emoji,
                              colorHex: theme.colorHex, isFavorite: false, source: .catalog,
                              questionOrigin: .backend, countries: theme.countries)
                }
                themeStore?.replaceThemes(
                    with: cachedThemes,
                    locale: locale,
                    catalogOrigin: .backend
                )
                themes = backendThemes
                if preferenceStore.preferencesRevision(locale: locale) == revision,
                   !preferenceStore.hasPendingThemePreferences(locale: locale) {
                    preferenceStore.applyRemotePreferredThemeIDs(remoteFavoriteIDs, locale: locale)
                }
                catalogOrigin = .backend
                onCatalogReplaced?()
                AppLog.content.info(
                    "Backend theme catalog accepted: locale=\(locale, privacy: .public) themes=\(backendThemes.count, privacy: .public)"
                )
                return true
            }
        } catch is CancellationError {
            return false
        } catch {
            handleAuthenticationFailureIfNeeded(error)
            AppLog.content.error(
                "Backend theme catalog rejected; current catalog remains active: origin=\(self.catalogOrigin.rawValue, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
            return false
        }
    }

    @discardableResult
    @MainActor
    func synchronizeThemePreferences(locale: String) async -> Bool {
        guard let backendContentAPI else { return false }
        let principal = accessTokenProvider.currentSession()?.userID
        let storedIDs = preferenceStore.orderedPreferredThemeIDs(locale: locale)
        let revision = preferenceStore.preferencesRevision(locale: locale)
        let generation = personalizationGeneration
        let favoriteThemeIDs: [String]
        if catalogOrigin == .backend {
            let availableIDs = Set((themes ?? []).map(\.stableID))
            favoriteThemeIDs = storedIDs.filter(availableIDs.contains)
        } else {
            favoriteThemeIDs = storedIDs
        }

        do {
            let response: BackendThemePreferencesResponse
            if preferenceStore.hasPendingThemePreferences(locale: locale) {
                response = try await backendContentAPI.replaceThemePreferences(
                    locale: locale,
                    favoriteThemeIDs: favoriteThemeIDs
                )
            } else {
                response = try await backendContentAPI.fetchThemePreferences(locale: locale)
            }
            try Task.checkCancellation()

            // Post-await mutations of preferenceStore, themes ordering, and
            // the onCatalogReplaced callback run on the main queue.
            return await MainActor.run {
                guard AppLocalizationStore.shared.resolvedLanguageCode == locale,
                      personalizationGeneration == generation,
                      accessTokenProvider.currentSession()?.userID == principal,
                      preferenceStore.preferencesRevision(locale: locale) == revision else { return false }
                preferenceStore.applyRemotePreferredThemeIDs(
                    response.favoriteThemeIds,
                    locale: locale
                )
                applyFavoriteOrder(response.favoriteThemeIds)
                onCatalogReplaced?()
                AppLog.content.info(
                    "Theme preferences synchronized: locale=\(locale, privacy: .public) favorites=\(response.favoriteThemeIds.count, privacy: .public)"
                )
                return true
            }
        } catch is CancellationError {
            return false
        } catch BackendContentError.unauthenticated {
            return false
        } catch {
            handleAuthenticationFailureIfNeeded(error)
            AppLog.content.error(
                "Theme preferences sync deferred: locale=\(locale, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
            return false
        }
    }

    @MainActor
    func prepareQuiz(
        themeID: String,
        questionCount: Int,
        locale: String
    ) async throws -> QuizTheme {
        try await prepareQuiz(
            themeID: themeID,
            questionCount: questionCount,
            difficulty: .medium,
            locale: locale
        )
    }

    @MainActor
    func prepareQuiz(
        themeID: String,
        questionCount: Int,
        difficulty: AIQuizDifficulty,
        locale: String
    ) async throws -> QuizTheme {
        guard
            QuizQuestionCountPolicy.supportedCounts.contains(questionCount),
            let metadata = (themes ?? fetchQuizThemes()).first(where: {
                $0.stableID == themeID
            })
        else {
            throw QuizPreparationError.unavailable
        }

        guard catalogOrigin == .backend else {
            AppLog.content.notice(
                "📦 LOCAL QUESTIONS: bundled catalog active theme=\(themeID, privacy: .public) locale=\(locale, privacy: .public) count=\(questionCount, privacy: .public)"
            )
            return try makeLocalQuiz(
                themeID: themeID,
                questionCount: questionCount
            )
        }
        guard let backendContentAPI else { throw QuizPreparationError.unavailable }

        let selectedCountry = countryProvider()
        let strategy = effectiveQuestionRepeatStrategy
        let userID = accessTokenProvider.currentSession()?.userID
        if strategy.progressMode != nil {
            guard let userID else { throw BackendContentError.unauthenticated }
            try await answerOutbox.synchronizeBeforeFetchingQuestions(for: userID)
            guard accessTokenProvider.currentSession()?.userID == userID else {
                throw QuestionAnswerSyncError.accountChanged
            }
        }
        let seed = seedGenerator()
        let startedAt = Date()
        do {
            let response = try await backendContentAPI.fetchQuestions(
                themeID: themeID,
                count: questionCount,
                locale: locale,
                difficulty: difficulty,
                seed: seed,
                strategy: strategy,
                country: selectedCountry.flatMap { metadata.countries.contains($0) ? $0 : nil }
            )
            try Task.checkCancellation()
            guard AppLocalizationStore.shared.resolvedLanguageCode == locale,
                  countryProvider() == selectedCountry else {
                throw CancellationError()
            }

            guard accessTokenProvider.currentSession()?.userID == userID else {
                throw QuestionAnswerSyncError.accountChanged
            }
            // The final filtered round can contain fewer questions than requested.
            // Preserve every issued question and record its actual completed count.
            let questions = response.questions.map { $0.makeModel(locale: response.locale) }
            AppLog.content.notice(
                "✅ BACKEND QUESTIONS: received theme=\(themeID, privacy: .public) locale=\(locale, privacy: .public) requested=\(questionCount, privacy: .public) received=\(questions.count, privacy: .public) seed=\(seed, privacy: .public) duration_ms=\(Self.durationMilliseconds(since: startedAt), privacy: .public)"
            )
            return QuizTheme(
                id: metadata.id,
                theme: metadata.theme,
                themeDescription: metadata.themeDescription,
                questions: questions,
                sfSymbolName: metadata.sfSymbolName,
                emoji: metadata.emoji,
                colorHex: metadata.colorHex,
                isFavorite: metadata.isFavorite,
                source: .catalog,
                questionOrigin: .backend,
                difficulty: difficulty,
                countries: metadata.countries
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AppLog.content.error(
                "⚠️ BACKEND QUESTIONS: failed, no bundled fallback in backend catalog mode theme=\(themeID, privacy: .public) locale=\(locale, privacy: .public) count=\(questionCount, privacy: .public) seed=\(seed, privacy: .public) duration_ms=\(Self.durationMilliseconds(since: startedAt), privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
            throw error
        }
    }

    @MainActor
    func prepareRandomQuiz(
        selectionMode: CrossThemeQuestionSelectionMode,
        localFallback: QuizTheme,
        questionCount: Int,
        locale: String
    ) async throws -> QuizTheme {
        try await prepareRandomQuiz(
            selectionMode: selectionMode,
            localFallback: localFallback,
            questionCount: questionCount,
            difficulty: .medium,
            locale: locale
        )
    }

    @MainActor
    func prepareRandomQuiz(
        selectionMode: CrossThemeQuestionSelectionMode,
        localFallback: QuizTheme,
        questionCount: Int,
        difficulty: AIQuizDifficulty,
        locale: String
    ) async throws -> QuizTheme {
        guard QuizQuestionCountPolicy.supportedCounts.contains(questionCount) else {
            throw QuizPreparationError.unavailable
        }
        guard catalogOrigin == .backend else {
            AppLog.content.notice(
                "📦 LOCAL RANDOM QUESTIONS: bundled catalog active mode=\(selectionMode.rawValue, privacy: .public) locale=\(locale, privacy: .public) count=\(questionCount, privacy: .public)"
            )
            return localFallback
        }
        guard let backendContentAPI else { throw QuizPreparationError.unavailable }

        let selectedCountry = countryProvider()
        let strategy = effectiveQuestionRepeatStrategy
        let userID = accessTokenProvider.currentSession()?.userID
        if strategy.progressMode != nil {
            guard let userID else { throw BackendContentError.unauthenticated }
            try await answerOutbox.synchronizeBeforeFetchingQuestions(for: userID)
            guard accessTokenProvider.currentSession()?.userID == userID else {
                throw QuestionAnswerSyncError.accountChanged
            }
        }
        let seed = seedGenerator()
        let startedAt = Date()
        do {
            let response = try await backendContentAPI.fetchRandomQuestions(
                selectionMode: selectionMode,
                count: questionCount,
                locale: locale,
                difficulty: difficulty,
                seed: seed,
                strategy: strategy,
                country: selectedCountry
            )
            try Task.checkCancellation()
            guard AppLocalizationStore.shared.resolvedLanguageCode == locale,
                  countryProvider() == selectedCountry else {
                throw CancellationError()
            }

            guard accessTokenProvider.currentSession()?.userID == userID else {
                throw QuestionAnswerSyncError.accountChanged
            }
            // The final filtered round can contain fewer questions than requested.
            // Preserve every issued question and record its actual completed count.
            let questions = response.questions.map { $0.makeModel(locale: response.locale) }
            AppLog.content.notice(
                "✅ BACKEND RANDOM QUESTIONS: received mode=\(selectionMode.rawValue, privacy: .public) locale=\(locale, privacy: .public) requested=\(questionCount, privacy: .public) received=\(questions.count, privacy: .public) seed=\(seed, privacy: .public) duration_ms=\(Self.durationMilliseconds(since: startedAt), privacy: .public)"
            )
            return QuizTheme(
                id: RandomQuizSelection.themeID,
                theme: localFallback.theme,
                themeDescription: localFallback.themeDescription,
                questions: questions,
                sfSymbolName: localFallback.sfSymbolName,
                emoji: localFallback.emoji,
                colorHex: localFallback.colorHex,
                isFavorite: localFallback.isFavorite,
                source: .catalog,
                questionOrigin: .backend,
                difficulty: difficulty
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AppLog.content.error(
                "⚠️ BACKEND RANDOM QUESTIONS: failed, no bundled fallback in backend catalog mode selection=\(selectionMode.rawValue, privacy: .public) locale=\(locale, privacy: .public) count=\(questionCount, privacy: .public) seed=\(seed, privacy: .public) duration_ms=\(Self.durationMilliseconds(since: startedAt), privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
            throw error
        }
    }

    func clearSwiftData(context: ModelContext) {
        SwiftDataThemeStore(context: context).clearThemes()
    }

    private func makeLocalQuiz(
        themeID: String,
        questionCount: Int
    ) throws -> QuizTheme {
        let catalog = themes ?? fetchQuizThemes()
        guard
            QuizQuestionCountPolicy.supportedCounts.contains(questionCount),
            let theme = catalog.first(where: { $0.stableID == themeID })
        else {
            throw QuizPreparationError.unavailable
        }

        let usableQuestions = theme.questions.filter {
            QuizQuestionCountPolicy.isUsable(QuestionModel(quizQuestion: $0))
        }
        guard usableQuestions.count >= questionCount else {
            throw QuizPreparationError.unavailable
        }
        return QuizTheme(
            id: theme.id,
            theme: theme.theme,
            themeDescription: theme.themeDescription,
            questions: Array(usableQuestions.shuffled().prefix(questionCount)),
            sfSymbolName: theme.sfSymbolName,
            emoji: theme.emoji,
            colorHex: theme.colorHex,
            isFavorite: theme.isFavorite,
            source: theme.source,
            questionOrigin: .bundled
        )
    }

    private func reloadDataForLocalizationChange() {
        guard themeStore != nil else { return }
        loadData(forceReload: true)
    }

    private func applyFavoriteOrder(_ favoriteThemeIDs: [String]) {
        guard let currentThemes = themes else { return }
        let rankByID = Dictionary(
            uniqueKeysWithValues: favoriteThemeIDs.enumerated().map { ($0.element, $0.offset) }
        )
        currentThemes.forEach {
            $0.isFavorite = rankByID[$0.stableID] != nil
        }
        themes = currentThemes.enumerated()
            .sorted { lhs, rhs in
                let lhsRank = rankByID[lhs.element.stableID]
                let rhsRank = rankByID[rhs.element.stableID]
                switch (lhsRank, rhsRank) {
                case let (.some(lhsRank), .some(rhsRank)):
                    return lhsRank < rhsRank
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }

    private func handleAuthenticationFailureIfNeeded(_ error: Error) {
        guard case BackendContentError.httpStatus(401, _) = error else { return }
        NotificationCenter.default.post(name: .backendAuthenticationInvalidated, object: nil)
    }

    private var effectiveQuestionRepeatStrategy: QuestionRepeatStrategy {
        repeatStrategyProvider().effective(
            hasValidBackendSession: accessTokenProvider.currentSession() != nil || accessTokenProvider.validAccessToken() != nil
        )
    }

    private static func durationMilliseconds(since startDate: Date) -> Int {
        max(Int(Date().timeIntervalSince(startDate) * 1_000), 0)
    }
}
