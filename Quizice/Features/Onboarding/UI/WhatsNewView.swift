import SwiftUI
import UIKit

@MainActor
final class WhatsNewPresentation {
    static let releaseVersion = "1.2"
    private static let handledReleaseKey = "quizice.whatsNew.handledRelease"

    private let defaults: UserDefaults
    private let appVersion: String?
    private weak var presentedController: UIViewController?

    init(
        defaults: UserDefaults = .standard,
        appVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    ) {
        self.defaults = defaults
        self.appVersion = appVersion
    }

    var isPresented: Bool { presentedController != nil }

    private func requiresPresentation(hasCompletedOnboarding: Bool) -> Bool {
        guard let appVersion,
              appVersion == Self.releaseVersion || appVersion.hasPrefix(Self.releaseVersion + "."),
              defaults.string(forKey: Self.handledReleaseKey) != Self.releaseVersion else { return false }
        if hasCompletedOnboarding { return true }
        markHandled()
        return false
    }

    private func markHandled() {
        defaults.set(Self.releaseVersion, forKey: Self.handledReleaseKey)
    }

    func presentIfNeeded(
        from presenter: UIViewController,
        hasCompletedOnboarding: Bool,
        completion: @escaping () -> Void
    ) -> Bool {
        guard !isPresented else { completion(); return true }
        guard requiresPresentation(hasCompletedOnboarding: hasCompletedOnboarding) else { return false }

        let appearance = AppAppearanceStore.shared.appearance(compatibleWith: presenter.traitCollection)
        let viewController = UIHostingController(rootView: WhatsNewView(appearance: appearance, onContinue: { [weak self] in
            self?.finish()
        }))
        viewController.modalPresentationStyle = .fullScreen
        viewController.overrideUserInterfaceStyle = appearance.resolvedInterfaceStyle
        presentedController = viewController
        presenter.present(viewController, animated: false, completion: completion)
        return true
    }

    private func finish() {
        guard let presentedController, !presentedController.isBeingDismissed else { return }
        markHandled()
        presentedController.dismiss(animated: true) { [weak self] in
            self?.presentedController = nil
        }
    }
}

struct WhatsNewView: View {
    let appearance: AppAppearance
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            AppBackgroundView(appearance: appearance, motionProfile: .edgeAware)
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text(L10n.WhatsNew.title(version: WhatsNewPresentation.releaseVersion))
                            .font(appearance.typography.swiftUIFont(size: 30, weight: .bold))
                            .accessibilityAddTraits(.isHeader)
                        change(L10n.WhatsNew.statistics, symbol: "chart.xyaxis.line")
                        change(L10n.WhatsNew.moreThemes, symbol: "square.grid.2x2")
                        change(L10n.WhatsNew.launch, symbol: "sparkles")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 28)
                }

                Button(action: onContinue) {
                    Text(L10n.WhatsNew.continueAction)
                        .font(appearance.typography.swiftUIFont(size: 18, weight: .semibold))
                        .foregroundStyle(Color(uiColor: QuizThemeAccentStyle.primaryButtonTextColor(themeID: nil, appearance: appearance)))
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(
                            Color(uiColor: appearance.primaryButton.backgroundColor),
                            in: RoundedRectangle(cornerRadius: appearance.primaryButton.cornerRadius)
                        )
                }
                .buttonStyle(QuizPressButtonStyle())
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: 560)
        }
        .foregroundStyle(Color(uiColor: appearance.screenTextColor))
        .preferredColorScheme(appearance.swiftUIColorScheme)
        .accessibilityAction(.escape, onContinue)
    }

    private func change(_ title: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(appearance.typography.swiftUIFont(size: 18, weight: .regular))
    }
}
