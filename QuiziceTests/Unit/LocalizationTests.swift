import UIKit
import XCTest
@testable import Quizice

final class LocalizationTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppLocalizationStore.Keys.language)
        super.tearDown()
    }

    func testLanguageStoreUsesExplicitLanguagePreference() {
        let suiteName = "LocalizationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = AppLocalizationStore(
            userDefaults: defaults,
            preferredLanguagesProvider: { ["de-DE"] }
        )

        store.languagePreference = .spanish

        XCTAssertEqual(store.resolvedLanguageCode, "es")
    }

    func testSystemLanguageResolvesSupportedRegionCode() {
        XCTAssertEqual(
            AppLocalizationStore.resolveSystemLanguageCode(preferredLanguages: ["es-MX", "en-US"]),
            "es"
        )
    }

    func testSystemLanguageFallsBackToEnglishWhenUnsupported() {
        XCTAssertEqual(
            AppLocalizationStore.resolveSystemLanguageCode(preferredLanguages: ["pt-BR", "ja-JP"]),
            "en"
        )
    }

    func testL10nReadsSelectedLanguageBundle() {
        AppLocalizationStore.shared.languagePreference = .english
        XCTAssertEqual(L10n.Common.next, "Next")

        AppLocalizationStore.shared.languagePreference = .russian
        XCTAssertEqual(L10n.Common.next, "Далее")
        XCTAssertEqual(L10n.Question.loadingFailedTitle, "Не удалось загрузить вопросы")
        XCTAssertEqual(L10n.Question.loadingFailedMessage, "Не удалось получить вопросы. Попробуйте ещё раз немного позже.")
        XCTAssertEqual(L10n.Question.networkFailureMessage, "Проверьте подключение к интернету и попробуйте снова.")
        XCTAssertEqual(L10n.Settings.QuestionStrategy.section, "Вопросы")
        XCTAssertEqual(L10n.Settings.QuestionStrategy.title, "Стратегия повторения")
        XCTAssertEqual(
            L10n.Settings.QuestionStrategy.title(for: .showAll),
            "Показывать все"
        )

        AppLocalizationStore.shared.languagePreference = .french
        XCTAssertEqual(L10n.Settings.language, "Langue")
    }

    func testDesignPolishCopyExistsInEverySupportedLocalization() throws {
        let root = localizedDataRoot()
        let languages = ["ru", "en", "es", "de", "it", "fr"]
        let requiredKeys = [
            "home.background_style.switcher",
            "home.background_style.original",
            "home.background_style.grid_4x4",
            "home.background_style.grid_5x5",
            "home.feeling_lucky.loading",
            "home.feeling_lucky.random_selection",
            "debug_menu.title",
            "debug_menu.hide_interface",
            "debug_menu.pulse",
            "debug_menu.pulse.subtitle",
            "ai_theme.prompt_too_long",
            "question.exit_alert.title",
            "question.exit_alert.message",
            "question.loading_failed.title",
            "question.loading_failed.message",
            "question.network_failure.message",
            "question.show_explanation",
            "question.show_question",
            "question.time_remaining",
            "result.play_again",
            "result.to_themes",
            "onboarding.action.skip",
            "onboarding.action.get_started",
            "onboarding.help.accessibility_label",
            "onboarding.help.accessibility_hint",
            "onboarding.progress_format",
            "onboarding.welcome.kicker",
            "onboarding.welcome.title",
            "onboarding.welcome.subtitle",
            "onboarding.topics.title",
            "onboarding.topics.subtitle",
            "onboarding.topics.selection_hint",
            "onboarding.topics.selected",
            "onboarding.topic.music",
            "onboarding.topic.technology",
            "onboarding.topic.history_culture",
            "onboarding.topic.politics_business",
            "onboarding.tutorial.title",
            "onboarding.tutorial.subtitle",
            "onboarding.tutorial.themes.title",
            "onboarding.tutorial.themes.detail",
            "onboarding.tutorial.ai.title",
            "onboarding.tutorial.ai.detail",
            "onboarding.tutorial.statistics.title",
            "onboarding.tutorial.statistics.detail",
            "onboarding.question_strategy.title",
            "onboarding.question_strategy.subtitle",
            "onboarding.question_strategy.settings_hint",
            "onboarding.question_strategy.availability_hint",
            "onboarding.question_strategy.hideAnswered.detail",
            "onboarding.question_strategy.retryIncorrect.detail",
            "onboarding.question_strategy.showAll.detail",
            "subscription.home.title",
            "subscription.home.subtitle",
            "subscription.home.price_badge",
            "subscription.home.accessibility_hint",
            "subscription.ai_card.title",
            "subscription.ai_card.subtitle",
            "subscription.ai_card.accessibility_hint",
            "subscription.badge.free",
            "subscription.paywall.eyebrow",
            "subscription.paywall.title",
            "subscription.paywall.subtitle",
            "subscription.paywall.free",
            "subscription.paywall.plus",
            "subscription.paywall.questions",
            "subscription.paywall.multiplier",
            "subscription.paywall.benefit.limit.title",
            "subscription.paywall.benefit.limit.subtitle",
            "subscription.paywall.benefit.flexibility.title",
            "subscription.paywall.benefit.flexibility.subtitle",
            "subscription.paywall.plan.title",
            "subscription.paywall.price_format",
            "subscription.paywall.plan.note",
            "subscription.paywall.cta_format",
            "subscription.paywall.restore",
            "subscription.paywall.legal",
            "subscription.paywall.close",
            "subscription.paywall.coming_soon.title",
            "subscription.paywall.coming_soon.message",
            "subscription.paywall.coming_soon.action"
        ]

        for language in languages {
            let url = root.appendingPathComponent("\(language).lproj/Localizable.strings")
            let data = try Data(contentsOf: url)
            var format = PropertyListSerialization.PropertyListFormat.openStep
            let strings = try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: String]
            )

            for key in requiredKeys {
                let value = try XCTUnwrap(strings[key], "Missing \(key) in \(language)")
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty \(key) in \(language)")
            }
        }
    }

    func testLocalizedDataFilesKeepStableThemeShapeAndValidAnswers() throws {
        let root = localizedDataRoot()
        let languages = ["ru", "en", "es", "de", "it", "fr"]
        var expectedThemeIDs: [String]?
        var expectedQuestionCounts: [Int]?
        var expectedSFSymbols: [String]?
        var expectedEmojis: [String]?
        var expectedColorHexes: [String]?

        for language in languages {
            let url = root.appendingPathComponent("\(language).lproj/data.json")
            let data = try Data(contentsOf: url)
            let themes = try JSONDecoder().decode([QuizThemePayload].self, from: data)

            let themeIDs = themes.map(\.id)
            let questionCounts = themes.map { $0.questions.count }
            let sfSymbols = themes.map(\.sfSymbol)
            let emojis = themes.map(\.emoji)
            let colorHexes = themes.map(\.colorHex)
            if expectedThemeIDs == nil {
                expectedThemeIDs = themeIDs
                expectedQuestionCounts = questionCounts
                expectedSFSymbols = sfSymbols
                expectedEmojis = emojis
                expectedColorHexes = colorHexes
            }

            XCTAssertEqual(themeIDs, expectedThemeIDs, "Theme IDs must match in \(language)")
            XCTAssertEqual(questionCounts, expectedQuestionCounts, "Question counts must match in \(language)")
            XCTAssertEqual(sfSymbols, expectedSFSymbols, "SF Symbols must match in \(language)")
            XCTAssertEqual(emojis, expectedEmojis, "Emoji must match in \(language)")
            XCTAssertEqual(colorHexes, expectedColorHexes, "Theme colors must match in \(language)")

            for theme in themes {
                XCTAssertFalse(theme.theme.isEmpty, "Theme title must not be empty in \(language)")
                XCTAssertFalse(theme.themeDescription.isEmpty, "Theme description must not be empty in \(language)")
                XCTAssertNotNil(
                    UIImage(systemName: theme.sfSymbol),
                    "Invalid SF Symbol '\(theme.sfSymbol)' in \(language)"
                )
                XCTAssertFalse(theme.emoji.isEmpty, "Theme emoji must not be empty in \(language)")
                XCTAssertEqual(
                    QuizThemeColor.normalizedHex(theme.colorHex),
                    theme.colorHex,
                    "Invalid theme color '\(theme.colorHex)' in \(language)"
                )
                for question in theme.questions {
                    XCTAssertFalse(question.question.isEmpty, "Question text must not be empty in \(language)")
                    XCTAssertTrue(
                        question.answers.contains(question.correctAnswer),
                        "Correct answer must be one of answers in \(language): \(question.question)"
                    )
                }
            }
        }
    }

    func testNonRussianDataFilesDoNotContainCyrillicQuestionContent() throws {
        let root = localizedDataRoot()
        let nonRussianLanguages = ["en", "es", "de", "it", "fr"]
        let cyrillicRange = try NSRegularExpression(pattern: #"[А-Яа-яЁё]"#)

        for language in nonRussianLanguages {
            let url = root.appendingPathComponent("\(language).lproj/data.json")
            let data = try Data(contentsOf: url)
            let themes = try JSONDecoder().decode([QuizThemePayload].self, from: data)

            for theme in themes {
                for question in theme.questions {
                    let values = [question.question, question.correctAnswer] + question.answers
                    for value in values {
                        let range = NSRange(value.startIndex..<value.endIndex, in: value)
                        XCTAssertNil(
                            cyrillicRange.firstMatch(in: value, range: range),
                            "\(language) contains Cyrillic quiz content: \(value)"
                        )
                    }
                }
            }
        }
    }

    func testBundledQuestionsAreUniqueAndSupportFullQuizzes() throws {
        for (name, themes) in try allBundledPayloads() {
            var seenQuestions = Set<String>()
            for theme in themes {
                XCTAssertGreaterThanOrEqual(theme.questions.count, 15, "Insufficient questions: \(name)/\(theme.id)")
                for question in theme.questions {
                    let normalized = question.question
                        .precomposedStringWithCanonicalMapping
                        .lowercased()
                        .split(whereSeparator: \.isWhitespace)
                        .joined(separator: " ")
                    XCTAssertTrue(seenQuestions.insert(normalized).inserted, "Duplicate in \(name): \(question.question)")
                    XCTAssertEqual(Set(question.answers).count, 4, "Four distinct answers required: \(name)/\(question.question)")
                    XCTAssertFalse(question.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    func testSatisfactionReleaseExplanationUsesTheYearFromTheQuestion() throws {
        for (name, themes) in try allBundledPayloads() {
            let question = try XCTUnwrap(themes.flatMap(\.questions).first {
                $0.correctAnswer == "Satisfaction" && $0.question.contains("1965")
            }, "Missing release-year question in \(name)")
            XCTAssertTrue(question.explanation.contains("1965"), "Release year missing from explanation in \(name)")
        }
    }

    func testFallbackQuestionsMatchRussianCatalog() throws {
        let payloads = try allBundledPayloads()
        let fallback = try XCTUnwrap(payloads.first { $0.name == "fallback" }?.themes)
        let russian = try XCTUnwrap(payloads.first { $0.name == "ru" }?.themes)
        XCTAssertEqual(fallback.map(\.id), russian.map(\.id))
        XCTAssertEqual(fallback.map(\.questions), russian.map(\.questions))
    }

    func testNonRussianDataFilesDoNotContainTransliteratedRussianQuestionFragments() throws {
        let root = localizedDataRoot()
        let nonRussianLanguages = ["en", "es", "de", "it", "fr"]
        let badFragments = [
            "V kakom",
            "Kak nazyvaetsya",
            "krupneyshaya",
            "provela",
            "sovet direktorov",
            "tekhnologiyu",
            "zamorazhivaniya",
            "gosdolga",
            "denezhnoy massy",
            "Bozhestvennoy",
            "imperatorom Kitaya",
            "besprovodnoy svyazi",
        ]

        for language in nonRussianLanguages {
            let url = root.appendingPathComponent("\(language).lproj/data.json")
            let data = try Data(contentsOf: url)
            let themes = try JSONDecoder().decode([QuizThemePayload].self, from: data)

            for theme in themes {
                for question in theme.questions {
                    for fragment in badFragments {
                        XCTAssertFalse(
                            question.question.localizedCaseInsensitiveContains(fragment),
                            "\(language) contains a transliterated Russian fragment '\(fragment)': \(question.question)"
                        )
                    }
                }
            }
        }
    }

    private func localizedDataRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Quizice")
    }

    private func allBundledPayloads() throws -> [(name: String, themes: [QuizThemePayload])] {
        try ["ru", "en", "es", "de", "it", "fr", "fallback"].map { name in
            let path = name == "fallback" ? "data.json" : "\(name).lproj/data.json"
            let data = try Data(contentsOf: localizedDataRoot().appendingPathComponent(path))
            return (name, try JSONDecoder().decode([QuizThemePayload].self, from: data))
        }
    }
}

private struct QuizThemePayload: Decodable {
    let id: String
    let theme: String
    let themeDescription: String
    let sfSymbol: String
    let emoji: String
    let colorHex: String
    let questions: [QuizQuestionPayload]
}

private struct QuizQuestionPayload: Decodable, Equatable {
    let question: String
    let answers: [String]
    let correctAnswer: String
    let explanation: String
}
