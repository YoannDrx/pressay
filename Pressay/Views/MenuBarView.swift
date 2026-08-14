import SwiftUI
import UniformTypeIdentifiers

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var updateService: UpdateService
    @ObservedObject private var history = HistoryService.shared
    @ObservedObject private var inbox = VoiceInboxService.shared
    @ObservedObject private var actionJournal = ActionJournalService.shared
    @ObservedObject private var modes = ModeStore.shared
    @ObservedObject private var account = AccountService.shared
    @AppStorage(Constants.activationModeKey) private var activationMode = Constants.defaultActivationMode
    @AppStorage(Constants.transcriptionEngineKey) private var transcriptionEngine = TranscriptionEngine.openAI.rawValue
    @State private var selectedTab = MenuBarTab.dictate
    private let onRequestClose: () -> Void

    init(onRequestClose: @escaping () -> Void = {}) {
        self.onRequestClose = onRequestClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabs
            Divider().opacity(0.55)
            header
            Divider().opacity(0.55)

            ScrollView(showsIndicators: false) {
                Group {
                    switch selectedTab {
                    case .dictate:
                        dictateTab
                    case .activity:
                        activityTab
                    case .account:
                        accountTab
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity)

            Divider().opacity(0.55)
            footer
        }
        .frame(width: 380)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.secondary.opacity(0.18))
        }
        .onAppear { appState.refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: .pressayMenuPanelWillOpen)) { _ in
            selectedTab = .dictate
        }
        .onChange(of: appState.isRecording) { _, active in
            if active { selectedTab = .dictate }
        }
        .onChange(of: appState.isTranscribing) { _, active in
            if active { selectedTab = .dictate }
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.16))
                    .frame(width: 38, height: 38)
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.system(size: 15, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Pressay")
                    .font(.system(size: 15, weight: .bold))
                Text(statusText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if account.state == .signedIn, let entitlement = account.entitlement {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(planLabel(entitlement.effectivePlan))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.blue)
                    if let email = account.account?.email {
                        Text(email)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            if appState.pendingCount > 0 {
                Label("\(appState.pendingCount)", systemImage: "tray.full.fill")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.blue.opacity(0.12), in: Capsule())
                    .accessibilityLabel("\(appState.pendingCount) éléments en attente")
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    private var tabs: some View {
        HStack(spacing: 5) {
            ForEach(MenuBarTab.allCases) { tab in
                Button {
                    selectedTab = tab
                    if tab == .account, account.state == .signedIn {
                        Task { await account.refresh() }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 15, weight: .semibold))
                        Text(tab.label)
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundStyle(selectedTab == tab ? Color.white : .secondary)
                    .frame(maxWidth: .infinity, minHeight: 49)
                    .background(
                        selectedTab == tab ? Color.accentColor : .clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 8)
    }

    private var dictateTab: some View {
        VStack(alignment: .leading, spacing: 11) {
            MenuBarCard(tint: statusColor) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .frame(width: 24, height: 24)
                        .background(statusColor.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusText)
                            .font(.system(size: 12, weight: .semibold))
                        Text(shortcutInstruction)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                if !DistributionChannel.current.supportsGlobalShortcuts {
                    Button(action: appState.toggleCaptureFromInterface) {
                        Label(
                            appState.isRecording ? "Terminer la dictée" : "Démarrer une dictée",
                            systemImage: appState.isRecording ? "stop.fill" : "mic.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.space, modifiers: [])
                }
            }

            MenuBarCard(tint: .blue) {
                HStack(spacing: 10) {
                    Label("Moteur", systemImage: transcriptionEngineValue == .openAI ? "cloud.fill" : "laptopcomputer")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text(transcriptionEngineValue.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(transcriptionEngineValue == .openAI ? .blue : .green)
                }
                Divider().opacity(0.4)
                HStack(spacing: 10) {
                    Label("Style", systemImage: selectedMode.symbolName)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Picker("", selection: selectedModeBinding) {
                        ForEach(modes.visibleModes) { mode in
                            Text(mode.name).tag(mode.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
            }

            if DistributionChannel.current.supportsSelectionTransformation,
               appState.keyboardService.transformationShortcutAvailable {
                Label(
                    "Transformer la sélection : \(transformationShortcutName)",
                    systemImage: "wand.and.stars"
                )
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 3)
            }

            if let message = appState.lastError ?? appState.lastNotice {
                Label(
                    message,
                    systemImage: appState.lastError == nil
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill"
                )
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(appState.lastError == nil ? .green : .orange)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
            }

            if appState.isTranscribing {
                Button(action: appState.cancelTranscription) {
                    Label("Annuler la transcription", systemImage: "xmark.circle")
                }
                .buttonStyle(MenuBarRowButtonStyle())
            }

            if let latest = history.entries.first {
                MenuBarCard(tint: .purple) {
                    HStack {
                        Label("Dernière dictée", systemImage: "quote.bubble.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.purple)
                        Spacer()
                        Text(latest.date, style: .relative)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    Button {
                        TextInjector.shared.copyToPasteboard(latest.text)
                        onRequestClose()
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Text(latest.text)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "doc.on.doc")
                                .foregroundStyle(.purple)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Copier la dernière dictée")
                }
            }
        }
    }

    private var activityTab: some View {
        VStack(alignment: .leading, spacing: 11) {
            if let latest = history.entries.first {
                MenuBarCard(tint: .purple) {
                    HStack {
                        Label("Dernière dictée", systemImage: "quote.bubble.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.purple)
                        Spacer()
                        Text(latest.date, style: .relative)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    Button {
                        TextInjector.shared.copyToPasteboard(latest.text)
                        onRequestClose()
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Text(latest.text)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "doc.on.doc")
                                .foregroundStyle(.purple)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Copier la dernière dictée")
                }
            } else {
                MenuBarCard(tint: .purple) {
                    Label("Aucune dictée pour le moment", systemImage: "waveform")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                ActivityCounter(
                    value: inbox.entries.count,
                    label: "Inbox",
                    icon: "tray.full.fill",
                    color: .blue,
                    action: showInboxWindow
                )
                ActivityCounter(
                    value: actionJournal.pendingEntries.count,
                    label: "À valider",
                    icon: "checkmark.shield.fill",
                    color: .orange,
                    action: showActionCenterWindow
                )
            }

            VStack(spacing: 2) {
                Button(action: showHistoryWindow) {
                    MenuCommandLabel("Historique complet", icon: "clock.arrow.circlepath", trailing: nil)
                }
                .buttonStyle(MenuBarRowButtonStyle())

                Button {
                    onRequestClose()
                    ModesWindowController.shared.show(
                        shortcutRouter: appState.keyboardService
                    )
                } label: {
                    Label(
                        DistributionChannel.current.supportsApplicationProfiles
                            ? "Styles et profils…"
                            : "Gérer les styles…",
                        systemImage: "square.grid.2x2"
                    )
                }
                .buttonStyle(MenuBarRowButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var accountTab: some View {
        MenuBarCard(tint: .green) {
            VStack(alignment: .leading, spacing: 11) {
                switch account.state {
                case .unavailable:
                    accountMessage(
                        "Le compte n’est pas disponible dans cette version.",
                        icon: "wrench.and.screwdriver.fill",
                        color: .secondary
                    )
                case .signedOut:
                    accountMessage(
                        "Connecte-toi pour retrouver ta formule et gérer tes Mac.",
                        icon: "person.crop.circle.badge.plus",
                        color: .blue
                    )
                    Button("Se connecter avec Google") {
                        Task { await account.signIn() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                case .signingIn:
                    accountMessage(
                        "Connexion sécurisée dans le navigateur…",
                        icon: "safari.fill",
                        color: .blue
                    )
                case .loading:
                    HStack(spacing: 9) {
                        ProgressView().controlSize(.small)
                        Text("Vérification du compte…")
                            .font(.system(size: 11))
                    }
                case .failed(let message):
                    accountMessage(
                        message,
                        icon: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                    if let requestID = account.requestID {
                        Text("Référence : \(requestID)")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                    Button("Réessayer") { Task { await account.refresh() } }
                case .signedIn:
                    signedInAccount
                }
                Divider().opacity(0.4)
                Label(
                    "Ni l’audio, ni les transcriptions, ni ta clé OpenAI ne sont envoyés au compte Pressay.",
                    systemImage: "lock.shield.fill"
                )
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var signedInAccount: some View {
        if let user = account.account {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 27))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName ?? user.email ?? "Compte Pressay")
                        .font(.system(size: 12, weight: .semibold))
                    if let email = user.email, user.displayName != nil {
                        Text(email)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let entitlement = account.entitlement {
                    Text(planLabel(entitlement.effectivePlan))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.green.opacity(0.13), in: Capsule())
                }
            }

            if let entitlement = account.entitlement {
                Divider().opacity(0.4)
                LabeledContent("Source du droit", value: entitlement.effectiveSource)
                if let end = entitlement.grantEnd ?? entitlement.subscriptionEnd {
                    LabeledContent(
                        "Valide jusqu’au",
                        value: end.formatted(date: .abbreviated, time: .omitted)
                    )
                }
                LabeledContent(
                    "Accès hors ligne",
                    value: entitlement.offlineValidUntil.formatted(date: .abbreviated, time: .omitted)
                )
            }
            LabeledContent("Mac actifs", value: "\(account.devices.count)")
                .font(.system(size: 10.5))
            Divider().opacity(0.4)
            HStack(spacing: 12) {
                Link("Gérer le compte ↗", destination: URL(string: "https://press-say.app/account")!)
                Spacer()
                Button("Actualiser") { Task { await account.refresh() } }
                Button("Déconnexion") { account.signOut() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func accountMessage(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 11))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        VStack(spacing: 1) {
            Button(action: showSettings) {
                MenuFooterCommandLabel("Réglages…", icon: "gearshape", shortcut: "⌘,")
            }
            .keyboardShortcut(",", modifiers: .command)
            .buttonStyle(MenuBarFooterButtonStyle())

            if DistributionChannel.current.usesSparkle {
                Button {
                    onRequestClose()
                    updateService.checkForUpdates()
                } label: {
                    MenuFooterCommandLabel(
                        "Rechercher les mises à jour…",
                        icon: "arrow.triangle.2.circlepath",
                        shortcut: nil
                    )
                }
                .disabled(!updateService.canCheckForUpdates)
                .buttonStyle(MenuBarFooterButtonStyle())
            }

            Button {
                onRequestClose()
                NSApp.activate(ignoringOtherApps: true)
                NSApp.orderFrontStandardAboutPanel(nil)
            } label: {
                MenuFooterCommandLabel("À propos de Pressay", icon: "info.circle", shortcut: nil)
            }
            .buttonStyle(MenuBarFooterButtonStyle())

            Divider().opacity(0.45).padding(.vertical, 3)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                MenuFooterCommandLabel("Quitter", icon: "xmark.square", shortcut: "⌘Q")
            }
            .keyboardShortcut("q", modifiers: .command)
            .buttonStyle(MenuBarFooterButtonStyle())
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
    }

    private var shortcutInstruction: String {
        guard DistributionChannel.current.supportsGlobalShortcuts else {
            return "Démarre la dictée ici. Le résultat sera copié ; la Voice Inbox est optionnelle."
        }
        let definition = appState.keyboardService.currentShortcut(for: .dictate)
        let key = definition?.displayName ?? "Fn / Globe"
        let isModifierOnly = definition?.side != nil
            || definition?.modifiers.contains(.function) == true
        return activationMode == ActivationMode.toggle.rawValue || !isModifierOnly
            ? "Appuie sur \(key) pour démarrer ou terminer."
            : "Maintiens \(key) pour parler, puis relâche."
    }

    private var transformationShortcutName: String {
        appState.keyboardService
            .currentShortcut(for: .transformSelection)?
            .displayName ?? "non défini"
    }

    private var selectedMode: ModeDefinition {
        modes.mode(withID: modes.selectedModeID)
            ?? NativeModeCatalog.visibleModes[0]
    }

    private var selectedModeBinding: Binding<UUID> {
        Binding(
            get: { modes.selectedModeID },
            set: { modes.selectedModeID = $0 }
        )
    }

    private var transcriptionEngineValue: TranscriptionEngine {
        TranscriptionEngine(rawValue: transcriptionEngine) ?? .openAI
    }

    private func showSettings() {
        onRequestClose()
        SettingsWindowController.shared.show(
            appState: appState,
            updateService: updateService
        )
    }

    private func planLabel(_ plan: String) -> String {
        switch plan {
        case "lifetime_byok": "Lifetime"
        case "pro_byok": "Pro BYOK"
        case "pro_cloud": "Pro Cloud"
        default: "Free"
        }
    }

    private func showHistoryWindow() {
        onRequestClose()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Historique Pressay"
        window.contentView = NSHostingView(rootView: HistoryView())
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showInboxWindow() {
        onRequestClose()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Voice Inbox Pressay"
        window.contentView = NSHostingView(rootView: VoiceInboxView())
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showActionCenterWindow() {
        onRequestClose()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Actions Pressay"
        window.contentView = NSHostingView(rootView: ActionCenterView())
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var statusIcon: String {
        if appState.isRecording { return "waveform" }
        if appState.isTranscribing { return "ellipsis" }
        if !appState.hasAPIKey { return "key.slash" }
        return "checkmark"
    }

    private var statusColor: Color {
        if appState.isRecording { return .red }
        if appState.isTranscribing { return .blue }
        if !appState.hasAPIKey { return .orange }
        return .green
    }

    private var statusText: String {
        if appState.isRecording { return "J’écoute…" }
        if appState.isTranscribing { return "Transcription en cours…" }
        if !appState.hasAPIKey { return "Clé API à configurer" }
        return "Prêt"
    }
}

extension Notification.Name {
    static let pressayMenuPanelWillOpen = Notification.Name(
        "fr.yodev.pressay.menu-panel-will-open"
    )
}

private enum MenuBarTab: String, CaseIterable, Identifiable {
    case dictate
    case activity
    case account

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dictate: "Dicter"
        case .activity: "Activité"
        case .account: "Compte"
        }
    }

    var icon: String {
        switch self {
        case .dictate: "waveform"
        case .activity: "clock.arrow.circlepath"
        case .account: "person.crop.circle"
        }
    }

    var color: Color {
        switch self {
        case .dictate: .blue
        case .activity: .purple
        case .account: .green
        }
    }
}

private struct MenuBarCard<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let tint: Color
    @ViewBuilder let content: Content

    init(tint: Color, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(tint.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(tint.opacity(contrast == .increased ? 0.48 : 0.16))
        }
    }
}

private struct ActivityCounter: View {
    let value: Int
    let label: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 22, height: 22)
                    .background(color.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(value)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(label)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct MenuCommandLabel: View {
    let title: String
    let icon: String
    let trailing: String?

    init(_ title: String, icon: String, trailing: String?) {
        self.title = title
        self.icon = icon
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon).frame(width: 16)
            Text(title)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.tertiary)
        }
    }
}

private struct MenuFooterCommandLabel: View {
    let title: String
    let icon: String
    let shortcut: String?

    init(_ title: String, icon: String, shortcut: String?) {
        self.title = title
        self.icon = icon
        self.shortcut = shortcut
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 17)
            Text(title)
                .font(.system(size: 11.5))
            Spacer()
            if let shortcut {
                Text(shortcut)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .padding(.horizontal, 7)
    }
}

private struct MenuBarRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .padding(.horizontal, 8)
            .background(
                configuration.isPressed ? Color.accentColor.opacity(0.14) : .clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(Rectangle())
    }
}

private struct MenuBarFooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? Color.primary : .secondary)
            .background(
                configuration.isPressed ? Color.primary.opacity(0.09) : .clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .contentShape(Rectangle())
    }
}

private enum VoiceInboxFilter: String, CaseIterable, Identifiable {
    case toProcess
    case today
    case archived
    case all

    var id: String { rawValue }
    var label: String {
        switch self {
        case .toProcess: "À traiter"
        case .today: "Aujourd’hui"
        case .archived: "Archivé"
        case .all: "Tout"
        }
    }
}

struct VoiceInboxView: View {
    @ObservedObject private var inbox = VoiceInboxService.shared
    @ObservedObject private var actionJournal = ActionJournalService.shared
    @State private var searchText = ""
    @State private var filter: VoiceInboxFilter = .toProcess

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack {
                    Label("Voice Inbox", systemImage: "tray.full")
                        .font(.headline)
                    Text("\(inbox.entries.filter { $0.status == .inbox }.count) à traiter")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        exportMarkdown()
                    } label: {
                        Label("Exporter", systemImage: "square.and.arrow.up")
                    }
                    .disabled(inbox.entries.isEmpty)
                    if !inbox.entries.isEmpty {
                        Button("Tout effacer", role: .destructive, action: inbox.clearAll)
                    }
                }
                HStack {
                    TextField("Rechercher dans l’Inbox", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                    Picker("Vue", selection: $filter) {
                        ForEach(VoiceInboxFilter.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 125)
                }
            }
            .padding()
            Divider()
            if let storageError = inbox.storageError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(storageError)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: inbox.clearStorageError) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Fermer l’erreur de stockage")
                }
                .padding(10)
                .background(.orange.opacity(0.08))
                Divider()
            }
            if inbox.entries.isEmpty {
                ContentUnavailableView(
                    "Inbox vide",
                    systemImage: "tray",
                    description: Text(
                        "Les dictées réalisées sans champ éditable apparaîtront ici."
                    )
                )
            } else if filteredEntries.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredEntries) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.title)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(entry.text)
                                            .font(.system(size: 12))
                                            .lineLimit(4)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(entry.date, style: .relative)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Button {
                                        TextInjector.shared.copyToPasteboard(entry.text)
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                    }
                                    .buttonStyle(.plain)
                                    .help("Copier")
                                    Menu {
                                        Button("Note Markdown") {
                                            actionJournal.propose(
                                                VoiceInboxActionFactory.note(from: entry)
                                            )
                                        }
                                        Button("Rappel") {
                                            actionJournal.propose(
                                                VoiceInboxActionFactory.reminder(from: entry)
                                            )
                                        }
                                        if let calendar = VoiceInboxActionFactory.calendar(from: entry) {
                                            Button("Événement calendrier") {
                                                actionJournal.propose(calendar)
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "wand.and.stars")
                                    }
                                    .menuStyle(.borderlessButton)
                                    .fixedSize()
                                    .help("Préparer une action")
                                    Button {
                                        inbox.toggleArchived(entry)
                                    } label: {
                                        Image(systemName: entry.status == .archived ? "tray.and.arrow.up" : "archivebox")
                                    }
                                    .buttonStyle(.plain)
                                    .help(entry.status == .archived ? "Remettre à traiter" : "Archiver")
                                    Button(role: .destructive) {
                                        inbox.delete(entry)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.plain)
                                }

                                if entry.project != nil || !entry.tags.isEmpty {
                                    HStack(spacing: 6) {
                                        if let project = entry.project {
                                            Label(project, systemImage: "folder")
                                                .font(.caption2)
                                                .foregroundStyle(.blue)
                                        }
                                        ForEach(entry.tags.filter { $0 != entry.project }, id: \.self) { tag in
                                            Text("#\(tag)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }

                                if !entry.tasks.isEmpty {
                                    VStack(alignment: .leading, spacing: 3) {
                                        ForEach(entry.tasks, id: \.self) { task in
                                            Label(task, systemImage: "square")
                                                .font(.caption)
                                        }
                                    }
                                }

                                if !entry.detectedDates.isEmpty {
                                    HStack(spacing: 5) {
                                        Image(systemName: "calendar")
                                        ForEach(entry.detectedDates, id: \.self) { date in
                                            Text(date, format: .dateTime.day().month().year())
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.purple)
                                }
                            }
                            .padding(11)
                            .background(
                                .secondary.opacity(0.07),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 520, idealWidth: 620, minHeight: 480, idealHeight: 620)
    }

    private var filteredEntries: [VoiceInboxEntry] {
        inbox.entries.filter { entry in
            let matchesFilter: Bool
            switch filter {
            case .toProcess: matchesFilter = entry.status == .inbox
            case .today: matchesFilter = Calendar.current.isDateInToday(entry.date)
            case .archived: matchesFilter = entry.status == .archived
            case .all: matchesFilter = true
            }
            guard matchesFilter else { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return [
                entry.title,
                entry.text,
                entry.project ?? "",
                entry.tags.joined(separator: " "),
                entry.tasks.joined(separator: " ")
            ].joined(separator: " ").localizedCaseInsensitiveContains(query)
        }
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "pressay-voice-inbox.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? Data(inbox.markdownExport().utf8).write(to: url, options: .atomic)
        }
    }
}

struct ActionCenterView: View {
    @ObservedObject private var journal = ActionJournalService.shared
    @State private var showsCompleted = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Actions sûres", systemImage: "checkmark.shield")
                    .font(.headline)
                Text("Aucune action externe n’est lancée sans validation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Journal", isOn: $showsCompleted)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Button("Nettoyer", action: journal.clearCompleted)
                    .disabled(journal.entries.allSatisfy { $0.status == .proposed })
            }
            .padding()
            Divider()

            if visibleEntries.isEmpty {
                ContentUnavailableView(
                    showsCompleted ? "Journal vide" : "Aucune action à valider",
                    systemImage: "checkmark.shield",
                    description: Text("Prépare une note, un rappel ou un événement depuis la Voice Inbox.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(visibleEntries) { entry in
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    Image(systemName: symbol(for: entry.proposal.kind))
                                        .foregroundStyle(color(for: entry.status))
                                    Text(entry.proposal.summary)
                                        .font(.system(size: 13, weight: .semibold))
                                    Spacer()
                                    Text(statusLabel(entry.status))
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(color(for: entry.status))
                                }
                                if let preview = entry.proposal.preview {
                                    Text(preview)
                                        .font(.system(size: 11, design: .monospaced))
                                        .lineLimit(8)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(8)
                                        .background(.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                                }
                                if let result = entry.resultSummary {
                                    Text(result)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if entry.status == .proposed {
                                    HStack {
                                        Label(
                                            riskLabel(entry.proposal.risk),
                                            systemImage: "eye"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        Spacer()
                                        Button("Refuser", role: .destructive) {
                                            journal.reject(entry)
                                        }
                                        Button("Valider") {
                                            journal.execute(entry)
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                }
                            }
                            .padding(12)
                            .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 560, minHeight: 480)
    }

    private var visibleEntries: [ActionJournalEntry] {
        showsCompleted ? journal.entries : journal.pendingEntries
    }

    private func symbol(for kind: ActionKind) -> String {
        switch kind {
        case .createNoteDraft: "note.text"
        case .createReminderDraft: "checklist"
        case .createCalendarDraft: "calendar"
        case .prepareTerminalCommand: "terminal"
        case .openURL: "link"
        default: "wand.and.stars"
        }
    }

    private func color(for status: ActionJournalStatus) -> Color {
        switch status {
        case .proposed: .blue
        case .executed: .green
        case .rejected: .secondary
        case .failed: .orange
        }
    }

    private func statusLabel(_ status: ActionJournalStatus) -> String {
        switch status {
        case .proposed: "À valider"
        case .executed: "Exécutée"
        case .rejected: "Refusée"
        case .failed: "Échec"
        }
    }

    private func riskLabel(_ risk: ActionRisk) -> String {
        switch risk {
        case .automatic: "Sans effet externe"
        case .preview: "Aperçu obligatoire"
        case .confirmationRequired: "Confirmation obligatoire"
        case .forbidden: "Interdite"
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState())
        .environmentObject(UpdateService())
}
