import Foundation

enum L10n {
    private static func localized(_ key: String, comment: String) -> String {
        AppLocalizationStore.shared.localizedBundle.localizedString(forKey: key, value: nil, table: "Localizable")
    }

    private static func formatted(_ key: String, comment: String, _ arguments: CVarArg...) -> String {
        let format = localized(key, comment: comment)
        return String(format: format, locale: AppLocalizationStore.shared.resolvedLocale, arguments: arguments)
    }

    enum Common {
        static var back: String { L10n.localized("common.back", comment: "Back button title") }
        static var exit: String { L10n.localized("common.exit", comment: "Exit button title") }
        static var next: String { L10n.localized("common.next", comment: "Next button title") }
        static var no: String { L10n.localized("common.no", comment: "Negative alert action title") }
        static var start: String { L10n.localized("common.start", comment: "Start button title") }
        static var yes: String { L10n.localized("common.yes", comment: "Positive alert action title") }
    }

    enum AccountStart {
        static var deletionSignInRequired: String { L10n.localized("account_start.deletion_pending.sign_in", comment: "Sign in to the original Game Center account to finish deletion") }
        static var connectingTitle: String { L10n.localized("account_start.connecting.title", comment: "Account connection in progress") }
        static var signInMessage: String { L10n.localized("account_start.sign_in.message", comment: "Game Center sign-in required before playing") }
        static var continueWithGameCenter: String { L10n.localized("account_start.sign_in.action", comment: "Explicit Game Center sign-in action") }
        static var deletionPendingTitle: String { L10n.localized("account_start.deletion_pending.title", comment: "Account deletion must finish before playing") }
        static var deletionPendingMessage: String { L10n.localized("account_start.deletion_pending.message", comment: "Finish pending account deletion guidance") }
        static var retryDeletion: String { L10n.localized("account_start.deletion_pending.action", comment: "Retry pending account deletion action") }
    }

    enum Onboarding {
        static var skip: String { L10n.localized("onboarding.action.skip", comment: "Skip onboarding button title") }
        static var getStarted: String { L10n.localized("onboarding.action.get_started", comment: "Finish onboarding button title") }
        static var helpAccessibilityLabel: String { L10n.localized("onboarding.help.accessibility_label", comment: "Onboarding help button accessibility label") }
        static var helpAccessibilityHint: String { L10n.localized("onboarding.help.accessibility_hint", comment: "Onboarding help button accessibility hint") }
        static var welcomeKicker: String { L10n.localized("onboarding.welcome.kicker", comment: "Onboarding welcome page kicker") }
        static var welcomeTitle: String { L10n.localized("onboarding.welcome.title", comment: "Onboarding welcome page title") }
        static var welcomeSubtitle: String { L10n.localized("onboarding.welcome.subtitle", comment: "Onboarding welcome page subtitle") }
        static var topicsTitle: String { L10n.localized("onboarding.topics.title", comment: "Onboarding topic selection page title") }
        static var topicsSubtitle: String { L10n.localized("onboarding.topics.subtitle", comment: "Onboarding topic selection page subtitle") }
        static var topicsSelectionHint: String { L10n.localized("onboarding.topics.selection_hint", comment: "Onboarding topic selection hint") }
        static var topicsSelected: String { L10n.localized("onboarding.topics.selected", comment: "Selected onboarding topic badge") }
        static var topicMusic: String { L10n.localized("onboarding.topic.music", comment: "Music onboarding topic title") }
        static var topicTechnology: String { L10n.localized("onboarding.topic.technology", comment: "Technology onboarding topic title") }
        static var topicHistoryCulture: String { L10n.localized("onboarding.topic.history_culture", comment: "History and culture onboarding topic title") }
        static var topicPoliticsBusiness: String { L10n.localized("onboarding.topic.politics_business", comment: "Politics and business onboarding topic title") }
        static var tutorialTitle: String { L10n.localized("onboarding.tutorial.title", comment: "Onboarding tutorial page title") }
        static var tutorialSubtitle: String { L10n.localized("onboarding.tutorial.subtitle", comment: "Onboarding tutorial page subtitle") }
        static var tutorialThemesTitle: String { L10n.localized("onboarding.tutorial.themes.title", comment: "Onboarding tutorial themes feature title") }
        static var tutorialThemesDetail: String { L10n.localized("onboarding.tutorial.themes.detail", comment: "Onboarding tutorial themes feature detail") }
        static var tutorialAITitle: String { L10n.localized("onboarding.tutorial.ai.title", comment: "Onboarding tutorial AI feature title") }
        static var tutorialAIDetail: String { L10n.localized("onboarding.tutorial.ai.detail", comment: "Onboarding tutorial AI feature detail") }
        static var tutorialStatisticsTitle: String { L10n.localized("onboarding.tutorial.statistics.title", comment: "Onboarding tutorial statistics feature title") }
        static var tutorialStatisticsDetail: String { L10n.localized("onboarding.tutorial.statistics.detail", comment: "Onboarding tutorial statistics feature detail") }

