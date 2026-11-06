import SwiftUI
import UIKit

struct OnboardingWelcomePage: View {
    private enum Layout {
        static let compactHeightThreshold: CGFloat = 590
        static let regularArtworkHeight: CGFloat = 232
        static let compactArtworkHeight: CGFloat = 178
        static let compactArtworkScale: CGFloat = 0.78
    }

    let themes: [OnboardingTheme]
    let isActive: Bool
    var focusedHeaderPage: AccessibilityFocusState<OnboardingPage?>.Binding

    @Environment(\.appAppearance) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRevealed = false

    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.height < Layout.compactHeightThreshold

            VStack(spacing: isCompact ? 12 : 22) {
                Spacer(minLength: isCompact ? 0 : 8)

                WelcomeArtwork(
                    themes: themes,
                    isRevealed: isRevealed || reduceMotion || !UIView.areAnimationsEnabled
                )
                .frame(height: Layout.regularArtworkHeight)
                .scaleEffect(isCompact ? Layout.compactArtworkScale : 1)
                .frame(
                    height: isCompact
                        ? Layout.compactArtworkHeight
                        : Layout.regularArtworkHeight
                )

                VStack(spacing: isCompact ? 8 : 12) {
                    Text(L10n.Onboarding.welcomeKicker)
                        .font(
                            appearance.typography.swiftUIFont(
                                size: isCompact ? 11 : 13,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(Color(uiColor: appearance.secondaryScreenTextColor))
                        .textCase(.uppercase)
                        .tracking(isCompact ? 0.5 : 0.8)

                    Text(L10n.Onboarding.welcomeTitle)
                        .font(
                            appearance.typography.swiftUIFont(
                                size: isCompact ? 30 : 38,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(Color(uiColor: appearance.screenTextColor))
                        .multilineTextAlignment(.center)
                        .lineSpacing(isCompact ? -1 : -2)
                        .minimumScaleFactor(0.76)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("onboardingWelcomeTitle")
                        .accessibilityFocused(focusedHeaderPage, equals: .welcome)

                    Text(L10n.Onboarding.welcomeSubtitle)
                        .font(
                            appearance.typography.swiftUIFont(
                                size: isCompact ? 15 : 18,
                                weight: .regular
                            )
                        )
                        .foregroundStyle(Color(uiColor: appearance.secondaryScreenTextColor))
                        .multilineTextAlignment(.center)
                        .lineSpacing(isCompact ? 1 : 3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, isCompact ? 0 : 4)

                Spacer(minLength: isCompact ? 0 : 18)
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, isCompact ? 20 : 24)
            .frame(
                maxWidth: .infinity,
                minHeight: geometry.size.height,
                maxHeight: geometry.size.height
            )
        }
        .accessibilityIdentifier("onboardingWelcomePage")
        .onAppear(perform: updateReveal)
        .onChange(of: isActive) { _, _ in updateReveal() }
    }

    private func updateReveal() {
        var resetTransaction = Transaction()
        resetTransaction.disablesAnimations = true
        withTransaction(resetTransaction) {
            isRevealed = reduceMotion || !UIView.areAnimationsEnabled ? isActive : false
        }
        guard isActive, !reduceMotion, UIView.areAnimationsEnabled else { return }
        Task { @MainActor in
            await Task.yield()
            isRevealed = true
        }
    }
}

private struct WelcomeArtwork: View {
    let themes: [OnboardingTheme]
    let isRevealed: Bool

    @Environment(\.appAppearance) private var appearance

    var body: some View {
        ZStack {
            ForEach(Array(themes.prefix(3).enumerated()), id: \.element.id) { index, theme in
                let pose = Self.decorationPoses[index]
                decorativeCard(
                    systemImage: theme.sfSymbolName,
                    color: ThemeVisualCatalog.tintColor(for: theme),
                    size: pose.size
                )
                .rotationEffect(.degrees(isRevealed ? pose.rotation : pose.hiddenRotation))
                .offset(
                    x: isRevealed ? pose.offset.width : pose.hiddenOffset.width,
                    y: isRevealed ? pose.offset.height : pose.hiddenOffset.height
                )
            }

            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .fill(Color(uiColor: appearance.card.backgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 44, style: .continuous)
                        .stroke(
                            Color(uiColor: appearance.card.borderColor),
                            lineWidth: max(appearance.card.borderWidth, 1)
                        )
                }
                .onboardingShadow(appearance.card.shadow)
                .frame(width: 160, height: 160)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "questionmark")
                            .font(appearance.typography.swiftUIFont(size: 44, weight: .black))
                            .foregroundStyle(Color(uiColor: appearance.screenTextColor))
                            .accessibilityHidden(true)

                        Text("QUIZICE")
                            .font(appearance.typography.swiftUIFont(size: 13, weight: .bold))
                            .foregroundStyle(Color(uiColor: appearance.secondarySurfaceTextColor))
                            .tracking(1.6)
                    }
                }
                .scaleEffect(isRevealed ? 1 : 0.92)
                .opacity(isRevealed ? 1 : 0.35)
        }
        .animation(
            .spring(response: 0.52, dampingFraction: 0.82, blendDuration: 0.08),
            value: isRevealed
        )
        .accessibilityHidden(true)
    }

