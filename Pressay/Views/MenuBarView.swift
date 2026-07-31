import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var updateService: UpdateService
    @Environment(\.openSettings) private var openSettings
    @ObservedObject private var history = HistoryService.shared
    @ObservedObject private var inbox = VoiceInboxService.shared
    @ObservedObject private var modes = ModeStore.shared
    @AppStorage(Constants.activationModeKey) private var activationMode = ActivationMode.hold.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
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
            .padding(.horizontal)
            .padding(.top, 9)

            Text(shortcutInstruction)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal)

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
                .frame(width: 150)
            }
            .padding(.horizontal)

            if appState.keyboardService.transformationShortcutAvailable {
                Label(
                    "Transformer la sélection : \(transformationShortcutName)",
                    systemImage: "wand.and.stars"
                )
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            }

            Button {
                ModesWindowController.shared.show(
                    shortcutRouter: appState.keyboardService
                )
            } label: {
                Label("Gérer les modes et profils…", systemImage: "slider.horizontal.3")
            }
            .padding(.horizontal, 4)

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
                .padding(.horizontal)
            }

            if appState.isTranscribing {
                Button(action: appState.cancelTranscription) {
                    Label("Annuler la transcription", systemImage: "xmark.circle")
                }
                .padding(.horizontal, 4)
            }

            Divider()

            if !inbox.entries.isEmpty {
                Button(action: showInboxWindow) {
                    Label(
                        "Voice Inbox · \(inbox.entries.count)",
                        systemImage: "tray.full"
                    )
                }
                .padding(.horizontal, 4)
                Divider()
            }

            if let latest = history.entries.first {
                Button(action: appState.copyLastTranscription) {
                    Label("Copier la dernière dictée", systemImage: "doc.on.doc")
                }
                .padding(.horizontal, 4)
                .help(latest.text)

                Menu {
                    ForEach(history.entries.prefix(6)) { entry in
                        Button {
                            TextInjector.shared.copyToPasteboard(entry.text)
                        } label: {
                            Text(preview(entry.text))
                        }
                    }
                    Divider()
                    Button("Voir tout…", action: showHistoryWindow)
                } label: {
                    Label("Historique chiffré", systemImage: "clock.arrow.circlepath")
                }
                .padding(.horizontal, 4)
                Divider()
            }

            Button {
                openSettings()
            } label: {
                Label("Réglages…", systemImage: "slider.horizontal.3")
            }
            .keyboardShortcut(",", modifiers: .command)
            .padding(.horizontal, 4)

            Button(action: updateService.checkForUpdates) {
                Label("Rechercher les mises à jour…", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!updateService.canCheckForUpdates)
            .padding(.horizontal, 4)

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quitter Pressay", systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .frame(width: 286)
        .buttonStyle(.plain)
        .onAppear { appState.refreshPermissions() }
    }

    private var shortcutInstruction: String {
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

    private func preview(_ text: String) -> String {
        text.count > 54 ? String(text.prefix(54)) + "…" : text
    }

    private func showHistoryWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 460),
            styleMask: [.titled, .closable],
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
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 500),
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

private struct VoiceInboxView: View {
    @ObservedObject private var inbox = VoiceInboxService.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Voice Inbox", systemImage: "tray.full")
                    .font(.headline)
                Spacer()
                if !inbox.entries.isEmpty {
                    Button("Tout effacer", action: inbox.clearAll)
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
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(inbox.entries) { entry in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.text)
                                        .textSelection(.enabled)
                                        .frame(
                                            maxWidth: .infinity,
                                            alignment: .leading
                                        )
                                    Text(entry.date, style: .relative)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Button {
                                    TextInjector.shared.copyToPasteboard(entry.text)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.plain)
                                Button(role: .destructive) {
                                    inbox.delete(entry)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
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
        .frame(minWidth: 390, minHeight: 420)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState())
        .environmentObject(UpdateService())
}