        static func progress(current: Int, total: Int) -> String {
            L10n.formatted(
                "onboarding.progress_format",
                comment: "Onboarding page progress accessibility value",
                current,
                total
            )
        }
    }

    enum Home {
        static var backgroundStyleSwitcher: String { L10n.localized("home.background_style.switcher", comment: "Experimental home background style switcher label") }
        static var chooseTheme: String { L10n.localized("home.choose_theme", comment: "Home screen theme selection title") }
        static var createWithAI: String { L10n.localized("home.create_with_ai", comment: "Create quiz theme with AI button title") }
        static var createWithAIAccessibilityLabel: String { L10n.localized("home.create_with_ai.accessibility_label", comment: "Create quiz theme with AI accessibility label, spelling out the abbreviation for VoiceOver") }
        static var createWithAIAccessibilityHint: String { L10n.localized("home.create_with_ai.accessibility_hint", comment: "Create quiz theme with AI accessibility hint") }
        static var createWithAIBetaBadge: String { L10n.localized("home.create_with_ai.beta_badge", comment: "Create quiz theme with AI beta badge") }
        static var exitAlertMessage: String { L10n.localized("home.exit_alert.message", comment: "Exit confirmation message") }
        static var feelingLucky: String { L10n.localized("home.feeling_lucky", comment: "Feeling lucky random theme button title") }
        static var feelingLuckyAccessibilityHint: String { L10n.localized("home.feeling_lucky.accessibility_hint", comment: "Feeling lucky button accessibility hint") }
        static var feelingLuckyLoading: String { L10n.localized("home.feeling_lucky.loading", comment: "Feeling lucky loading state title") }
        static var moreThemes: String { L10n.localized("home.more_themes", comment: "More themes button title") }
        static var moreThemesAccessibilityHint: String { L10n.localized("home.more_themes.accessibility_hint", comment: "More themes button accessibility hint") }
        static var randomSelection: String { L10n.localized("home.feeling_lucky.random_selection", comment: "Feeling lucky quiz theme title") }
        static var statisticsAccessibilityHint: String { L10n.localized("home.statistics.accessibility_hint", comment: "Home statistics card accessibility hint") }
        static var statisticsAccessibilityLabel: String { L10n.localized("home.statistics.accessibility_label", comment: "Home statistics card accessibility label") }
        static var statisticsAccuracyShort: String { L10n.localized("home.statistics.accuracy_short", comment: "Home statistics card accuracy metric title") }
        static var statisticsDescription: String { L10n.localized("home.statistics.description", comment: "Home statistics card description") }
        static var statisticsPlayedShort: String { L10n.localized("home.statistics.played_short", comment: "Home statistics card played quizzes metric title") }
        static var themesCollectionAccessibilityLabel: String { L10n.localized("home.themes_collection.accessibility_label", comment: "Home themes collection accessibility label") }
        static var unavailableThemes: String { L10n.localized("home.unavailable_themes", comment: "Home screen empty themes title") }

        enum BackgroundStyle {
            static var original: String { L10n.localized("home.background_style.original", comment: "Original mesh gradient background option") }
            static var grid4x4: String { L10n.localized("home.background_style.grid_4x4", comment: "4 by 4 mesh gradient background option") }
            static var grid5x5: String { L10n.localized("home.background_style.grid_5x5", comment: "5 by 5 mesh gradient background option") }
        }

        static var motivationPrompts: [String] {
            [
                L10n.localized("home.motivation_prompt.1", comment: "Home screen random motivation prompt"),
                L10n.localized("home.motivation_prompt.2", comment: "Home screen random motivation prompt"),
                L10n.localized("home.motivation_prompt.3", comment: "Home screen random motivation prompt"),
                L10n.localized("home.motivation_prompt.4", comment: "Home screen random motivation prompt"),
                L10n.localized("home.motivation_prompt.5", comment: "Home screen random motivation prompt"),
                L10n.localized("home.motivation_prompt.6", comment: "Home screen random motivation prompt"),
                L10n.localized("home.motivation_prompt.7", comment: "Home screen random motivation prompt"),
                L10n.localized("home.motivation_prompt.8", comment: "Home screen random motivation prompt"),
                L10n.localized("home.motivation_prompt.9", comment: "Home screen random motivation prompt"),
                L10n.localized("home.motivation_prompt.10", comment: "Home screen random motivation prompt"),
                L10n.localized("home.motivation_prompt.11", comment: "Home screen random motivation prompt"),
                L10n.localized("home.motivation_prompt.12", comment: "Home screen random motivation prompt")
            ]
        }

