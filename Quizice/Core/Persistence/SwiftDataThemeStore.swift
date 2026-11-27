import Foundation
import SwiftData

@Model
private final class StoredQuizQuestion {
    var question: String
    var answers: [String]
    var correctAnswer: String
    var explanation: String?

    init(
        question: String,
        answers: [String],
        correctAnswer: String,
        explanation: String? = nil
    ) {
        self.question = question
        self.answers = answers
        self.correctAnswer = correctAnswer
        self.explanation = explanation
    }

    convenience init(model: QuizQuestion) {
        self.init(
            question: model.question,
            answers: model.answers,
            correctAnswer: model.correctAnswer,
            explanation: model.explanation
        )
    }

    func makeDomainModel() -> QuizQuestion {
        QuizQuestion(
            question: question,
            answers: answers,
            correctAnswer: correctAnswer,
            explanation: explanation
        )
    }
}

@Model
private final class StoredQuizTheme {
    @Attribute(.unique) var id: String
    var theme: String
    var themeDescription: String
    var sfSymbolName: String?
    var emoji: String?
    var colorHex: String?
    var isFavorite: Bool?
    var sourceRawValue: String?
    var questionOriginRawValue: String?
    var catalogLocale: String?
    var countries: [String]?
    var subtopicsData: Data?
    var catalogOriginRawValue: String?
    @Relationship(deleteRule: .cascade) var questions: [StoredQuizQuestion]

    init(
        id: String,
        theme: String,
        themeDescription: String,
        sfSymbolName: String?,
        emoji: String?,
        colorHex: String?,
        isFavorite: Bool?,
        sourceRawValue: String?,
        questionOriginRawValue: String?,
        catalogLocale: String?,
        catalogOriginRawValue: String?,
        questions: [StoredQuizQuestion],
        countries: [String]? = nil,
        subtopicsData: Data? = nil
    ) {
        self.id = id
        self.theme = theme
        self.themeDescription = themeDescription
        self.sfSymbolName = sfSymbolName
        self.emoji = emoji
        self.colorHex = colorHex
        self.isFavorite = isFavorite
        self.sourceRawValue = sourceRawValue
        self.questionOriginRawValue = questionOriginRawValue
        self.catalogLocale = catalogLocale
        self.catalogOriginRawValue = catalogOriginRawValue
        self.questions = questions
        self.countries = countries
        self.subtopicsData = subtopicsData
    }

    convenience init(
        model: QuizTheme,
        catalogLocale: String,
        catalogOrigin: QuizCatalogOrigin
    ) {
        self.init(
            id: model.id,
            theme: model.theme,
            themeDescription: model.themeDescription,
            sfSymbolName: model.sfSymbolName,
            emoji: model.emoji,
            colorHex: model.colorHex,
            isFavorite: model.isFavorite,
            sourceRawValue: model.source.rawValue,
            questionOriginRawValue: model.questionOrigin.rawValue,
            catalogLocale: catalogLocale,
            catalogOriginRawValue: catalogOrigin.rawValue,
            questions: model.questions.map(StoredQuizQuestion.init(model:)),
            countries: model.countries,
            subtopicsData: try? JSONEncoder().encode(model.subtopics)
        )
    }

    func makeDomainModel() -> QuizTheme {
        QuizTheme(
            id: id,
            theme: theme,
            themeDescription: themeDescription,
            questions: questions.map { $0.makeDomainModel() },
            sfSymbolName: sfSymbolName ?? QuizTheme.defaultSFSymbolName,
            emoji: emoji ?? QuizTheme.defaultEmoji,
            colorHex: colorHex,
            isFavorite: isFavorite ?? false,
            source: QuizThemeSource(rawValue: sourceRawValue ?? "") ?? .catalog,
            questionOrigin: QuizQuestionOrigin(rawValue: questionOriginRawValue ?? "") ?? .bundled,
            countries: countries ?? [],
            subtopics: subtopicsData.flatMap { try? JSONDecoder().decode([QuizSubtopic].self, from: $0) } ?? []
        )
    }
}

final class SwiftDataThemeStore {
    struct CatalogSnapshot {
        let themes: [QuizTheme]
        let locale: String?
        let origin: QuizCatalogOrigin
    }

    static var schema: Schema {
        Schema([StoredQuizTheme.self, StoredQuizQuestion.self])
    }

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchThemes() -> [QuizTheme] {
        fetchCatalog().themes
    }

    func fetchCatalog() -> CatalogSnapshot {
        let descriptor = FetchDescriptor<StoredQuizTheme>(sortBy: [SortDescriptor(\.theme)])
        do {
            let storedThemes = try context.fetch(descriptor)
            let firstTheme = storedThemes.first
            return CatalogSnapshot(
                themes: storedThemes.map { $0.makeDomainModel() },
                locale: firstTheme?.catalogLocale,
                origin: QuizCatalogOrigin(
                    rawValue: firstTheme?.catalogOriginRawValue ?? ""
                ) ?? .bundled
            )
        } catch {
            AppLog.persistence.error("Failed to fetch themes: \(String(describing: error), privacy: .public)")
            AppMetricaAnalyticsTracker.shared.reportOperationalError(error, context: .persistentStore)
            return CatalogSnapshot(themes: [], locale: nil, origin: .bundled)
        }
    }

    func replaceThemes(
        with themes: [QuizTheme]
    ) {
        replaceThemes(
            with: themes,
            locale: AppLocalizationStore.shared.resolvedLanguageCode,
            catalogOrigin: .bundled
        )
    }

    func replaceThemes(
        with themes: [QuizTheme],
        locale: String,
        catalogOrigin: QuizCatalogOrigin
    ) {
        do {
            let previous = try context.fetch(FetchDescriptor<StoredQuizTheme>())
            for theme in previous { context.delete(theme) }
            for theme in themes {
                context.insert(StoredQuizTheme(
                    model: theme, catalogLocale: locale, catalogOrigin: catalogOrigin
                ))
            }
            // Delete and insert in one save: a failed refresh keeps the previous
            // persisted catalogue available on the next launch.
            try context.save()
        } catch {
            context.rollback()
            AppLog.persistence.error("Failed to save themes: \(String(describing: error), privacy: .public)")
            AppMetricaAnalyticsTracker.shared.reportOperationalError(error, context: .persistentStore)
        }
    }

    func clearThemes() {
        do {
            let themes = try context.fetch(FetchDescriptor<StoredQuizTheme>())
            for theme in themes {
                context.delete(theme)
            }
            try context.save()
            AppLog.persistence.debug("SwiftData cleared")
        } catch {
            context.rollback()
            AppLog.persistence.error("Database clearing error: \(String(describing: error), privacy: .public)")
            AppMetricaAnalyticsTracker.shared.reportOperationalError(error, context: .persistentStore)
        }
    }

    func erasePersonalization() throws {
        do {
            let themes = try context.fetch(FetchDescriptor<StoredQuizTheme>())
            for theme in themes { theme.isFavorite = false }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
