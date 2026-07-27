import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var updateService: UpdateService
    @Environment(\.openSettings) private var openSettings
    @ObservedObject private var history = HistoryService.shared
    @AppStorage(Constants.shortcutKey) private var shortcut = DictationShortcut.function.rawValue
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
        let key = DictationShortcut(rawValue: shortcut)?.label ?? "Fn / Globe"
        return activationMode == ActivationMode.toggle.rawValue
            ? "Appuie sur \(key) pour démarrer ou terminer."
            : "Maintiens \(key) pour parler, puis relâche."
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

#Preview {
    MenuBarView()
        .environmentObject(AppState())
        .environmentObject(UpdateService())
}