        static func statisticsAccessibilityValue(playedQuizzes: Int, percentage: Int) -> String {
            L10n.formatted(
                "home.statistics.accessibility_value_format",
                comment: "Home statistics card accessibility value format",
                playedQuizzes,
                percentage
            )
        }
    }

#if DEBUG
    enum DebugMenu {
        static var title: String { L10n.localized("debug_menu.title", comment: "Debug menu screen title") }
        static var interfaceSectionTitle: String { L10n.localized("debug_menu.section.interface", comment: "Debug menu interface section title") }
        static var backendSectionTitle: String { L10n.localized("debug_menu.section.backend", comment: "Debug menu backend section title") }
        static var toolsSectionTitle: String { L10n.localized("debug_menu.section.tools", comment: "Debug menu tools section title") }
        static var hideInterface: String { L10n.localized("debug_menu.hide_interface", comment: "Debug menu hide interface toggle title") }
        static var hideInterfaceSubtitle: String { L10n.localized("debug_menu.hide_interface.subtitle", comment: "Debug menu hide interface toggle subtitle") }
        static var showSubscriptionPromo: String { L10n.localized("debug_menu.show_subscription_promo", comment: "Debug toggle to show the Pro promo button") }
        static var showSubscriptionPromoSubtitle: String { L10n.localized("debug_menu.show_subscription_promo.subtitle", comment: "Debug-only subscription promo visibility") }
        static var subscriptionActive: String { L10n.localized("debug_menu.subscription_active", comment: "Debug menu active subscription toggle title") }
        static var subscriptionActiveSubtitle: String { L10n.localized("debug_menu.subscription_active.subtitle", comment: "Debug menu active subscription toggle subtitle") }
        static var pulse: String { L10n.localized("debug_menu.pulse", comment: "Pulse network console row title") }
        static var pulseSubtitle: String { L10n.localized("debug_menu.pulse.subtitle", comment: "Pulse network console row subtitle") }
    }
#endif

    enum AITheme {
        enum Difficulty {
            static var easy: String { L10n.localized("ai_theme.difficulty.easy", comment: "Easy AI quiz difficulty") }
            static var medium: String { L10n.localized("ai_theme.difficulty.medium", comment: "Medium AI quiz difficulty") }
            static var hard: String { L10n.localized("ai_theme.difficulty.hard", comment: "Hard AI quiz difficulty") }
        }

        enum Progress {
            static var analyzing: String { L10n.localized("ai_theme.progress.analyzing", comment: "AI generation analyzing phase") }
            static var sending: String { L10n.localized("ai_theme.progress.sending", comment: "AI generation sending phase") }
            static var generating: String { L10n.localized("ai_theme.progress.generating", comment: "AI generation composing phase") }
            static var almostReady: String { L10n.localized("ai_theme.progress.almost_ready", comment: "AI generation almost ready phase") }
        }

        enum Error {
            enum Refusal {
                static var title: String { L10n.localized("ai_theme.error.refusal.title", comment: "AI refusal title") }
                static var message: String { L10n.localized("ai_theme.error.refusal.message", comment: "AI refusal message") }
            }

            enum Network {
                static var title: String { L10n.localized("ai_theme.error.network.title", comment: "AI network error title") }
                static var message: String { L10n.localized("ai_theme.error.network.message", comment: "AI network error message") }
            }

            enum Quota {
                static var title: String { L10n.localized("ai_theme.error.quota.title", comment: "Monthly AI quota exhausted") }
                static var message: String { L10n.localized("ai_theme.error.quota.message", comment: "Monthly AI quota reset") }
            }

            enum Service {
                static var title: String { L10n.localized("ai_theme.error.service.title", comment: "AI service error title") }
                static var message: String { L10n.localized("ai_theme.error.service.message", comment: "AI service error message") }
            }

            enum InvalidQuiz {
                static var title: String { L10n.localized("ai_theme.error.invalid_quiz.title", comment: "Invalid generated quiz title") }
                static var message: String { L10n.localized("ai_theme.error.invalid_quiz.message", comment: "Invalid generated quiz message") }
            }

            enum Authentication {
                static var title: String { L10n.localized("ai_theme.error.authentication.title", comment: "AI authentication required title") }
                static var message: String { L10n.localized("ai_theme.error.authentication.message", comment: "AI authentication required message") }
            }

            enum Configuration {
                static var title: String { L10n.localized("ai_theme.error.configuration.title", comment: "AI debug configuration title") }
                static var message: String { L10n.localized("ai_theme.error.configuration.message", comment: "AI debug configuration message") }
            }

