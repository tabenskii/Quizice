import SwiftUI
import UIKit

enum OnboardingPage: Int, CaseIterable, Identifiable {
    case welcome
    case topics
    case tutorial

    var id: Int { rawValue }
}

struct OnboardingTheme: Identifiable, Equatable {
    let id: String
    let title: String
    let sfSymbolName: String
    let emoji: String
    let colorHex: String?

    init(
        id: String,
        title: String,
        sfSymbolName: String = QuizTheme.defaultSFSymbolName,
        emoji: String = QuizTheme.defaultEmoji,
        colorHex: String? = nil
    ) {
        self.id = id
        self.title = title
        self.sfSymbolName = sfSymbolName
        self.emoji = emoji
        self.colorHex = QuizThemeColor.normalizedHex(colorHex)
    }
}

struct QuizOnboardingView: View {
    private enum Layout {
        static let horizontalInset: CGFloat = 20
        static let chromeSpacing: CGFloat = 14
        static let progressSpacing: CGFloat = 7
        static let progressHeight: CGFloat = 4
        static let topPadding: CGFloat = 12
        static let bottomPadding: CGFloat = 10
        static let footerSpacing: CGFloat = 10
        static let buttonHeight: CGFloat = 56
        static let backButtonWidth: CGFloat = 56
        static let storyTapWidth: CGFloat = 64
    }

    let appearance: AppAppearance
    let themes: [OnboardingTheme]
    let catalogOrigin: QuizCatalogOrigin
    let onComplete: (Set<String>) -> Void