    private struct DecorationPose {
        let size: CGFloat
        let rotation: Double
        let hiddenRotation: Double
        let offset: CGSize
        let hiddenOffset: CGSize
    }

    private static let decorationPoses = [
        DecorationPose(
            size: 82,
            rotation: -13,
            hiddenRotation: -24,
            offset: CGSize(width: -96, height: 42),
            hiddenOffset: CGSize(width: -122, height: 68)
        ),
        DecorationPose(
            size: 72,
            rotation: 12,
            hiddenRotation: 24,
            offset: CGSize(width: 104, height: -38),
            hiddenOffset: CGSize(width: 132, height: -58)
        ),
        DecorationPose(
            size: 62,
            rotation: 8,
            hiddenRotation: 18,
            offset: CGSize(width: 108, height: 72),
            hiddenOffset: CGSize(width: 136, height: 98)
        )
    ]

    private func decorativeCard(systemImage: String, color: UIColor, size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Color(uiColor: appearance.themeCardBackground(baseColor: color)))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .stroke(Color(uiColor: appearance.themeCardBorder(baseColor: color)), lineWidth: 1.2)
            }
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: ThemeVisualCatalog.resolvedSymbolName(systemImage))
                    .font(appearance.typography.swiftUIFont(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(Color(uiColor: appearance.themeCardTextColor(baseColor: color)))
            }
            .onboardingShadow(appearance.themeCardShadow)
            .opacity(isRevealed ? 1 : 0.22)
    }
}

struct OnboardingTopicsPage: View {
    private enum Layout {
        static let compactHeightThreshold: CGFloat = 590
    }

    let themes: [OnboardingTheme]
    let catalogOrigin: QuizCatalogOrigin
    @Binding var selectedThemeIDs: Set<String>
    let isActive: Bool
    var focusedHeaderPage: AccessibilityFocusState<OnboardingPage?>.Binding

    @Environment(\.appAppearance) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.height < Layout.compactHeightThreshold