            enum Unavailable {
                static var title: String { L10n.localized("ai_theme.error.unavailable.title", comment: "AI unavailable title") }
                static var message: String { L10n.localized("ai_theme.error.unavailable.message", comment: "AI unavailable message") }
            }
        }

        static var difficulty: String { L10n.localized("ai_theme.difficulty", comment: "AI quiz difficulty selector title") }
        static var editTheme: String { L10n.localized("ai_theme.edit_theme", comment: "Edit AI quiz theme action") }
        static var errorMessage: String { L10n.localized("ai_theme.error_message", comment: "AI theme creation error message") }
        static var errorTitle: String { L10n.localized("ai_theme.error_title", comment: "AI theme creation error title") }
        static var generating: String { L10n.localized("ai_theme.generating", comment: "AI generation button title") }
        static var promptPlaceholder: String { L10n.localized("ai_theme.prompt_placeholder", comment: "AI theme prompt placeholder") }
        static func promptTooLong(maximumLength: Int) -> String {
            L10n.formatted(
                "ai_theme.prompt_too_long",
                comment: "AI theme prompt validation message",
                maximumLength
            )
        }
        static var questionCount: String { L10n.localized("ai_theme.question_count", comment: "AI quiz question count selector title") }
        static var retry: String { L10n.localized("ai_theme.retry", comment: "Retry AI generation action") }
        static var submit: String { L10n.localized("ai_theme.submit", comment: "AI theme creation submit button title") }
        static var subtitle: String { L10n.localized("ai_theme.subtitle", comment: "AI theme creation subtitle") }
        static var title: String { L10n.localized("ai_theme.title", comment: "AI theme creation screen title") }

        static func questionCountAccessibility(count: Int) -> String {
            L10n.formatted(
                "ai_theme.question_count.accessibility_format",
                comment: "AI quiz question count accessibility label",
                count
            )
        }
    }

    enum Question {
        static var answeredCorrect: String { L10n.localized("question.answered.correct", comment: "VoiceOver announcement after a correct answer") }
        static var answeredWrongUnknown: String { L10n.localized("question.answered.wrong_unknown", comment: "VoiceOver announcement after a wrong answer when the correct option cannot be resolved") }
        static var audioLoadFailure: String { L10n.localized("question.audio_load_failure", comment: "Console message when answer sounds fail to load") }
        static var exitAlertMessage: String { L10n.localized("question.exit_alert.message", comment: "Message shown before discarding current quiz progress") }
        static var exitAlertTitle: String { L10n.localized("question.exit_alert.title", comment: "Title shown before discarding current quiz progress") }
        static var fallbackTheme: String { L10n.localized("question.fallback_theme", comment: "Fallback quiz theme name") }
        static var showExplanation: String { L10n.localized("question.show_explanation", comment: "Show the answer explanation on the back of the question card") }
        static var showQuestion: String { L10n.localized("question.show_question", comment: "Return to the question side of the card") }
        static var tapToAnswer: String { L10n.localized("question.tap_to_answer.accessibility_hint", comment: "Accessibility hint for a quiz answer button") }
        static var timeRemaining: String { L10n.localized("question.time_remaining", comment: "Quiz timer accessibility label") }
        static var unavailableAnswer: String { L10n.localized("question.unavailable_answer", comment: "Unavailable answer placeholder") }
        static var unavailableMessage: String { L10n.localized("question.unavailable.message", comment: "Message when selected theme has no usable questions") }
        static var loadingFailedTitle: String { L10n.localized("question.loading_failed.title", comment: "Question loading failure alert title") }
        static var loadingFailedMessage: String { L10n.localized("question.loading_failed.message", comment: "Question loading failure retry guidance") }
        static var networkFailureMessage: String { L10n.localized("question.network_failure.message", comment: "Question loading failure when internet access is unavailable") }
        static var insufficientQuestionsMessage: String { L10n.localized("question.insufficient.message", comment: "Fewer than five questions remain") }
        static var progressCompleteMessage: String { L10n.localized("question.progress_complete.message", comment: "Message when repeat filtering leaves no questions") }
        static var unavailableNumber: String { L10n.localized("question.unavailable_number", comment: "Unavailable question number label") }

        static func number(_ number: Int) -> String {
            L10n.formatted("question.number_format", comment: "Question number format", number)
        }

        static func answeredWrong(correctAnswer: String) -> String {
            L10n.formatted("question.answered.wrong_format", comment: "VoiceOver announcement after a wrong answer with the correct option", correctAnswer)
        }

