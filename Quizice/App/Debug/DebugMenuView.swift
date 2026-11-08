#if DEBUG
import PulseUI
import SwiftUI

enum DebugSubscriptionPromoSettings {
    static let showPromoKey = "quizice.debug.subscription.show-promo"
}

@MainActor
final class DebugMenuViewModel: ObservableObject {
    @Published private(set) var isInterfaceHidden: Bool
    @Published private(set) var usesLocalhostBackend: Bool
    @Published private(set) var usesLocalContentOnly: Bool
    @Published private(set) var usesDirectAI: Bool
    @Published private(set) var showsSubscriptionPromo: Bool
    @Published private(set) var isSubscriptionActive: Bool
    @Published private(set) var backgroundStyle: AppBackgroundStyle

    let showsBackgroundStyles: Bool

    private let toggleInterfaceVisibilityAction: () -> Void
    private let toggleLocalhostBackendAction: () -> Void
    private let toggleLocalContentOnlyAction: () -> Void
    private let toggleDirectAIAction: () -> Void
    private let setSubscriptionPromoVisibleAction: (Bool) -> Void
    private let setSubscriptionActiveAction: (Bool) -> Void
    private let selectBackgroundStyleAction: (AppBackgroundStyle) -> Void
    private let defaults: UserDefaults

    init(
        isInterfaceHidden: Bool,
        isSubscriptionActive: Bool,
        appearance: AppAppearance,
        defaults: UserDefaults = .standard,
        toggleInterfaceVisibility: @escaping () -> Void,
        toggleLocalhostBackend: @escaping () -> Void,
        toggleLocalContentOnly: @escaping () -> Void,
        toggleDirectAI: @escaping () -> Void,
        setSubscriptionPromoVisible: @escaping (Bool) -> Void,
        setSubscriptionActive: @escaping (Bool) -> Void,
        selectBackgroundStyle: @escaping (AppBackgroundStyle) -> Void
    ) {
        self.isInterfaceHidden = isInterfaceHidden
        self.usesLocalhostBackend = defaults.bool(forKey: DebugBackendSettings.useLocalhostKey)
        self.usesLocalContentOnly = defaults.bool(forKey: DebugBackendSettings.useLocalContentOnlyKey)
        self.usesDirectAI = defaults.bool(forKey: DebugAIRuntimeSettings.useDirectAIKey)
        self.showsSubscriptionPromo = defaults.bool(forKey: DebugSubscriptionPromoSettings.showPromoKey)
        self.isSubscriptionActive = isSubscriptionActive
        self.backgroundStyle = appearance.backgroundStyle
        self.showsBackgroundStyles = appearance.designStyle == .classic
        self.defaults = defaults
        self.toggleInterfaceVisibilityAction = toggleInterfaceVisibility
        self.toggleLocalhostBackendAction = toggleLocalhostBackend
        self.toggleLocalContentOnlyAction = toggleLocalContentOnly
        self.toggleDirectAIAction = toggleDirectAI
        self.setSubscriptionPromoVisibleAction = setSubscriptionPromoVisible
        self.setSubscriptionActiveAction = setSubscriptionActive
        self.selectBackgroundStyleAction = selectBackgroundStyle
    }

    func toggleInterfaceVisibility() {
        toggleInterfaceVisibilityAction()
        isInterfaceHidden.toggle()
    }

    func toggleLocalhostBackend() {
        toggleLocalhostBackendAction()
        refreshRuntimeSettings()
    }

    func toggleLocalContentOnly() {
        toggleLocalContentOnlyAction()
        refreshRuntimeSettings()
    }

    func toggleDirectAI() {
        toggleDirectAIAction()
        refreshRuntimeSettings()
    }

    func setSubscriptionPromoVisible(_ isVisible: Bool) {
        defaults.set(isVisible, forKey: DebugSubscriptionPromoSettings.showPromoKey)
        setSubscriptionPromoVisibleAction(isVisible)
        showsSubscriptionPromo = isVisible
    }