            VStack(spacing: isCompact ? 8 : 14) {
                VStack(spacing: isCompact ? 6 : 10) {
                    Text(L10n.Onboarding.topicsTitle)
                        .font(
                            appearance.typography.swiftUIFont(
                                size: isCompact ? 28 : 32,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(Color(uiColor: appearance.screenTextColor))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("onboardingTopicsTitle")
                        .accessibilityFocused(focusedHeaderPage, equals: .topics)

                    Text(L10n.Onboarding.topicsSubtitle)
                        .font(
                            appearance.typography.swiftUIFont(
                                size: isCompact ? 15 : 17,
                                weight: .regular
                            )
                        )
                        .foregroundStyle(Color(uiColor: appearance.secondaryScreenTextColor))
                        .multilineTextAlignment(.center)
                        .lineSpacing(isCompact ? 1 : 2)
                        .fixedSize(horizontal: false, vertical: true)

#if DEBUG
                    if DebugBackendSettings.shouldShowSourceIndicators {
                        OnboardingCatalogSourceBadge(origin: catalogOrigin)
                    }
#endif
                }
                .padding(.horizontal, 24)

                FallingTopicsStage(
                    themes: themes,
                    selectedThemeIDs: $selectedThemeIDs,
                    isActive: isActive
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

                Label(L10n.Onboarding.topicsSelectionHint, systemImage: "hand.tap.fill")
                    .font(
                        appearance.typography.swiftUIFont(
                            size: isCompact ? 12 : 14,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(Color(uiColor: appearance.secondaryScreenTextColor))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, isCompact ? 0 : 2)
            }
            .frame(maxWidth: 560)
            .padding(.top, isCompact ? 4 : 12)
            .frame(
                maxWidth: .infinity,
                minHeight: geometry.size.height,
                maxHeight: geometry.size.height,
                alignment: .top
            )
        }
        .accessibilityIdentifier("onboardingTopicsPage")
    }
}

#if DEBUG
private struct OnboardingCatalogSourceBadge: View {
    let origin: QuizCatalogOrigin

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color(uiColor: AppAssetColor.white.uiColor))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color(uiColor: backgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityLabel(title)
            .accessibilityIdentifier("onboardingBackendCatalogSource")
    }

    private var title: String {
        switch origin {
        case .backend: "CATALOG: BACKEND"
        case .bundled: "CATALOG: LOCAL"
        }
    }

    private var backgroundColor: UIColor {
        switch origin {
        case .backend: AppAssetColor.fallbackGreen.uiColor
        case .bundled: AppAssetColor.fallbackOrange.uiColor
        }
    }
}
#endif

struct OnboardingTutorialPage: View {
    let themePreview: OnboardingTheme?
    let isActive: Bool
    var focusedHeaderPage: AccessibilityFocusState<OnboardingPage?>.Binding

    @Environment(\.appAppearance) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Start in the final state so an initially presented tutorial never renders
    // as an empty page before `onAppear` gets a chance to run. When this page is
    // preloaded off-screen, `updateReveal()` resets it for the entrance motion.
    @State private var isRevealed = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    Text(L10n.Onboarding.tutorialTitle)
                        .font(appearance.typography.swiftUIFont(size: 32, weight: .bold))
                        .foregroundStyle(Color(uiColor: appearance.screenTextColor))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("onboardingTutorialTitle")
                        .accessibilityFocused(focusedHeaderPage, equals: .tutorial)

                    Text(L10n.Onboarding.tutorialSubtitle)
                        .font(appearance.typography.swiftUIFont(size: 17, weight: .regular))
                        .foregroundStyle(Color(uiColor: appearance.secondaryScreenTextColor))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)

                VStack(spacing: 12) {
                    ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                        TutorialFeatureRow(feature: feature, themePreview: themePreview)
                            // Keep the content readable even if the page is captured or
                            // interrupted before its reveal transaction commits.
                            .scaleEffect(showsContent ? 1 : 0.985)
                            .offset(y: showsContent ? 0 : 14)
                            .animation(revealAnimation(index: index), value: isRevealed)
                    }
                }
            }
            .frame(maxWidth: 540)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("onboardingTutorialPage")
        .onAppear(perform: updateReveal)
        .onChange(of: isActive) { _, _ in updateReveal() }
    }

    private var features: [TutorialFeature] {
        [
            TutorialFeature(
                id: "themes",
                kind: .theme,
                title: L10n.Onboarding.tutorialThemesTitle,
                detail: L10n.Onboarding.tutorialThemesDetail
            ),
            TutorialFeature(
                id: "ai",
                kind: .ai,
                title: L10n.Onboarding.tutorialAITitle,
                detail: L10n.Onboarding.tutorialAIDetail
            ),
            TutorialFeature(
                id: "statistics",
                kind: .statistics,
                title: L10n.Onboarding.tutorialStatisticsTitle,
                detail: L10n.Onboarding.tutorialStatisticsDetail
            )
        ]
    }

    private var showsContent: Bool {
        isRevealed || reduceMotion || !UIView.areAnimationsEnabled
    }

    private func updateReveal() {
        var resetTransaction = Transaction()
        resetTransaction.disablesAnimations = true
        withTransaction(resetTransaction) {
            isRevealed = reduceMotion || !UIView.areAnimationsEnabled ? isActive : false
        }
        guard isActive, !reduceMotion, UIView.areAnimationsEnabled else { return }
        Task { @MainActor in
            await Task.yield()
            isRevealed = true
        }
    }

    private func revealAnimation(index: Int) -> Animation? {
        guard !reduceMotion, UIView.areAnimationsEnabled else { return nil }
        return .timingCurve(0.23, 1, 0.32, 1, duration: 0.34)
            .delay(Double(index) * 0.07)
    }
}