        static func loadAnnouncement(number: String, question: String) -> String {
            L10n.formatted("question.load.announcement_format", comment: "VoiceOver announcement posted when a new question appears", number, question)
        }
    }

    enum Result {
        static var fallbackDescription: String { L10n.localized("result.description.fallback", comment: "Fallback result description") }
        static var strongResultDescription: String { L10n.localized("result.description.high_score", comment: "Result description for strong results") }
        static var invalidScoreDescription: String { L10n.localized("result.description.invalid_score", comment: "Result description for invalid score state") }
        static var lowScoreDescription: String { L10n.localized("result.description.low_score", comment: "Result description for low scores") }
        static var mediumLowScoreDescription: String { L10n.localized("result.description.medium_low_score", comment: "Result description for medium-low scores") }
        static var mediumScoreDescription: String { L10n.localized("result.description.medium_score", comment: "Result description for medium scores") }
        static var noQuestionsDescription: String { L10n.localized("result.description.no_questions", comment: "Result description for attempts without questions") }
        static var perfectScoreDescription: String { L10n.localized("result.description.perfect_score", comment: "Result description for perfect scores") }
        static var playAgain: String { L10n.localized("result.play_again", comment: "Replay current quiz button title") }
        static var toThemes: String { L10n.localized("result.to_themes", comment: "Return to quiz themes button title") }
        static var veryLowScoreDescription: String { L10n.localized("result.description.very_low_score", comment: "Result description for very low scores") }

        static func text(correctAnswers: Int, totalQuestions: Int) -> String {
            L10n.formatted("result.text_format", comment: "Quiz result title format", correctAnswers, totalQuestions)
        }

        static func announcement(correctAnswers: Int, totalQuestions: Int) -> String {
            L10n.formatted("result.announcement_format", comment: "VoiceOver announcement of the final quiz score", correctAnswers, totalQuestions)
        }
    }

    enum Subscription {
        static var aiCardAccessibilityHint: String { L10n.localized("subscription.ai_card.accessibility_hint", comment: "AI creation card Plus promo accessibility hint") }
        static var aiCardSubtitle: String { L10n.localized("subscription.ai_card.subtitle", comment: "AI creation card Plus promo subtitle") }
        static var aiCardTitle: String { L10n.localized("subscription.ai_card.title", comment: "AI creation card Plus promo title") }
        static var close: String { L10n.localized("subscription.paywall.close", comment: "Subscription paywall close button accessibility label") }
        static var eyebrow: String { L10n.localized("subscription.paywall.eyebrow", comment: "Subscription paywall eyebrow") }
        static var flexibilityBenefitSubtitle: String { L10n.localized("subscription.paywall.benefit.flexibility.subtitle", comment: "Subscription flexibility benefit subtitle") }
        static var flexibilityBenefitTitle: String { L10n.localized("subscription.paywall.benefit.flexibility.title", comment: "Subscription flexibility benefit title") }
        static var free: String { L10n.localized("subscription.paywall.free", comment: "Free tier label") }
        static var freeBadge: String { L10n.localized("subscription.badge.free", comment: "Free AI question limit badge") }
        static var homeAccessibilityHint: String { L10n.localized("subscription.home.accessibility_hint", comment: "Home Plus banner accessibility hint") }
        static var homePriceBadge: String { L10n.localized("subscription.home.price_badge", comment: "Home Plus banner preview price badge") }
        static var homeSubtitle: String { L10n.localized("subscription.home.subtitle", comment: "Home Plus banner subtitle") }
        static var homeTitle: String { L10n.localized("subscription.home.title", comment: "Home Plus banner title") }
        static var legal: String { L10n.localized("subscription.paywall.legal", comment: "Subscription preview legal note") }
        static var limitBenefitSubtitle: String { L10n.localized("subscription.paywall.benefit.limit.subtitle", comment: "Subscription AI limit benefit subtitle") }
        static var limitBenefitTitle: String { L10n.localized("subscription.paywall.benefit.limit.title", comment: "Subscription AI limit benefit title") }
        static var multiplier: String { L10n.localized("subscription.paywall.multiplier", comment: "Subscription question limit multiplier") }
        static var planNote: String { L10n.localized("subscription.paywall.plan.note", comment: "Subscription plan note") }
        static var planTitle: String { L10n.localized("subscription.paywall.plan.title", comment: "Subscription plan title") }
        static var plus: String { L10n.localized("subscription.paywall.plus", comment: "Plus tier label") }
        static var generationLimit: String { L10n.localized("subscription.paywall.questions", comment: "Monthly AI generation limit metric label") }
        static var restore: String { L10n.localized("subscription.paywall.restore", comment: "Restore purchases button title") }
        static var subtitle: String { L10n.localized("subscription.paywall.subtitle", comment: "Subscription paywall subtitle") }
        static var title: String { L10n.localized("subscription.paywall.title", comment: "Subscription paywall title") }

