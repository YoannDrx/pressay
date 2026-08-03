import SwiftUI
import UniformTypeIdentifiers

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var updateService: UpdateService
    @ObservedObject private var history = HistoryService.shared
    @ObservedObject private var inbox = VoiceInboxService.shared
    @ObservedObject private var actionJournal = ActionJournalService.shared
    @ObservedObject private var modes = ModeStore.shared
    @AppStorage(Constants.activationModeKey) private var activationMode = Constants.defaultActivationMode
    private let onRequestClose: () -> Void

    init(onRequestClose: @escaping () -> Void = {}) {
        self.onRequestClose = onRequestClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.14))
                        .frame(width: 34, height: 34)
                    Image(systemName: statusIcon)
                        .foregroundStyle(statusColor)
                        .font(.system(size: 14, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pressay").font(.headline)
                    Text(statusText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if appState.pendingCount > 0 {
                    Text("+\(appState.pendingCount)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(6)
                        .background(.blue.opacity(0.14), in: Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
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

                HStack(spacing: 8) {
                    Label("Mode", systemImage: selectedMode.symbolName)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Picker("", selection: selectedModeBinding) {
                        ForEach(modes.visibleModes) { mode in
                            Text(mode.name).tag(mode.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 156)
                }
                .padding(10)
                .background(
                    .secondary.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 10)
                )

                if DistributionChannel.current.supportsSelectionTransformation,
                   appState.keyboardService.transformationShortcutAvailable {
                    Label(
                        "Transformer la sélection : \(transformationShortcutName)",
                        systemImage: "wand.and.stars"
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }

                if let message = appState.lastError ?? appState.lastNotice {
                    Label(
                        message,
                        systemImage: appState.lastError == nil
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(appState.lastError == nil ? .green : .orange)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if appState.isTranscribing {
                    Button(action: appState.cancelTranscription) {
                        Label("Annuler la transcription", systemImage: "xmark.circle")
                    }
                    .buttonStyle(MenuBarRowButtonStyle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                if let latest = history.entries.first {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Label("Dernière dictée", systemImage: "quote.bubble")
                                .font(.system(size: 11, weight: .semibold))
                            Spacer()
                            Text(latest.date, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Button {
                            appState.copyLastTranscription()
                            onRequestClose()
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Text(latest.text)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "doc.on.doc")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(
                                .secondary.opacity(0.07),
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Copier la dernière dictée")
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 5)

                    Button(action: showHistoryWindow) {
                        Label("Ouvrir tout l’historique…", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(MenuBarRowButtonStyle())

                    Divider()
                }

                if !inbox.entries.isEmpty {
                    Button(action: showInboxWindow) {
                        Label(
                            "Voice Inbox · \(inbox.entries.count)",
                            systemImage: "tray.full"
                        )
                    }
                    .buttonStyle(MenuBarRowButtonStyle())
                }

                if !actionJournal.pendingEntries.isEmpty {
                    Button(action: showActionCenterWindow) {
                        Label(
                            "Actions à valider · \(actionJournal.pendingEntries.count)",
                            systemImage: "checkmark.shield"
                        )
                    }
                    .buttonStyle(MenuBarRowButtonStyle())
                }

                Button {
                    onRequestClose()
                    ModesWindowController.shared.show(
                        shortcutRouter: appState.keyboardService
                    )
                } label: {
                    Label(
                        DistributionChannel.current.supportsApplicationProfiles
                            ? "Modes et profils…"
                            : "Gérer les modes…",
                        systemImage: "square.grid.2x2"
                    )
                }
                .buttonStyle(MenuBarRowButtonStyle())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            VStack(spacing: 4) {
                Button {
                    onRequestClose()
                    if DistributionChannel.current == .appStore {
                        #if APP_STORE
                        SettingsWindowController.shared.show(
                            appState: appState,
                            updateService: updateService
                        )
                        #endif
                    } else {
                        SettingsWindowController.shared.show(
                            appState: appState,
                            updateService: updateService
                        )
                    }
                } label: {
                    Label("Réglages…", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: .command)
                .buttonStyle(MenuBarRowButtonStyle())

                if DistributionChannel.current.usesSparkle {
                    Button {
                        onRequestClose()
                        updateService.checkForUpdates()
                    } label: {
                        Label("Rechercher les mises à jour…", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(!updateService.canCheckForUpdates)
                    .buttonStyle(MenuBarRowButtonStyle())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quitter Pressay", systemImage: "power")
                    .foregroundStyle(.red)
            }
            .keyboardShortcut("q", modifiers: .command)
            .buttonStyle(MenuBarRowButtonStyle())
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .frame(width: 316)
        .onAppear { appState.refreshPermissions() }
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
