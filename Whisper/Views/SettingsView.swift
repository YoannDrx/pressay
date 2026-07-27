import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var metrics = PerformanceMetricsService.shared

    @State private var apiKeyInput = ""
    @State private var isValidating = false
    @State private var validationMessage: ValidationMessage?

    @AppStorage(Constants.transcriptionLanguageKey)
    private var language = Constants.defaultTranscriptionLanguage
    @AppStorage(Constants.transcriptionModelKey)
    private var model = Constants.defaultTranscriptionModel
    @AppStorage(Constants.vocabularyProfileKey)
    private var vocabularyProfile = "development"
    @AppStorage(Constants.technicalVocabularyKey)
    private var customVocabulary = ""
    @AppStorage(Constants.shortcutKey)
    private var shortcut = DictationShortcut.function.rawValue
    @AppStorage(Constants.activationModeKey)
    private var activationMode = ActivationMode.hold.rawValue
    @AppStorage(Constants.historyEnabledKey)
    private var historyEnabled = true
    @AppStorage(Constants.historyRetentionDaysKey)
    private var historyRetentionDays = 1
    @AppStorage(Constants.metricsEnabledKey)
    private var metricsEnabled = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    permissionsSection
                    apiSection
                    recognitionSection
                    shortcutSection
                    privacySection
                    aboutSection
                }
                .padding(24)
            }
            footer
        }
        .frame(width: 520, height: 760)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { appState.refreshPermissions() }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            appState.refreshPermissions()
        }
        .onChange(of: historyEnabled) { _, _ in HistoryService.shared.applyPreferences() }
        .onChange(of: historyRetentionDays) { _, _ in HistoryService.shared.applyPreferences() }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 48, height: 48)
                    .shadow(color: .accentColor.opacity(0.22), radius: 10, y: 4)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Whisper")
                        .font(.system(size: 18, weight: .bold))
                    Text("La dictée qui reste hors de ton chemin")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("v\(appVersion)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.08), in: Capsule())
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            Divider().opacity(0.5)
        }
    }

    private var permissionsSection: some View {
        SettingsSection(title: "DÉMARRAGE", icon: "checkmark.shield") {
            VStack(spacing: 12) {
                permissionRow(
                    title: "Microphone",
                    detail: "Nécessaire pour enregistrer la dictée.",
                    granted: appState.hasMicrophonePermission,
                    action: appState.requestMicrophonePermission
                )
                Divider().opacity(0.45)
                permissionRow(
                    title: "Accessibilité",
                    detail: "Nécessaire uniquement pour coller automatiquement.",
                    granted: appState.hasAccessibilityPermission,
                    action: appState.requestAccessibilityPermission
                )
            }
        }
    }

    private var apiSection: some View {
        SettingsSection(title: "API OPENAI", icon: "key.fill") {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 9) {
                    SecureField("sk-…", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                    Button(isValidating ? "Validation…" : "Valider") { validateKey() }
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating)
                }
                HStack {
                    Label(
                        appState.hasAPIKey ? "Clé vérifiée dans le Trousseau" : "Clé non configurée",
                        systemImage: appState.hasAPIKey ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                    )
                    .foregroundStyle(appState.hasAPIKey ? .green : .orange)
                    .font(.system(size: 11, weight: .medium))
                    Spacer()
                    if appState.hasAPIKey {
                        Button("Réinitialiser", action: appState.clearAPIKey)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                    Link("Créer une clé ↗", destination: URL(string: "https://platform.openai.com/api-keys")!)
                        .font(.system(size: 11))
                }
                if let validationMessage {
                    Text(validationMessage.text)
                        .font(.system(size: 10))
                        .foregroundStyle(validationMessage.success ? .green : .orange)
                }
                Text("La validation utilise uniquement l’endpoint de transcription, donc les clés restreintes compatibles sont acceptées.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var recognitionSection: some View {
        SettingsSection(title: "RECONNAISSANCE", icon: "waveform.badge.magnifyingglass") {
            VStack(alignment: .leading, spacing: 13) {
                settingPicker(title: "Langue", detail: "Une langue explicite réduit latence et erreurs.", selection: $language) {
                    Text("Français").tag("fr")
                    Text("Anglais").tag("en")
                    Text("Automatique").tag("")
                }
                Divider().opacity(0.45)
                settingPicker(title: "Modèle", detail: "Même API, compromis coût / précision.", selection: $model) {
                    ForEach(TranscriptionModel.allCases) { item in
                        Text(item.label).tag(item.rawValue)
                    }
                }
                Divider().opacity(0.45)
                settingPicker(title: "Profil de vocabulaire", detail: "Seul le profil actif est envoyé avec l’audio.", selection: $vocabularyProfile) {
                    Text("Développement").tag("development")
                    Text("Général").tag("general")
                    Text("Personnalisé").tag("custom")
                }
                if vocabularyProfile == "custom" {
                    TextEditor(text: $customVocabulary)
                        .font(.system(size: 11, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(7)
                        .frame(height: 70)
                        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    Text("Noms propres, produits et acronymes séparés par des virgules.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var shortcutSection: some View {
        SettingsSection(title: "DÉCLENCHEMENT", icon: "keyboard") {
            VStack(spacing: 13) {
                settingPicker(title: "Raccourci", detail: "Choisis une touche modificatrice droite dédiée.", selection: $shortcut) {
                    ForEach(DictationShortcut.allCases) { item in
                        Text(item.label).tag(item.rawValue)
                    }
                }
                Divider().opacity(0.45)
                settingPicker(title: "Mode", detail: activationMode == ActivationMode.hold.rawValue
                    ? "Maintiens pour parler, relâche pour envoyer."
                    : "Appuie une fois pour démarrer, une fois pour envoyer.", selection: $activationMode) {
                    ForEach(ActivationMode.allCases) { item in
                        Text(item.label).tag(item.rawValue)
                    }
                }
            }
        }
    }

    private var privacySection: some View {
        SettingsSection(title: "CONFIDENTIALITÉ ET MESURES", icon: "lock.shield") {
            VStack(alignment: .leading, spacing: 13) {
                Toggle("Conserver un historique local chiffré", isOn: $historyEnabled)
                    .font(.system(size: 12, weight: .medium))
                if historyEnabled {
                    settingPicker(title: "Rétention", detail: "Suppression automatique sur ce Mac.", selection: $historyRetentionDays) {
                        Text("24 heures").tag(1)
                        Text("7 jours").tag(7)
                        Text("30 jours").tag(30)
                    }
                }
                Divider().opacity(0.45)
                Toggle("Mesurer les temps de traitement localement", isOn: $metricsEnabled)
                    .font(.system(size: 12, weight: .medium))
                Text("Optionnel : uniquement des durées agrégées, jamais l’audio ni le texte, aucun envoi.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                if metricsEnabled {
                    HStack(spacing: 12) {
                        ForEach(MetricStep.allCases, id: \.rawValue) { step in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.label).font(.system(size: 9)).foregroundStyle(.secondary)
                                Text(metricText(step)).font(.system(size: 11, weight: .semibold, design: .rounded))
                            }
                        }
                        Spacer()
                        Button("Réinitialiser") { metrics.reset() }
                            .font(.system(size: 10))
                    }
                    .id(metrics.revision)
                }
            }
        }
    }

    private var aboutSection: some View {
        SettingsSection(title: "À PROPOS", icon: "info.circle") {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Whisper for macOS").font(.system(size: 12, weight: .semibold))
                    Text("Audio temporaire · Historique AES-256 · Aucune télémétrie distante")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Link("Confidentialité", destination: URL(string: "https://github.com/YoannDrx/whisper/blob/main/PRIVACY.md")!)
                    .font(.system(size: 10))
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            HStack {
                Text("Prêt pour les dictées courtes comme longues.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quitter") { NSApplication.shared.terminate(nil) }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
    }

    private func permissionRow(
        title: String,
        detail: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(granted ? .green : .orange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Autoriser", action: action)
            } else {
                Text("Accordée").font(.system(size: 10, weight: .medium)).foregroundStyle(.green)
            }
        }
    }

    private func settingPicker<Value: Hashable, Content: View>(
        title: String,
        detail: String,
        selection: Binding<Value>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: selection, content: content)
                .labelsHidden()
                .frame(width: 160)
        }
    }

    private func validateKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        isValidating = true
        validationMessage = nil
        Task {
            let valid = await appState.updateAPIKey(key)
            isValidating = false
            validationMessage = ValidationMessage(
                success: valid,
                text: valid ? "Clé vérifiée et enregistrée." : "La clé ou son droit de transcription est invalide."
            )
            if valid { apiKeyInput = "" }
        }
    }

    private func metricText(_ step: MetricStep) -> String {
        guard let value = metrics.average(for: step) else { return "—" }
        return value < 1 ? "\(Int(value * 1_000)) ms" : String(format: "%.1f s", value)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2"
    }

    private struct ValidationMessage {
        let success: Bool
        let text: String
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            content
                .padding(15)
                .background(
                    Color(nsColor: .controlBackgroundColor).opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.primary.opacity(0.06), lineWidth: 1)
                )
        }
    }
}

#Preview {
    SettingsView().environmentObject(AppState())
}