        enum ComingSoon {
            static var action: String { L10n.localized("subscription.paywall.coming_soon.action", comment: "Subscription preview alert action") }
            static var message: String { L10n.localized("subscription.paywall.coming_soon.message", comment: "Subscription preview alert message") }
            static var title: String { L10n.localized("subscription.paywall.coming_soon.title", comment: "Subscription preview alert title") }
        }

        static func pricePerMonth(_ price: String) -> String {
            L10n.formatted(
                "subscription.paywall.price_format",
                comment: "Subscription monthly price format",
                price
            )
        }

        static func subscribeCTA(_ price: String) -> String {
            L10n.formatted(
                "subscription.paywall.cta_format",
                comment: "Subscription primary CTA format",
                price
            )
        }
    }

    enum Settings {
        static var alertAction: String { L10n.localized("settings.alert.action", comment: "Default settings alert action title") }
        static var appearanceSectionTitle: String { L10n.localized("settings.section.appearance", comment: "Settings appearance section title") }
        static var close: String { L10n.localized("settings.close", comment: "Settings close button title") }
        static var feedback: String { L10n.localized("settings.feedback", comment: "Settings feedback row title") }
        static var feedbackSubtitle: String { L10n.localized("settings.feedback.subtitle", comment: "Settings feedback row subtitle") }
        static var feedbackUnavailableMessage: String { L10n.localized("settings.feedback.unavailable_message", comment: "Settings feedback unavailable alert message") }
        static var done: String { L10n.localized("settings.done", comment: "Settings done button title") }
        static var icon: String { L10n.localized("settings.icon", comment: "Settings app icon row title") }
        static var iconSubtitle: String { L10n.localized("settings.icon.subtitle", comment: "Settings app icon row subtitle") }
        static var language: String { L10n.localized("settings.language", comment: "Settings app language row title") }
        static var languageSubtitle: String { L10n.localized("settings.language.subtitle", comment: "Settings app language row subtitle") }
        static var profile: String { L10n.localized("settings.profile", comment: "Settings profile row title") }
        static var profileSectionTitle: String { L10n.localized("settings.section.profile", comment: "Settings profile section title") }
        static var profileSubtitle: String { L10n.localized("settings.profile.subtitle", comment: "Settings profile row subtitle") }
        static var profileUnavailableMessage: String { L10n.localized("settings.profile.unavailable_message", comment: "Settings profile unavailable alert message") }
        static var privacyPolicy: String { L10n.localized("settings.privacy_policy", comment: "Privacy policy link title") }
        static var privacyPolicySubtitle: String { L10n.localized("settings.privacy_policy.subtitle", comment: "Privacy policy link subtitle") }
        static var privacyUnavailableTitle: String { L10n.localized("settings.privacy_policy.unavailable.title", comment: "Privacy policy link could not open title") }
        static var privacyUnavailableMessage: String { L10n.localized("settings.privacy_policy.unavailable.message", comment: "Privacy policy link could not open message") }
        static var restartRequiredTitle: String { L10n.localized("settings.restart_required.title", comment: "Settings restart required alert title") }
        static var supportSectionTitle: String { L10n.localized("settings.section.support", comment: "Settings support section title") }
        static var design: String { L10n.localized("settings.design", comment: "Settings design row title") }
        static var designSubtitle: String { L10n.localized("settings.design.subtitle", comment: "Settings design row subtitle") }
        static var cleanThemeMode: String { L10n.localized("settings.clean_theme_mode", comment: "Settings clean theme mode row title") }
        static var cleanThemeModeSubtitle: String { L10n.localized("settings.clean_theme_mode.subtitle", comment: "Settings clean theme mode row subtitle") }
        static var theme: String { L10n.localized("settings.theme", comment: "Settings theme row title") }
        static var themeSubtitle: String { L10n.localized("settings.theme.subtitle", comment: "Settings theme row subtitle") }
        static var title: String { L10n.localized("settings.title", comment: "Settings screen title") }
#if DEBUG
        static var developerSectionTitle: String { L10n.localized("settings.section.developer", comment: "Debug settings developer section title") }
        static var localhostBackend: String { L10n.localized("settings.backend.localhost", comment: "Debug localhost backend toggle title") }
        static var localhostBackendSubtitle: String { L10n.localized("settings.backend.localhost.subtitle", comment: "Debug localhost backend toggle subtitle") }
        static var localContentOnly: String { L10n.localized("settings.backend.local_content_only", comment: "Debug local content only toggle title") }
        static var localContentOnlySubtitle: String { L10n.localized("settings.backend.local_content_only.subtitle", comment: "Debug local content only toggle subtitle") }
        static var directAI: String { L10n.localized("settings.ai.direct", comment: "Debug direct AI toggle title") }
        static var directAISubtitle: String { L10n.localized("settings.ai.direct.subtitle", comment: "Debug direct AI toggle subtitle") }
#endif

