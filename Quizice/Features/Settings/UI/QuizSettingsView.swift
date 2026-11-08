import SwiftUI

private enum Layout {
    static let contentHorizontalInset: CGFloat = 20
    static let contentTopInset: CGFloat = 28
    static let contentMinimumTopInset: CGFloat = 46
    static let contentBottomInset: CGFloat = 24
    static let titleRowSpacing: CGFloat = 14
    static let titleBottomSpacing: CGFloat = 10
    static let doneButtonHorizontalInset: CGFloat = 16
    static let doneButtonVerticalInset: CGFloat = 9
    static let sectionSpacing: CGFloat = 16
    static let sectionTitleHorizontalInset: CGFloat = 2
    static let sectionContentSpacing: CGFloat = 14
    static let sectionContentPadding: CGFloat = 16
    static let rowSpacing: CGFloat = 12
    static let rowAccessorySpacing: CGFloat = 6
    static let rowAccessoryMinimumSpacing: CGFloat = 12
    static let rowIconSize: CGFloat = 36
    static let rowTextSpacing: CGFloat = 3
    static let rowValueMinimumScaleFactor: CGFloat = 0.72
    static let stackedValueTopSpacing: CGFloat = 12
    static let stackedValueInset: CGFloat = 12
    static let stackedValueLeadingInset: CGFloat = rowIconSize + rowSpacing
    static let iconChoicesSpacing: CGFloat = 10
    static let iconChoiceContentSpacing: CGFloat = 8
    static let iconChoiceImageSize: CGFloat = 48
    static let iconChoiceTextMinimumScaleFactor: CGFloat = 0.82
}

struct QuizSettingsView: View {
    enum AccessibilityID {
        static let deleteAccount = "settingsDeleteAccount"
        static let createAccount = "settingsCreateAccount"
        static let accountUnavailable = "settingsAccountUnavailable"
        static let privacyPolicy = "settingsPrivacyPolicy"
    }

    private enum AppIcon: String, CaseIterable, Identifiable {
        case classic
        case dark
        case ice

        var id: String { rawValue }

        var title: String {
            switch self {
            case .classic: return L10n.Settings.Icon.classic
            case .dark: return L10n.Settings.Icon.dark
            case .ice: return L10n.Settings.Icon.ice
            }
        }