    func setSubscriptionActive(_ isActive: Bool) {
        setSubscriptionActiveAction(isActive)
        isSubscriptionActive = isActive
    }

    func selectBackgroundStyle(_ style: AppBackgroundStyle) {
        selectBackgroundStyleAction(style)
        backgroundStyle = style
    }

    private func refreshRuntimeSettings() {
        usesLocalhostBackend = defaults.bool(forKey: DebugBackendSettings.useLocalhostKey)
        usesLocalContentOnly = defaults.bool(forKey: DebugBackendSettings.useLocalContentOnlyKey)
        usesDirectAI = defaults.bool(forKey: DebugAIRuntimeSettings.useDirectAIKey)
    }
}

#if targetEnvironment(simulator)
private struct DebugTestAccountSection: View {
    @State private var key = ""
    @State private var isConnecting = false
    @State private var status: String?

    var body: some View {
        Section(L10n.DebugMenu.testAccountTitle) {
            SecureField(L10n.DebugMenu.testAccountKey, text: $key)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("debugTestAccountKey")
            Button {
                Task { await connect() }
            } label: {
                HStack {
                    Text(L10n.DebugMenu.testAccountConnect)
                    if isConnecting { ProgressView() }
                }
            }
            .disabled(isConnecting)
            .accessibilityIdentifier("debugTestAccountConnect")
            Text(status ?? L10n.DebugMenu.testAccountHelp)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @MainActor private func connect() async {
        guard !isConnecting else { return }
        guard let configuration = BackendConfiguration.load() else {
            status = L10n.DebugMenu.testAccountNoBackend
            return
        }
        isConnecting = true
        defer { isConnecting = false }
        let provider = DebugTestAccountProvider(configuration: configuration)
        do {
            let secret = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let selectedKey = secret.isEmpty ? try provider.loadKey() : secret else {
                status = L10n.DebugMenu.testAccountKeyRequired
                return
            }
            _ = try await provider.connect(key: selectedKey)
            key = ""
            NotificationCenter.default.post(name: DebugTestAccountProvider.didConnect, object: nil)
        } catch {
            // Never show decoding payloads or request headers containing credentials.
            status = L10n.DebugMenu.testAccountFailure
        }
    }
}
#endif

struct DebugMenuView: View {
    enum AccessibilityID {
        static let root = "debugMenuRoot"
        static let interfaceToggle = "debugMenuInterfaceToggle"
        static let localhostToggle = "debugMenuLocalhostToggle"
        static let localContentToggle = "debugMenuLocalContentToggle"
        static let directAIToggle = "debugMenuDirectAIToggle"
        static let subscriptionPromoToggle = "debugMenuSubscriptionPromoToggle"
        static let subscriptionActiveToggle = "debugMenuSubscriptionActiveToggle"
        static let pulse = "debugMenuPulse"
        static let backgroundStyle = "debugMenuBackgroundStyle"
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: DebugMenuViewModel

    var body: some View {
        NavigationStack {
            List {
                interfaceSection
                backendSection
#if targetEnvironment(simulator)
                DebugTestAccountSection()
#endif
                toolsSection
                if viewModel.showsBackgroundStyles {
                    backgroundSection
                }
            }
            .accessibilityIdentifier(AccessibilityID.root)
            .navigationTitle(L10n.DebugMenu.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Settings.done) {
                        dismiss()
                    }
                }
            }
        }
        .tint(.blue)
        .preferredColorScheme(.dark)
    }

    private var interfaceSection: some View {
        Section(L10n.DebugMenu.interfaceSectionTitle) {
            Toggle(
                isOn: Binding(
                    get: { viewModel.isInterfaceHidden },
                    set: { _ in viewModel.toggleInterfaceVisibility() }
                )
            ) {
                DebugMenuRowLabel(
                    title: L10n.DebugMenu.hideInterface,
                    subtitle: L10n.DebugMenu.hideInterfaceSubtitle,
                    systemImage: "eye.slash.fill",
                    color: .orange
                )
            }
            .accessibilityIdentifier(AccessibilityID.interfaceToggle)

            Toggle(
                isOn: Binding(
                    get: { viewModel.showsSubscriptionPromo },
                    set: { viewModel.setSubscriptionPromoVisible($0) }
                )
            ) {
                DebugMenuRowLabel(
                    title: L10n.DebugMenu.showSubscriptionPromo,
                    subtitle: L10n.DebugMenu.showSubscriptionPromoSubtitle,
                    systemImage: "rectangle.badge.plus",
                    color: .purple
                )
            }
            .accessibilityIdentifier(AccessibilityID.subscriptionPromoToggle)

            Toggle(
                isOn: Binding(
                    get: { viewModel.isSubscriptionActive },
                    set: { viewModel.setSubscriptionActive($0) }
                )
            ) {
                DebugMenuRowLabel(
                    title: L10n.DebugMenu.subscriptionActive,
                    subtitle: L10n.DebugMenu.subscriptionActiveSubtitle,
                    systemImage: "crown.fill",
                    color: Color(uiColor: AIThemeVisualStyle.accentColor)
                )
            }
            .accessibilityIdentifier(AccessibilityID.subscriptionActiveToggle)
        }
    }

    private var backendSection: some View {
        Section(L10n.DebugMenu.backendSectionTitle) {
            Toggle(
                isOn: Binding(
                    get: { viewModel.usesLocalhostBackend },
                    set: { _ in viewModel.toggleLocalhostBackend() }
                )
            ) {
                DebugMenuRowLabel(
                    title: L10n.Settings.localhostBackend,
                    subtitle: L10n.Settings.localhostBackendSubtitle,
                    systemImage: "server.rack",
                    color: .blue
                )
            }
            .accessibilityIdentifier(AccessibilityID.localhostToggle)

            Toggle(
                isOn: Binding(
                    get: { viewModel.usesLocalContentOnly },
                    set: { _ in viewModel.toggleLocalContentOnly() }
                )
            ) {
                DebugMenuRowLabel(
                    title: L10n.Settings.localContentOnly,
                    subtitle: L10n.Settings.localContentOnlySubtitle,
                    systemImage: "externaldrive.fill",
                    color: .indigo
                )
            }
            .accessibilityIdentifier(AccessibilityID.localContentToggle)

            Toggle(
                isOn: Binding(
                    get: { viewModel.usesDirectAI },
                    set: { _ in viewModel.toggleDirectAI() }
                )
            ) {
                DebugMenuRowLabel(
                    title: L10n.Settings.directAI,
                    subtitle: L10n.Settings.directAISubtitle,
                    systemImage: "key.fill",
                    color: .yellow
                )
            }
            .accessibilityIdentifier(AccessibilityID.directAIToggle)
        }
    }

    private var toolsSection: some View {
        Section(L10n.DebugMenu.toolsSectionTitle) {
            NavigationLink {
                DebugPulseConsoleView()
            } label: {
                DebugMenuRowLabel(
                    title: L10n.DebugMenu.pulse,
                    subtitle: L10n.DebugMenu.pulseSubtitle,
                    systemImage: "waveform.path.ecg",
                    color: .red
                )
            }
            .accessibilityIdentifier(AccessibilityID.pulse)
        }
    }

    private var backgroundSection: some View {
        Section(L10n.Home.backgroundStyleSwitcher) {
            ForEach(AppBackgroundStyle.allCases) { style in
                Button {
                    viewModel.selectBackgroundStyle(style)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: style.systemImageName)
                            .frame(width: 28)
                        Text(style.title)
                            .foregroundStyle(.primary)
                        Spacer()
                        if viewModel.backgroundStyle == style {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(
                                    Color(uiColor: AppAssetColor.fallbackBlue.uiColor)
                                )
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityIdentifier(AccessibilityID.backgroundStyle)
    }
}

private struct DebugMenuRowLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28)
        }
    }
}

private struct DebugPulseConsoleView: View {
    var body: some View {
        ConsoleView(mode: .network)
            .closeButtonHidden()
            .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