        static func restartRequiredMessage(selection: String) -> String {
            L10n.formatted("settings.restart_required.message_format", comment: "Settings restart required alert message format", selection)
        }

        enum Account {
            static var delete: String { L10n.localized("settings.account.delete", comment: "Delete account action") }
            static var deleteSubtitle: String { L10n.localized("settings.account.delete.subtitle", comment: "Delete account row description") }
            static var deleting: String { L10n.localized("settings.account.deleting", comment: "Account deletion in progress") }
            static var deleteConfirmationTitle: String { L10n.localized("settings.account.delete.confirm.title", comment: "Account deletion confirmation title") }
            static var deleteConfirmationMessage: String { L10n.localized("settings.account.delete.confirm.message", comment: "Account deletion consequences") }
            static var deletedTitle: String { L10n.localized("settings.account.deleted.title", comment: "Account deletion succeeded title") }
            static var deletedMessage: String { L10n.localized("settings.account.deleted.message", comment: "Account deletion succeeded message") }
            static var deletionFailedTitle: String { L10n.localized("settings.account.delete.failed.title", comment: "Account deletion failed title") }
            static var deletionFailedMessage: String { L10n.localized("settings.account.delete.failed.message", comment: "Account deletion failed retry guidance") }
            static var cleanupRequiredTitle: String { L10n.localized("settings.account.cleanup.title", comment: "Local account cleanup required title") }
            static var cleanupRequiredMessage: String { L10n.localized("settings.account.cleanup.message", comment: "Server account deleted but local cleanup needs retry") }
            static var sessionExpiredTitle: String { L10n.localized("settings.account.session_expired.title", comment: "Account deletion session expired title") }
            static var sessionExpiredMessage: String { L10n.localized("settings.account.session_expired.message", comment: "Account deletion session expired explanation") }
            static var create: String { L10n.localized("settings.account.create", comment: "Explicitly create a new account action") }
            static var createSubtitle: String { L10n.localized("settings.account.create.subtitle", comment: "Create a new account row description") }
            static var creating: String { L10n.localized("settings.account.creating", comment: "Account creation in progress") }
            static var createConfirmationTitle: String { L10n.localized("settings.account.create.confirm.title", comment: "New account confirmation title") }
            static var createConfirmationMessage: String { L10n.localized("settings.account.create.confirm.message", comment: "New account does not restore deleted data") }
            static var createdTitle: String { L10n.localized("settings.account.created.title", comment: "New account creation succeeded title") }
            static var createdMessage: String { L10n.localized("settings.account.created.message", comment: "New account creation succeeded message") }
            static var creationFailedTitle: String { L10n.localized("settings.account.create.failed.title", comment: "New account creation failed title") }
            static var creationFailedMessage: String { L10n.localized("settings.account.create.failed.message", comment: "New account creation failed message") }
            static var unavailableTitle: String { L10n.localized("settings.account.unavailable.title", comment: "Account management unavailable title") }
            static var unavailableMessage: String { L10n.localized("settings.account.unavailable.message", comment: "No connected Quizice account available") }
            static var cancel: String { L10n.localized("settings.account.cancel", comment: "Cancel account operation") }
            static var retry: String { L10n.localized("settings.account.retry", comment: "Retry account operation") }
        }

        enum Icon {
            static var classic: String { L10n.localized("settings.icon.classic", comment: "Classic app icon option title") }
            static var dark: String { L10n.localized("settings.icon.dark", comment: "Dark app icon option title") }
            static var ice: String { L10n.localized("settings.icon.ice", comment: "Ice app icon option title") }
        }

        enum Theme {
            static var dark: String { L10n.localized("settings.theme.dark", comment: "Dark app theme option title") }
            static var light: String { L10n.localized("settings.theme.light", comment: "Light app theme option title") }
            static var system: String { L10n.localized("settings.theme.system", comment: "System app theme option title") }
        }

        enum Language {
            static var system: String { L10n.localized("settings.language.system", comment: "System app language option title") }
        }