    @State private var selectedPage: OnboardingPage
    @State private var selectedThemeIDs: Set<String>
    @AccessibilityFocusState private var focusedHeaderPage: OnboardingPage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        appearance: AppAppearance,
        themes: [OnboardingTheme] = [],
        catalogOrigin: QuizCatalogOrigin = .bundled,
        initialPage: OnboardingPage = .welcome,
        preferredThemeIDs: Set<String> = [],
        onComplete: @escaping (Set<String>) -> Void
    ) {
        self.appearance = appearance
        self.themes = themes
        self.catalogOrigin = catalogOrigin
        self.onComplete = onComplete
        _selectedPage = State(initialValue: initialPage)
        _selectedThemeIDs = State(
            initialValue: preferredThemeIDs.intersection(Set(themes.map(\.id)))
        )
    }

    var body: some View {
        ZStack {
            AppBackgroundView(appearance: appearance, motionProfile: .edgeAware)

            VStack(spacing: 0) {
                chrome
                    .padding(.horizontal, Layout.horizontalInset)

                TabView(selection: $selectedPage) {
                    OnboardingWelcomePage(
                        themes: themes,
                        isActive: selectedPage == .welcome,
                        focusedHeaderPage: $focusedHeaderPage
                    )
                        .tag(OnboardingPage.welcome)

                    OnboardingTopicsPage(
                        themes: themes,
                        catalogOrigin: catalogOrigin,
                        selectedThemeIDs: $selectedThemeIDs,
                        isActive: selectedPage == .topics,
                        focusedHeaderPage: $focusedHeaderPage
                    )
                    .tag(OnboardingPage.topics)

                    OnboardingTutorialPage(
                        themePreview: themes.first,
                        isActive: selectedPage == .tutorial,
                        focusedHeaderPage: $focusedHeaderPage
                    )
                        .tag(OnboardingPage.tutorial)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .indexViewStyle(.page(backgroundDisplayMode: .never))
                .overlay(alignment: .leading) {
                    Color.clear
                        .frame(width: Layout.storyTapWidth)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: goBack)
                        .accessibilityHidden(true)
                }
                .overlay(alignment: .trailing) {
                    Color.clear
                        .frame(width: Layout.storyTapWidth)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: advance)
                        .accessibilityHidden(true)
                }

                footer
                    .padding(.horizontal, Layout.horizontalInset)
            }
            .frame(maxWidth: 560, maxHeight: .infinity)
            .safeAreaPadding(.top, Layout.topPadding)
            .safeAreaPadding(.bottom, Layout.bottomPadding)
        }
        .environment(\.appAppearance, appearance)
        .preferredColorScheme(appearance.swiftUIColorScheme)
        .tint(Color(uiColor: appearance.screenTextColor))
        .onAppear {
            focusedHeaderPage = selectedPage
        }
        .onChange(of: selectedPage) { _, page in
            UIAccessibility.post(
                notification: .pageScrolled,
                argument: L10n.Onboarding.progress(
                    current: page.rawValue + 1,
                    total: OnboardingPage.allCases.count
                )
            )
            focusedHeaderPage = page
        }
    }

    private var chrome: some View {
        HStack(spacing: Layout.chromeSpacing) {
            HStack(spacing: Layout.progressSpacing) {
                ForEach(OnboardingPage.allCases) { page in
                    Capsule()
                        .fill(progressColor(for: page))
                        .frame(maxWidth: .infinity)
                        .frame(height: Layout.progressHeight)
                }
            }
            .frame(maxWidth: .infinity)
            .layoutPriority(0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                L10n.Onboarding.progress(
                    current: selectedPage.rawValue + 1,
                    total: OnboardingPage.allCases.count
                )
            )

            Button(action: complete) {
                Text(selectedPage == .tutorial ? L10n.Settings.close : L10n.Onboarding.skip)
                    .font(appearance.typography.swiftUIFont(size: 15, weight: .semibold))
                    .foregroundStyle(Color(uiColor: appearance.screenTextColor))
                    .padding(.horizontal, 13)
                    .frame(minHeight: 38)
                    .background(
                        Color(uiColor: appearance.iconButton.backgroundColor),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(
                                Color(uiColor: appearance.iconButton.borderColor),
                                lineWidth: appearance.iconButton.borderWidth
                            )
                    }
            }
            .buttonStyle(QuizPressButtonStyle())
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
            .accessibilityIdentifier("onboardingCloseButton")
        }
    }

    private var footer: some View {
        HStack(spacing: Layout.footerSpacing) {
            if selectedPage != .welcome {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                        .font(appearance.typography.swiftUIFont(size: 18, weight: .bold))
                        .foregroundStyle(Color(uiColor: appearance.screenTextColor))
                        .frame(width: Layout.backButtonWidth, height: Layout.buttonHeight)
                        .background(
                            Color(uiColor: appearance.secondaryButton.backgroundColor),
                            in: RoundedRectangle(
                                cornerRadius: appearance.secondaryButton.cornerRadius,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: appearance.secondaryButton.cornerRadius,
                                style: .continuous
                            )
                            .stroke(
                                Color(uiColor: appearance.secondaryButton.borderColor),
                                lineWidth: appearance.secondaryButton.borderWidth
                            )
                        }
                }
                .buttonStyle(QuizPressButtonStyle())
                .accessibilityLabel(L10n.Common.back)
                .accessibilityIdentifier("onboardingBackButton")
            }

            Button(action: advance) {
                HStack(spacing: 9) {
                    Text(selectedPage == .tutorial ? L10n.Onboarding.getStarted : L10n.Common.next)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Image(systemName: selectedPage == .tutorial ? "sparkles" : "arrow.right")
                        .font(appearance.typography.swiftUIFont(size: 16, weight: .bold))
                        .accessibilityHidden(true)
                }
                .font(appearance.typography.swiftUIFont(size: 18, weight: .semibold))
                .foregroundStyle(
                    Color(
                        uiColor: QuizThemeAccentStyle.primaryButtonTextColor(
                            themeID: nil,
                            appearance: appearance
                        )
                    )
                )
                .frame(maxWidth: .infinity)
                .frame(height: Layout.buttonHeight)
                .background(
                    Color(uiColor: appearance.primaryButton.backgroundColor),
                    in: RoundedRectangle(
                        cornerRadius: appearance.primaryButton.cornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: appearance.primaryButton.cornerRadius,
                        style: .continuous
                    )
                    .stroke(
                        Color(uiColor: appearance.primaryButton.borderColor),
                        lineWidth: appearance.primaryButton.borderWidth
                    )
                }
                .onboardingShadow(appearance.primaryButton.shadow)
            }
            .buttonStyle(QuizPressButtonStyle())
            .accessibilityIdentifier("onboardingPrimaryButton")
        }
    }

    private func progressColor(for page: OnboardingPage) -> Color {
        Color(uiColor: appearance.screenTextColor)
            .opacity(page.rawValue <= selectedPage.rawValue ? 0.92 : 0.20)
    }

    private func advance() {
        guard let nextPage = OnboardingPage(rawValue: selectedPage.rawValue + 1) else {
            complete()
            return
        }
        withAnimation(pageAnimation) {
            selectedPage = nextPage
        }
    }

    private func goBack() {
        guard let previousPage = OnboardingPage(rawValue: selectedPage.rawValue - 1) else { return }
        withAnimation(pageAnimation) {
            selectedPage = previousPage
        }
    }

    private func complete() {
        onComplete(selectedThemeIDs)
    }

    private var pageAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return .timingCurve(0.32, 0.72, 0, 1, duration: 0.32)
    }
}

extension View {
    func onboardingShadow(_ shadow: AppShadowStyle) -> some View {
        self.shadow(
            color: Color(uiColor: shadow.color).opacity(Double(shadow.opacity)),
            radius: shadow.radius,
            x: shadow.offset.width,
            y: shadow.offset.height
        )
    }
}