private struct TutorialFeature: Identifiable {
    enum Kind {
        case theme
        case ai
        case statistics
    }

    let id: String
    let kind: Kind
    let title: String
    let detail: String
}

private struct TutorialFeatureRow: View {
    let feature: TutorialFeature
    let themePreview: OnboardingTheme?

    @Environment(\.appAppearance) private var appearance

    var body: some View {
        HStack(spacing: 15) {
            preview
                .frame(width: 74, height: 74)

            VStack(alignment: .leading, spacing: 5) {
                Text(feature.title)
                    .font(appearance.typography.swiftUIFont(size: 18, weight: .semibold))
                    .foregroundStyle(Color(uiColor: appearance.surfaceTextColor))
                    .fixedSize(horizontal: false, vertical: true)

                Text(feature.detail)
                    .font(appearance.typography.swiftUIFont(size: 14, weight: .regular))
                    .foregroundStyle(Color(uiColor: appearance.secondarySurfaceTextColor))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(appearance.typography.swiftUIFont(size: 13, weight: .bold))
                .foregroundStyle(Color(uiColor: appearance.secondarySurfaceTextColor).opacity(0.7))
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(
            Color(uiColor: appearance.card.backgroundColor),
            in: RoundedRectangle(cornerRadius: appearance.card.cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: appearance.card.cornerRadius, style: .continuous)
                .stroke(Color(uiColor: appearance.card.borderColor), lineWidth: appearance.card.borderWidth)
        }
        .onboardingShadow(appearance.card.shadow)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var preview: some View {
        switch feature.kind {
        case .theme:
            let tintColor = themePreview.map(ThemeVisualCatalog.tintColor(for:))
                ?? ThemeVisualCatalog.tintColor(colorHex: nil, themeID: "theme-preview")
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: appearance.themeCardBackground(baseColor: tintColor)))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color(uiColor: appearance.themeCardBorder(baseColor: tintColor)), lineWidth: 1.3)
                }
                .overlay {
                    Image(
                        uiImage: ThemeVisualCatalog.logoImage(
                            sfSymbolName: themePreview?.sfSymbolName
                                ?? QuizTheme.defaultSFSymbolName
                        ) ?? UIImage()
                    )
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .foregroundStyle(Color(uiColor: appearance.themeCardTextColor(baseColor: tintColor)))
                }

        case .ai:
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: appearance.secondaryButton.backgroundColor))
                .overlay {
                    aiPreviewOutline
                }
                .shadow(
                    color: appearance.designStyle == .radar
                        ? Color(uiColor: appearance.accentColor).opacity(0.22)
                        : .clear,
                    radius: appearance.designStyle == .radar ? 10 : 0
                )
                .overlay {
                    Image(systemName: "sparkles")
                        .font(appearance.typography.swiftUIFont(size: 28, weight: .semibold))
                        .foregroundStyle(Color(uiColor: appearance.screenTextColor))
                        .accessibilityHidden(true)
                }

        case .statistics:
            ZStack {
                Circle()
                    .stroke(Color(uiColor: appearance.progressTrackColor), lineWidth: 7)

                Circle()
                    .trim(from: 0, to: 0.78)
                    .stroke(
                        Color(uiColor: appearance.correctAnswerColor),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Text("78%")
                    .font(appearance.typography.swiftUIFont(size: 15, weight: .bold))
                    .foregroundStyle(Color(uiColor: appearance.surfaceTextColor))
            }
            .padding(5)
        }
    }

    @ViewBuilder
    private var aiPreviewOutline: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        if appearance.designStyle == .radar {
            shape.stroke(Color(uiColor: appearance.accentColor), lineWidth: 2)
        } else {
            shape.stroke(
                LinearGradient(
                    colors: [
                        Color(uiColor: AIThemeVisualStyle.gradientStartColor),
                        Color(uiColor: AIThemeVisualStyle.gradientEndColor)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                lineWidth: 2
            )
        }
    }
}