        enum QuestionStrategy {
            static var unavailableMessage: String { L10n.localized("settings.questionStrategy.unavailable", comment: "Personalized repeat filters require a backend account and catalog") }
            static var section: String { L10n.localized("settings.questionStrategy.section", comment: "Settings question strategy section title") }
            static var title: String { L10n.localized("settings.questionStrategy.title", comment: "Settings question repeat strategy row title") }
            static var helpTitle: String { L10n.localized("settings.questionStrategy.help.title", comment: "Question repeat strategy help title") }
            static var helpMessage: String { L10n.localized("settings.questionStrategy.help.message", comment: "Question repeat strategy help message") }
            static var helpAccessibilityLabel: String { L10n.localized("settings.questionStrategy.help.accessibilityLabel", comment: "Question repeat strategy help button accessibility label") }

            static func title(for strategy: QuestionRepeatStrategy) -> String {
                L10n.localized(
                    "settings.questionStrategy.\(strategy.rawValue)",
                    comment: "Question repeat strategy option title"
                )
            }
        }

        enum Design {
            static var classic: String { L10n.localized("settings.design.classic", comment: "Classic design option title") }
            static var clean: String { L10n.localized("settings.design.clean", comment: "Clean design option title") }
            static var radar: String { L10n.localized("settings.design.radar", comment: "Radar design option title") }
        }
    }

    enum Statistics {
        static var historyLoading: String { L10n.localized("statistics.history.loading", comment: "Statistics history loading") }
        static var historyError: String { L10n.localized("statistics.history.error", comment: "Statistics history error") }
        static var historyRetry: String { L10n.localized("statistics.history.retry", comment: "Statistics history retry") }
        static var historyUndated: String { L10n.localized("statistics.history.undated", comment: "Statistics history undated") }
        static var historyTitle: String { L10n.localized("statistics.history.title", comment: "Daily statistics charts section title") }
        static var historyEmpty: String { L10n.localized("statistics.history.empty", comment: "No dated games in the selected period") }
        static var dailyAccuracy: String { L10n.localized("statistics.history.accuracy", comment: "Daily answer accuracy chart title") }
        static var dailyGames: String { L10n.localized("statistics.history.games", comment: "Daily completed games chart title") }
        static var day: String { L10n.localized("statistics.history.day", comment: "Statistics date axis label") }
        static var period: String { L10n.localized("statistics.period.title", comment: "Statistics period picker label") }
        static var periodWeek: String { L10n.localized("statistics.period.week", comment: "Last seven calendar days") }
        static var periodMonth: String { L10n.localized("statistics.period.month", comment: "Last thirty calendar days") }
        static var periodAllTime: String { L10n.localized("statistics.period.all_time", comment: "All recorded history") }
        static var accessibilityLabel: String { L10n.localized("statistics.accessibility_label", comment: "Expanded statistics card accessibility label") }
        static var bestResult: String { L10n.localized("statistics.best_result", comment: "Best result row title") }
        static var correctAnswers: String { L10n.localized("statistics.correct_answers", comment: "Correct answers row title") }
        static var emptyStateText: String { L10n.localized("statistics.empty_state.text", comment: "Statistics empty state text") }
        static var percentage: String { L10n.localized("statistics.percentage", comment: "Correct answers percentage row title") }
        static var playedQuizzes: String { L10n.localized("statistics.played_quizzes", comment: "Played quizzes row title") }
        static var subtitleEmpty: String { L10n.localized("statistics.subtitle.empty", comment: "Statistics subtitle when there are no attempts") }
        static var subtitleWithStats: String { L10n.localized("statistics.subtitle.with_stats", comment: "Statistics subtitle when attempts exist") }
        static var title: String { L10n.localized("statistics.title", comment: "Statistics card title") }
    }

    enum ThemeCard {
        static var country: String { L10n.localized("theme_card.country", comment: "Country for this quiz round") }
        static var internationalQuestions: String { L10n.localized("theme_card.international_questions", comment: "Questions without a country filter") }
        static var accessibilityHint: String { L10n.localized("theme.card.accessibility_hint", comment: "Theme card accessibility hint") }
        static var closeAccessibilityLabel: String { L10n.localized("theme.card.close_accessibility_label", comment: "Expanded theme card close button accessibility label") }
        static var defaultThemeDescription: String { L10n.localized("description.default_theme_description", comment: "Default theme description fallback") }
        static var questionCount: String { L10n.localized("description.question_count", comment: "Question count picker caption") }
        static var showDescriptionAccessibilityLabel: String { L10n.localized("theme.card.show_description_accessibility_label", comment: "Expanded theme card show-description accessibility label") }
        static var showFrontAccessibilityLabel: String { L10n.localized("theme.card.show_front_accessibility_label", comment: "Expanded theme card return-to-front accessibility label") }

        static func accessibilityLabel(themeName: String) -> String {
            L10n.formatted("theme.card.accessibility_label_format", comment: "Theme card accessibility label format", themeName)
        }
    }
}
