import SwiftUI

@MainActor
final class AccountStartModel: ObservableObject {
    @Published var state: AppAccountAccessState
    @Published var errorMessage: String?
    @Published var needsGameCenterSignIn = true

    var usesConnectionSplash: Bool {
        state == .loading || state == .authenticated || (state == .signInRequired && !needsGameCenterSignIn)
    }

    init(state: AppAccountAccessState = .loading, errorMessage: String? = nil) {
        self.state = state
        self.errorMessage = errorMessage
    }
}

struct AccountStartView: View {
    @ObservedObject var model: AccountStartModel
    let appearance: AppAppearance
    let onPrimaryAction: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 32
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 17
    @ScaledMetric(relativeTo: .footnote) private var privacySize: CGFloat = 14
    @StateObject private var connectionReadiness = FakeLaunchReadiness(isReady: false)

    init(
        model: AccountStartModel,
        appearance: AppAppearance = AppAppearanceStore.shared.appearance(compatibleWith: .current),
        onPrimaryAction: @escaping () -> Void
    ) {
        self.model = model
        self.appearance = appearance
        self.onPrimaryAction = onPrimaryAction
    }

    var body: some View {
        Group {
            if model.usesConnectionSplash {
                connectionSplash
                .accessibilityIdentifier("accountConnectionSplash")
            } else {
                accountScreen
            }
        }
        .environment(\.appAppearance, appearance)
        .preferredColorScheme(appearance.swiftUIColorScheme)
        .accessibilityIdentifier("accountStartScreen")
    }

    @ViewBuilder
    private var connectionSplash: some View {
        if model.errorMessage != nil || model.state == .signInRequired {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    FakeLaunchScreenView(appearance: appearance, readiness: connectionReadiness, showsBackground: false)
                        .frame(width: min(geometry.size.width, geometry.size.height * 0.8),
                               height: geometry.size.height * 0.4)
                        .clipped()
                    ScrollView {
                        VStack(spacing: 18) {
                            Text(model.errorMessage ?? L10n.AccountStart.connectionFailedMessage)
                                .font(appearance.typography.swiftUIFont(size: bodySize, weight: .medium))
                                .foregroundStyle(Color(uiColor: appearance.screenTextColor))
                                .multilineTextAlignment(.center)
                                .accessibilityIdentifier("accountStartError")
                            action
                        }
                        .frame(maxWidth: 440)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
                .background {
                    let style = FakeLaunchVisualStyle(appearance: appearance)
                    Color(uiColor: style.backgroundColor).ignoresSafeArea()
                    if style.revealsAppBackground { AppBackgroundView(appearance: appearance) }
                }
            }
        } else {
            FakeLaunchScreenView(appearance: appearance, readiness: connectionReadiness)
        }
    }

    private var accountScreen: some View {
        GeometryReader { geometry in
            ZStack {
                Color(uiColor: appearance.backgroundColor)
                    .ignoresSafeArea()
                AppBackgroundView(appearance: appearance)
                    .allowsHitTesting(false)

                ScrollView {
                    VStack(spacing: geometry.size.height < 700 ? 24 : 32) {
                        Image("QII")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .foregroundStyle(Color(uiColor: appearance.screenTextColor))
                            .frame(width: min(geometry.size.width * 0.6, 260))
                            .accessibilityHidden(true)

                        message
                        action
                        privacyLink
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 28)
                    .frame(maxWidth: 440)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
                .scrollIndicators(.hidden)
            }
        }
        .environment(\.appAppearance, appearance)
        .preferredColorScheme(appearance.swiftUIColorScheme)
        .accessibilityIdentifier("accountStartScreen")
    }

    private var message: some View {
        VStack(spacing: 14) {
            Text(title)
                .font(appearance.typography.swiftUIFont(size: titleSize, weight: .bold))
                .foregroundStyle(Color(uiColor: appearance.screenTextColor))
                .accessibilityAddTraits(.isHeader)

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(appearance.typography.swiftUIFont(size: bodySize, weight: .medium))
                    .foregroundStyle(Color(uiColor: appearance.screenTextColor))
                    .accessibilityIdentifier("accountStartError")
            } else if let description {
                Text(description)
                    .font(appearance.typography.swiftUIFont(size: bodySize, weight: .regular))
                    .foregroundStyle(Color(uiColor: appearance.secondaryScreenTextColor))
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var action: some View {
        if let actionTitle {
            Button(action: onPrimaryAction) {
                Text(actionTitle)
                    .font(appearance.typography.swiftUIFont(size: bodySize, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Color(uiColor: QuizThemeAccentStyle.primaryButtonTextColor(
                        themeID: nil, appearance: appearance
                    )))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(
                        Color(uiColor: appearance.primaryButton.backgroundColor),
                        in: RoundedRectangle(cornerRadius: appearance.primaryButton.cornerRadius, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: appearance.primaryButton.cornerRadius, style: .continuous)
                            .stroke(Color(uiColor: appearance.primaryButton.borderColor), lineWidth: appearance.primaryButton.borderWidth)
                    }
            }
            .buttonStyle(QuizPressButtonStyle())
            .accessibilityIdentifier(model.usesConnectionSplash ? "accountConnectionRetry" : "accountStartPrimaryAction")
        }
    }

    @ViewBuilder
    private var privacyLink: some View {
        if let url = URL(string: "https://github.com/tabenskii/Quizice/blob/main/docs/privacy-policy.md") {
            Link(destination: url) {
                Text(L10n.Settings.privacyPolicy)
                    .font(appearance.typography.swiftUIFont(size: privacySize, weight: .regular))
                    .foregroundStyle(Color(uiColor: appearance.secondaryScreenTextColor))
                    .underline()
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("accountStartPrivacyPolicy")
        }
    }

    private var title: String {
        switch model.state {
        case .loading, .authenticated: return ""
        case .signInRequired: return L10n.Onboarding.welcomeTitle
        case .deleted: return L10n.Settings.Account.deletedTitle
        case .deletionPending: return L10n.AccountStart.deletionPendingTitle
        }
    }

    private var description: String? {
        switch model.state {
        case .loading, .authenticated: return nil
        case .signInRequired: return L10n.AccountStart.signInMessage
        case .deleted: return L10n.Settings.Account.deletedMessage
        case .deletionPending: return L10n.AccountStart.deletionPendingMessage
        }
    }

    private var actionTitle: String? {
        if model.usesConnectionSplash {
            return model.errorMessage != nil || model.state == .signInRequired ? L10n.Settings.Account.retry : nil
        }
        switch model.state {
        case .loading, .authenticated: return nil
        case .signInRequired: return L10n.AccountStart.continueWithGameCenter
        case .deleted: return L10n.Settings.Account.create
        case .deletionPending: return L10n.AccountStart.retryDeletion
        }
    }
}