        var systemImage: String {
            switch self {
            case .classic: return "sparkles"
            case .dark: return "moon.stars.fill"
            case .ice: return "snowflake"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppAppearanceStore.Keys.cleanColorScheme) private var selectedThemeID = CleanColorSchemePreference.system.rawValue
    @AppStorage(AppAppearanceStore.Keys.designStyle) private var selectedDesignStyleID = AppDesignStyle.defaultStyle.rawValue
    @AppStorage(AppAppearanceStore.Keys.backgroundStyle) private var selectedBackgroundStyleID = AppBackgroundStyle.defaultStyle.rawValue
    @AppStorage(AppLocalizationStore.Keys.language) private var selectedLanguageID = AppLanguagePreference.system.rawValue
    @AppStorage("quizice.settings.icon") private var selectedIconID = AppIcon.classic.rawValue
    @AppStorage(QuestionRepeatStrategyStore.defaultsKey) private var repeatStrategyID = QuestionRepeatStrategy.showAll.rawValue
    @State var activeAlert: SettingsAlert?
    @State private var showsQuestionStrategyHelp = false
    @State private var didTrackScreen = false
    @State var allowsPersonalizedRepeats: Bool
    @StateObject var account: SettingsAccountModel
    let analytics: AnalyticsTracking
    let personalizedRepeatsAvailable: () -> Bool
    let onAccountDeleted: () -> Void

    init(
        analytics: AnalyticsTracking = AppMetricaAnalyticsTracker.shared,
        accountManager: (any AccountManaging)? = nil,
        onAccountDeleted: @escaping () -> Void = {},
        personalizedRepeatsAvailable: @escaping () -> Bool = {
            ThemeCatalogRepository.shared.catalogOrigin == .backend
                && StoredBackendAccessTokenProvider().validAccessToken() != nil
        }
    ) {
        self.analytics = analytics
        self.onAccountDeleted = onAccountDeleted
        self.personalizedRepeatsAvailable = personalizedRepeatsAvailable
        _allowsPersonalizedRepeats = State(initialValue: personalizedRepeatsAvailable())
        _account = StateObject(wrappedValue: SettingsAccountModel(manager: accountManager))
    }

    private var selectedTheme: CleanColorSchemePreference {
        CleanColorSchemePreference(rawValue: selectedThemeID) ?? .system
    }

    private var selectedDesignStyle: AppDesignStyle {
        guard
            let style = AppDesignStyle(rawValue: selectedDesignStyleID),
            style.isSelectable
        else { return AppDesignStyle.defaultStyle }
        return style
    }

    private var selectedLanguage: AppLanguagePreference {
        AppLanguagePreference(rawValue: selectedLanguageID) ?? .system
    }

    private var selectedBackgroundStyle: AppBackgroundStyle {
        AppBackgroundStyle(rawValue: selectedBackgroundStyleID) ?? .defaultStyle
    }

    private var selectedIcon: AppIcon {
        AppIcon(rawValue: selectedIconID) ?? .classic
    }

    var appearance: AppAppearance {
        let traitCollection = UITraitCollection(userInterfaceStyle: selectedTheme.traitUserInterfaceStyle(fallback: colorScheme))
        return AppAppearance(
            designStyle: selectedDesignStyle,
            cleanColorSchemePreference: selectedTheme,
            backgroundStyle: selectedBackgroundStyle,
            traitCollection: traitCollection
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                settingsBackground

                ScrollView {
                    content(topInset: max(Layout.contentMinimumTopInset, geometry.safeAreaInsets.top + Layout.contentTopInset))
                }

                if showsQuestionStrategyHelp {
                    questionStrategyHelpOverlay
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
        }
        .environment(\.appAppearance, appearance)
        .preferredColorScheme(appearance.swiftUIColorScheme)
        .tint(Color(uiColor: appearance.screenTextColor))
        .interactiveDismissDisabled(account.isBusy)
        .alert(item: $activeAlert, content: makeAlert)
        .onReceive(NotificationCenter.default.publisher(for: .backendAuthenticationEstablished)) { _ in
            allowsPersonalizedRepeats = personalizedRepeatsAvailable()
            account.refreshAvailability()
        }
        .onReceive(NotificationCenter.default.publisher(for: .backendAuthenticationInvalidated)) { _ in
            allowsPersonalizedRepeats = false
            account.refreshAvailability()
        }
        .onReceive(NotificationCenter.default.publisher(for: .backendAccountDeleted)) { _ in
            allowsPersonalizedRepeats = false
            account.refreshAvailability()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            allowsPersonalizedRepeats = personalizedRepeatsAvailable()
            account.refreshAvailability()
        }
        .onAppear {
            allowsPersonalizedRepeats = personalizedRepeatsAvailable()
            account.refreshAvailability()
            guard !didTrackScreen else { return }
            didTrackScreen = true
            analytics.track(.screenView(screen: .settings))
        }
    }

    @ViewBuilder
    private var settingsBackground: some View {
        if appearance.designStyle == .classic {
            AppBackgroundView(
                appearance: appearance,
                motionProfile: .edgeAware
            )
        } else {
            Color(uiColor: appearance.backgroundColor)
                .ignoresSafeArea()
        }
    }

    private func content(topInset: CGFloat) -> some View {
        VStack(spacing: Layout.sectionSpacing) {
            settingsTitle
            questionStrategySection
            appearanceSection
            supportSection
            profileSection
        }
        .padding(.horizontal, Layout.contentHorizontalInset)
        .padding(.top, topInset)
        .padding(.bottom, Layout.contentBottomInset)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private var settingsTitle: some View {
        HStack(spacing: Layout.titleRowSpacing) {
            Text(L10n.Settings.title)
                .font(appearance.typography.swiftUIFont(size: 38, weight: .bold))
                .foregroundStyle(Color(uiColor: appearance.screenTextColor))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                dismiss()
            } label: {
                Text(L10n.Settings.done)
                    .font(appearance.typography.swiftUIFont(size: 15, weight: .semibold))
                    .foregroundStyle(Color(uiColor: appearance.screenTextColor))
                    .padding(.horizontal, Layout.doneButtonHorizontalInset)
                    .padding(.vertical, Layout.doneButtonVerticalInset)
                    .background(
                        Color(uiColor: appearance.iconButton.backgroundColor),
                        in: RoundedRectangle(cornerRadius: appearance.iconButton.cornerRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: appearance.iconButton.cornerRadius, style: .continuous)
                            .stroke(Color(uiColor: appearance.iconButton.borderColor), lineWidth: appearance.iconButton.borderWidth)
                    )
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(QuizPressButtonStyle())
            .disabled(account.isBusy)
        }
            .padding(.bottom, Layout.titleBottomSpacing)
    }

    private var questionStrategySection: some View {
        SettingsSection(
            title: L10n.Settings.QuestionStrategy.section,
            titleAccessory: {
                Button(action: presentQuestionStrategyHelp) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(appearance.typography.swiftUIFont(size: 14, weight: .semibold))
                        .foregroundStyle(Color(uiColor: appearance.secondaryScreenTextColor))
                        .frame(width: 44, height: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(QuizPressButtonStyle())
                .accessibilityLabel(L10n.Settings.QuestionStrategy.helpAccessibilityLabel)
            },
            content: {
                if allowsPersonalizedRepeats {
                    Menu {
                        ForEach(QuestionRepeatStrategy.allCases, id: \.rawValue) { strategy in
                            Button(L10n.Settings.QuestionStrategy.title(for: strategy)) {
                                repeatStrategyID = strategy.rawValue
                            }
                        }
                    } label: {
                        SettingsValueRow(
                            systemImage: "arrow.triangle.2.circlepath",
                            title: L10n.Settings.QuestionStrategy.title, subtitle: "",
                            value: L10n.Settings.QuestionStrategy.title(for: QuestionRepeatStrategy(rawValue: repeatStrategyID) ?? .showAll)
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(alignment: .leading, spacing: Layout.rowSpacing) {
                        SettingsRowHeader(systemImage: "arrow.triangle.2.circlepath",
                            title: L10n.Settings.QuestionStrategy.title, subtitle: L10n.Settings.QuestionStrategy.title(for: .showAll))
                        Text(L10n.Settings.QuestionStrategy.unavailableMessage)
                            .font(appearance.typography.swiftUIFont(size: 13, weight: .regular))
                            .foregroundStyle(Color(uiColor: appearance.secondarySurfaceTextColor))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        )
    }

    private var questionStrategyHelpOverlay: some View {
        QuizAlertOverlay(
            title: L10n.Settings.QuestionStrategy.helpTitle,
            message: L10n.Settings.QuestionStrategy.helpMessage,
            systemImage: "arrow.triangle.2.circlepath",
            iconColor: .white,
            primaryAction: QuizAlertAction(
                title: L10n.Settings.alertAction,
                emphasis: .primary,
                accessibilityIdentifier: "questionStrategyHelpDismissButton",
                action: dismissQuestionStrategyHelp
            ),
            secondaryAction: nil,
            onEscape: dismissQuestionStrategyHelp
        )
        .environment(\.appAppearance, questionStrategyHelpAppearance)
        .preferredColorScheme(.dark)
    }

    private var questionStrategyHelpAppearance: AppAppearance {
        AppAppearance(
            designStyle: appearance.designStyle,
            cleanColorSchemePreference: .dark,
            backgroundStyle: appearance.backgroundStyle,
            traitCollection: UITraitCollection(userInterfaceStyle: .dark)
        )
    }

    private func presentQuestionStrategyHelp() {
        setQuestionStrategyHelpPresented(true, duration: 0.18)
    }

    private func dismissQuestionStrategyHelp() {
        setQuestionStrategyHelpPresented(false, duration: 0.16)
    }

    private func setQuestionStrategyHelpPresented(_ isPresented: Bool, duration: Double) {
        if reduceMotion {
            showsQuestionStrategyHelp = isPresented
        } else {
            withAnimation(.easeOut(duration: duration)) {
                showsQuestionStrategyHelp = isPresented
            }
        }
    }

    private var appearanceSection: some View {
        SettingsSection(title: L10n.Settings.appearanceSectionTitle) {
            Menu {
                ForEach(AppDesignStyle.settingsOrder) { designStyle in
                    Button(designStyle.title) {
                        let oldValue = selectedDesignStyleID
                        selectedDesignStyleID = designStyle.rawValue
                        AppAppearanceStore.shared.notifyChange()
                        trackSettingChange(setting: .design, oldValue: oldValue, newValue: designStyle.rawValue)
                    }
                    .disabled(!designStyle.isSelectable)
                }
            } label: {
                SettingsValueRow(
                    systemImage: "paintpalette.fill",
                    title: L10n.Settings.design,
                    subtitle: L10n.Settings.designSubtitle,
                    value: selectedDesignStyle.title
                )
            }
            .buttonStyle(.plain)

            Divider()
                .background(Color(uiColor: appearance.card.borderColor))

            Menu {
                ForEach(AppLanguagePreference.allCases) { language in
                    Button(language.title) {
                        let oldValue = selectedLanguageID
                        AppLocalizationStore.shared.languagePreference = language
                        trackSettingChange(setting: .language, oldValue: oldValue, newValue: language.rawValue)
                    }
                }
            } label: {
                SettingsValueRow(
                    systemImage: "globe",
                    title: L10n.Settings.language,
                    subtitle: L10n.Settings.languageSubtitle,
                    value: selectedLanguage.title
                )
            }
            .buttonStyle(.plain)

            if selectedDesignStyle == .clean {
                Divider()
                    .background(Color(uiColor: appearance.card.borderColor))

                Menu {
                    ForEach(CleanColorSchemePreference.allCases) { theme in
                        Button(theme.title) {
                            let oldValue = selectedThemeID
                            selectedThemeID = theme.rawValue
                            AppAppearanceStore.shared.notifyChange()
                            trackSettingChange(setting: .theme, oldValue: oldValue, newValue: theme.rawValue)
                        }
                    }
                } label: {
                    SettingsValueRow(
                        systemImage: "circle.lefthalf.filled",
                        title: L10n.Settings.cleanThemeMode,
                        subtitle: L10n.Settings.cleanThemeModeSubtitle,
                        value: selectedTheme.title
                    )
                }
                .buttonStyle(.plain)
            }

            Divider()
                .background(Color(uiColor: appearance.card.borderColor))

            VStack(alignment: .leading, spacing: Layout.rowSpacing) {
                SettingsRowHeader(
                    systemImage: "app.fill",
                    title: L10n.Settings.icon,
                    subtitle: L10n.Settings.iconSubtitle
                )

                HStack(spacing: Layout.iconChoicesSpacing) {
                    ForEach(AppIcon.allCases) { icon in
                        let isEnabled = icon == .classic && selectedIcon != icon
                        IconChoiceButton(
                            title: icon.title,
                            systemImage: icon.systemImage,
                            isSelected: selectedIcon == icon,
                            isEnabled: isEnabled
                        ) {
                            let oldValue = selectedIconID
                            selectedIconID = icon.rawValue
                            trackSettingChange(setting: .icon, oldValue: oldValue, newValue: icon.rawValue)
                            activeAlert = .restart(icon.title)
                        }
                    }
                }
            }
        }
    }

    private func trackSettingChange(setting: AnalyticsSetting, oldValue: String, newValue: String) {
        guard oldValue != newValue else { return }
        analytics.track(.settingChanged(setting: setting, oldValue: oldValue, newValue: newValue))
    }
}

struct SettingsSection<Content: View>: View {
    @Environment(\.appAppearance) private var appearance

    let title: String
    private let titleAccessory: AnyView?
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        titleAccessory = nil
        self.content = content()
    }

    init<TitleAccessory: View>(
        title: String,
        @ViewBuilder titleAccessory: () -> TitleAccessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.titleAccessory = AnyView(titleAccessory())
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.rowSpacing) {
            HStack(spacing: Layout.rowAccessorySpacing) {
                Text(title)
                    .font(appearance.typography.swiftUIFont(size: 13, weight: .semibold))
                    .foregroundStyle(Color(uiColor: appearance.secondaryScreenTextColor))
                    .textCase(.uppercase)

                if let titleAccessory {
                    titleAccessory
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Layout.sectionTitleHorizontalInset)

            VStack(spacing: Layout.sectionContentSpacing) {
                content
            }
            .padding(Layout.sectionContentPadding)
            .background(
                Color(uiColor: appearance.card.backgroundColor),
                in: RoundedRectangle(cornerRadius: appearance.card.cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: appearance.card.cornerRadius, style: .continuous)
                    .stroke(Color(uiColor: appearance.card.borderColor), lineWidth: appearance.card.borderWidth)
            )
        }
    }
}

struct SettingsActionRow: View {
    @Environment(\.appAppearance) private var appearance

    let systemImage: String
    let title: String
    let subtitle: String
    var role: ButtonRole?
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: Layout.rowSpacing) {
                SettingsRowHeader(systemImage: systemImage, title: title, subtitle: subtitle, isDestructive: role == .destructive)
                    .layoutPriority(1)

                Spacer(minLength: Layout.rowAccessoryMinimumSpacing)

                if isLoading {
                    ProgressView()
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "chevron.right")
                        .font(appearance.typography.swiftUIFont(size: 13, weight: .bold))
                        .foregroundStyle(Color(uiColor: appearance.secondarySurfaceTextColor))
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(QuizPressButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private struct SettingsValueRow: View {
    @Environment(\.appAppearance) private var appearance
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let systemImage: String
    let title: String
    let subtitle: String
    let value: String

    @ViewBuilder
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            stackedBody
        } else {
            horizontalBody
        }
    }

    private var horizontalBody: some View {
        HStack(spacing: Layout.rowSpacing) {
            SettingsRowHeader(systemImage: systemImage, title: title, subtitle: subtitle)
                .layoutPriority(1)

            Spacer(minLength: Layout.rowAccessoryMinimumSpacing)

            HStack(spacing: Layout.rowAccessorySpacing) {
                Text(value)
                    .font(appearance.typography.swiftUIFont(size: 15, weight: .semibold))
                    .foregroundStyle(Color(uiColor: appearance.surfaceTextColor))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .minimumScaleFactor(Layout.rowValueMinimumScaleFactor)
                    .allowsTightening(true)
                    .layoutPriority(1)

                Image(systemName: "chevron.down")
                    .font(appearance.typography.swiftUIFont(size: 12, weight: .bold))
                    .foregroundStyle(Color(uiColor: appearance.secondarySurfaceTextColor))
                    .accessibilityHidden(true)
            }
            .layoutPriority(1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var stackedBody: some View {
        VStack(alignment: .leading, spacing: Layout.stackedValueTopSpacing) {
            SettingsRowHeader(systemImage: systemImage, title: title, subtitle: subtitle)

            HStack(spacing: Layout.rowAccessorySpacing) {
                Text(value)
                    .font(appearance.typography.swiftUIFont(size: 15, weight: .semibold))
                    .foregroundStyle(Color(uiColor: appearance.surfaceTextColor))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: Layout.rowAccessoryMinimumSpacing)

                Image(systemName: "chevron.down")
                    .font(appearance.typography.swiftUIFont(size: 12, weight: .bold))
                    .foregroundStyle(Color(uiColor: appearance.secondarySurfaceTextColor))
                    .accessibilityHidden(true)
            }
            .padding(Layout.stackedValueInset)
            .background(
                Color(uiColor: appearance.row.backgroundColor),
                in: RoundedRectangle(cornerRadius: appearance.row.cornerRadius, style: .continuous)
            )
            .padding(.leading, Layout.stackedValueLeadingInset)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

struct SettingsRowHeader: View {
    @Environment(\.appAppearance) private var appearance

    let systemImage: String
    let title: String
    let subtitle: String
    var isDestructive = false

    var body: some View {
        HStack(spacing: Layout.rowSpacing) {
            Image(systemName: systemImage)
                .font(appearance.typography.swiftUIFont(size: 20, weight: .semibold))
                .foregroundStyle(Color(uiColor: settingsIconColor))
                .frame(width: Layout.rowIconSize, height: Layout.rowIconSize)
                .background(
                    Color(uiColor: appearance.row.backgroundColor),
                    in: RoundedRectangle(cornerRadius: appearance.row.cornerRadius, style: .continuous)
                )

            VStack(alignment: .leading, spacing: Layout.rowTextSpacing) {
                Text(title)
                    .font(appearance.typography.swiftUIFont(size: 17, weight: .semibold))
                    .foregroundStyle(isDestructive ? Color.red : Color(uiColor: appearance.surfaceTextColor))

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(appearance.typography.swiftUIFont(size: 13, weight: .regular))
                        .foregroundStyle(Color(uiColor: appearance.secondarySurfaceTextColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var settingsIconColor: UIColor {
        appearance.designStyle == .classic ? .white : appearance.accentColor
    }
}

private struct IconChoiceButton: View {
    @Environment(\.appAppearance) private var appearance

    let title: String
    let systemImage: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Layout.iconChoiceContentSpacing) {
                Image(systemName: systemImage)
                    .font(appearance.typography.swiftUIFont(size: 22, weight: .semibold))
                    .foregroundStyle(Color(uiColor: settingsIconColor))
                    .frame(width: Layout.iconChoiceImageSize, height: Layout.iconChoiceImageSize)
                    .background(
                        RoundedRectangle(cornerRadius: appearance.row.cornerRadius, style: .continuous)
                            .fill(
                                isSelected
                                    ? Color(uiColor: appearance.accentColor).opacity(0.22)
                                    : Color(uiColor: appearance.row.backgroundColor)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: appearance.row.cornerRadius, style: .continuous)
                            .stroke(
                                isSelected
                                    ? Color(uiColor: appearance.accentColor)
                                    : Color(uiColor: appearance.row.borderColor),
                                lineWidth: appearance.row.borderWidth
                            )
                    )

                Text(title)
                    .font(appearance.typography.swiftUIFont(size: 12, weight: .semibold))
                    .foregroundStyle(
                        Color(uiColor: isSelected ? appearance.surfaceTextColor : appearance.secondarySurfaceTextColor)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(Layout.iconChoiceTextMinimumScaleFactor)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.38)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var settingsIconColor: UIColor {
        appearance.designStyle == .classic ? .white : appearance.accentColor
    }
}

private extension CleanColorSchemePreference {
    func traitUserInterfaceStyle(fallback colorScheme: ColorScheme) -> UIUserInterfaceStyle {
        switch self {
        case .system:
            return colorScheme == .dark ? .dark : .light
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

#if DEBUG
#Preview("Settings") {
    QuizSettingsView()
}
#endif
