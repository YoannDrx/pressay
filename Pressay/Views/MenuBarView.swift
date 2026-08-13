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
    @AppStorage(Constants.openAITranscriptionProfileKey) private var openAIProfile = Constants.defaultOpenAITranscriptionProfile
    @State private var selectedTab = MenuBarTab.dictate
    private let onRequestClose: () -> Void

    init(onRequestClose: @escaping () -> Void = {}) {
        self.onRequestClose = onRequestClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            tabBar
            Divider().opacity(0.55)

            ScrollView(showsIndicators: false) {
                Group {
                    switch selectedTab {
                    case .dictate: dictateTab
                    case .activity: activityTab
                    case .account: accountTab
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity)

            Divider().opacity(0.55)
            persistentCommands
        }
        .frame(width: 380)
        .frame(minHeight: 520, idealHeight: 660, maxHeight: 700)
        .background(.regularMaterial)
        .onAppear {
            appState.refreshPermissions()
            if appState.isRecording || appState.isTranscribing {
                selectedTab = .dictate
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .pressayPopoverWillOpen)
        ) { _ in
            selectedTab = .dictate
        }
        .onDisappear { selectedTab = .dictate }
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
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.system(size: 15, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Pressay").font(.system(size: 15, weight: .bold))
                Text(statusText).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            if appState.pendingCount > 0 {
                Text("\(appState.pendingCount) en attente")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .accessibilityElement(children: .combine)
    }

    private var tabBar: some View {
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
                            .font(.system(size: 14, weight: .semibold))
                        Text(tab.label).font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        selectedTab == tab ? Color.accentColor.opacity(0.12) : .clear,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var dictateTab: some View {
        VStack(alignment: .leading, spacing: 13) {
            MenuBarCard(title: "DICTÉE", icon: "mic.fill") {
                VStack(alignment: .leading, spacing: 11) {
                    Label(shortcutInstruction, systemImage: "keyboard")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

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

                    if transcriptionEngine == TranscriptionEngine.openAI.rawValue {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("PROFIL OPENAI")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("Profil OpenAI", selection: $openAIProfile) {
                                ForEach(OpenAITranscriptionProfile.allCases) { profile in
                                    Text(profile.label).tag(profile.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            Text(currentOpenAIProfile.detail)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Label("WhisperKit local · aucun coût API", systemImage: "lock.shield.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.green)
                    }

                    Divider().opacity(0.45)
                    LabeledContent {
                        Picker("Style d’écriture", selection: selectedModeBinding) {
                            ForEach(modes.visibleModes) { mode in
                                Text(mode.name).tag(mode.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 164)
                    } label: {
                        Label("Style d’écriture", systemImage: selectedMode.symbolName)
                            .font(.system(size: 11, weight: .medium))
                    }
                }
            }

            if let message = appState.lastError ?? appState.lastNotice {
                Label(
                    message,
                    systemImage: appState.lastError == nil
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill"
                )
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(appState.lastError == nil ? .green : .orange)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }

            if let preview = appState.realtimeTranscriptPreview,
               !preview.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Texte en direct", systemImage: "text.bubble.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(preview)
                        .font(.system(size: 11))
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Transcription en direct")
                }
                .padding(10)
                .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }

            if let model = appState.lastTranscriptionModel {
                LabeledContent("Dernier moteur", value: model)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if let metrics = appState.lastTranscriptionMetrics {
                HStack(spacing: 12) {
                    if let connection = metrics.connectionSeconds {
                        Label(
                            "Connexion \(connection.formatted(.number.precision(.fractionLength(2)))) s",
                            systemImage: "network"
                        )
                    }
                    if let firstText = metrics.timeToFirstByteSeconds {
                        Label(
                            "Premier texte \(firstText.formatted(.number.precision(.fractionLength(2)))) s",
                            systemImage: "text.bubble"
                        )
                    }
                    Label(
                        "Final \(metrics.totalSeconds.formatted(.number.precision(.fractionLength(2)))) s",
                        systemImage: "checkmark.circle"
                    )
                }
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
            }

            if let reason = appState.lastTranscriptionFallbackReason {
                Label("Repli utilisé : \(reason)", systemImage: "arrow.triangle.branch")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if appState.isTranscribing {
                Button(action: appState.cancelTranscription) {
                    Label("Annuler la transcription", systemImage: "xmark.circle")
                }
                .buttonStyle(MenuBarRowButtonStyle())
            }

            if DistributionChannel.current.supportsSelectionTransformation,
               appState.keyboardService.transformationShortcutAvailable {
                Label(
                    "Transformer la sélection : \(transformationShortcutName)",
                    systemImage: "wand.and.stars"
                )
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var activityTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            MenuBarCard(title: "ACTIVITÉ RÉCENTE", icon: "clock.arrow.circlepath") {
                if let latest = history.entries.first {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Dernière dictée").font(.system(size: 11, weight: .semibold))
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
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                        .help("Copier la dernière dictée")
                    }
                } else {
                    ContentUnavailableView(
                        "Aucune dictée",
                        systemImage: "waveform",
                        description: Text("Ta prochaine transcription apparaîtra ici.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 130)
                }
            }

            Button(action: showHistoryWindow) {
                MenuCommandLabel("Historique complet", icon: "clock", trailing: nil)
            }
            .buttonStyle(MenuBarRowButtonStyle())

            Button(action: showInboxWindow) {
                MenuCommandLabel("Voice Inbox", icon: "tray.full", trailing: "\(inbox.entries.count)")
            }
            .buttonStyle(MenuBarRowButtonStyle())

            Button(action: showActionCenterWindow) {
                MenuCommandLabel("Actions à valider", icon: "checkmark.shield", trailing: "\(actionJournal.pendingEntries.count)")
            }
            .buttonStyle(MenuBarRowButtonStyle())

            Button {
                onRequestClose()
                ModesWindowController.shared.show(shortcutRouter: appState.keyboardService)
            } label: {
                MenuCommandLabel(
                    DistributionChannel.current.supportsApplicationProfiles
                        ? "Styles et profils"
                        : "Gérer les styles",
                    icon: "square.grid.2x2",
                    trailing: nil
                )
            }
            .buttonStyle(MenuBarRowButtonStyle())
        }
    }

    @ViewBuilder
    private var accountTab: some View {
        MenuBarCard(title: "COMPTE PRESSAY", icon: "person.crop.circle") {
            VStack(alignment: .leading, spacing: 11) {
                switch account.state {
                case .unavailable:
                    Label("Compte indisponible dans cette build", systemImage: "wrench.and.screwdriver")
                        .foregroundStyle(.secondary)
                case .signedOut:
                    Text("Connecte-toi pour synchroniser tes droits et gérer tes Mac.")
                        .foregroundStyle(.secondary)
                    Button("Se connecter à Pressay") {
                        Task { await account.signIn() }
                    }
                    .buttonStyle(.borderedProminent)
                case .signingIn:
                    Label("Connexion sécurisée dans le navigateur…", systemImage: "safari")
                case .loading:
                    HStack { ProgressView().controlSize(.small); Text("Vérification du compte…") }
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button("Réessayer") { Task { await account.refresh() } }
                case .signedIn:
                    signedInAccountContent
                }
                Text("Le compte ne reçoit ni l’audio, ni les transcriptions, ni ta clé OpenAI.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 11))
        }
    }

    @ViewBuilder
    private var signedInAccountContent: some View {
        if let user = account.account {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(user.displayName ?? user.email ?? "Compte Pressay")
                        .font(.system(size: 13, weight: .semibold))
                    if let email = user.email, user.displayName != nil {
                        Text(email).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let entitlement = account.entitlement {
                    Text(planLabel(entitlement.effectivePlan))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
            }
            if let entitlement = account.entitlement {
                Divider().opacity(0.45)
                LabeledContent("Source du droit", value: entitlement.effectiveSource)
                if let end = entitlement.grantEnd ?? entitlement.subscriptionEnd {
                    LabeledContent("Valide jusqu’au", value: end.formatted(date: .abbreviated, time: .omitted))
                }
                LabeledContent(
                    "Accès hors ligne",
                    value: entitlement.offlineValidUntil.formatted(date: .abbreviated, time: .omitted)
                )
            }
            HStack {
                LabeledContent("Mac actifs", value: "\(account.devices.count)")
                Link(
                    "Gérer ↗",
                    destination: URL(string: "https://press-say.app/account")!
                )
            }
            Divider().opacity(0.45)
            HStack {
                Link("Gérer l’abonnement ↗", destination: URL(string: "https://press-say.app/account")!)
                Spacer()
                Button("Actualiser") { Task { await account.refresh() } }
                Button("Se déconnecter") { account.signOut() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var persistentCommands: some View {
        VStack(spacing: 2) {
            Button(action: showSettings) {
                MenuCommandLabel("Réglages…", icon: "gearshape", trailing: "⌘,")
            }
            .keyboardShortcut(",", modifiers: .command)
            .buttonStyle(MenuBarRowButtonStyle())

            if DistributionChannel.current.usesSparkle {
                Button {
                    onRequestClose()
                    updateService.checkForUpdates()
                } label: {
                    MenuCommandLabel("Rechercher les mises à jour…", icon: "arrow.triangle.2.circlepath", trailing: nil)
                }
                .disabled(!updateService.canCheckForUpdates)
                .buttonStyle(MenuBarRowButtonStyle())
            }

            Button {
                onRequestClose()
                NSApp.activate(ignoringOtherApps: true)
                NSApp.orderFrontStandardAboutPanel(nil)
            } label: {
                MenuCommandLabel("À propos de Pressay", icon: "info.circle", trailing: nil)
            }
            .buttonStyle(MenuBarRowButtonStyle())

            Divider().opacity(0.45).padding(.vertical, 3)
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                MenuCommandLabel("Quitter Pressay", icon: "xmark.square", trailing: "⌘Q")
            }
            .keyboardShortcut("q", modifiers: .command)
            .buttonStyle(MenuBarRowButtonStyle())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var currentOpenAIProfile: OpenAITranscriptionProfile {
        OpenAITranscriptionProfile(rawValue: openAIProfile) ?? .liveQuality
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
        statusPresentation.icon
    }

    private var statusColor: Color {
        switch statusPresentation.tone {
        case .ready: .green
        case .recording: .red
        case .working: .blue
        case .attention: .orange
        }
    }

    private var statusText: String {
        statusPresentation.text
    }

    private var statusPresentation: MenuBarOperationalStatus {
        MenuBarOperationalStatus.resolve(
            isRecording: appState.isRecording,
            isTranscribing: appState.isTranscribing,
            transcriptionEngine: transcriptionEngine,
            hasAPIKey: appState.hasAPIKey,
            error: appState.lastError
        )
    }
}

struct MenuBarOperationalStatus: Equatable {
    enum Tone: Equatable {
        case ready
        case recording
        case working
        case attention
    }

    let icon: String
    let text: String
    let tone: Tone

    static func resolve(
        isRecording: Bool,
        isTranscribing: Bool,
        transcriptionEngine: String,
        hasAPIKey: Bool,
        error: String?
    ) -> Self {
        if isRecording {
            return Self(icon: "waveform", text: "J’écoute…", tone: .recording)
        }
        if isTranscribing {
            return Self(
                icon: "ellipsis",
                text: "Transcription en cours…",
                tone: .working
            )
        }
        if let error, !error.isEmpty {
            return Self(
                icon: "exclamationmark.triangle.fill",
                text: error,
                tone: .attention
            )
        }
        if transcriptionEngine == TranscriptionEngine.openAI.rawValue,
           !hasAPIKey {
            return Self(
                icon: "key.slash",
                text: "Clé API à configurer",
                tone: .attention
            )
        }
        if transcriptionEngine == TranscriptionEngine.whisperKit.rawValue {
            return Self(
                icon: "checkmark",
                text: "Prêt · WhisperKit local",
                tone: .ready
            )
        }
        return Self(icon: "checkmark", text: "Prêt", tone: .ready)
    }
}

extension Notification.Name {
    static let pressayPopoverWillOpen = Notification.Name(
        "fr.yodev.pressay.popover-will-open"
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
}

private struct MenuBarCard<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    init(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    .secondary.opacity(contrast == .increased ? 0.34 : 0.12)
                )
        }
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
            Image(systemName: icon)
                .frame(width: 16)
            Text(title)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.tertiary)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct MenuBarRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuBarRowButtonBody(configuration: configuration)
    }

    private struct MenuBarRowButtonBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .padding(.horizontal, 8)
                .background(
                    configuration.isPressed
                        ? Color.accentColor.opacity(0.16)
                        : isHovering
                            ? Color.primary.opacity(0.065)
                            : .clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .contentShape(Rectangle())
                .onHover { isHovering = $0 }
        }
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
