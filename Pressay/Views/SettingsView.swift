import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var updateService: UpdateService
    @ObservedObject private var metrics = PerformanceMetricsService.shared
    @ObservedObject private var modes = ModeStore.shared

    @State private var apiKeyInput = ""
    @State private var isValidating = false
    @State private var validationMessage: ValidationMessage?
    @State private var diagnosticsMessage: String?

    @AppStorage(Constants.transcriptionLanguageKey)
    private var language = Constants.defaultTranscriptionLanguage
    @AppStorage(Constants.transcriptionModelKey)
    private var model = Constants.defaultTranscriptionModel
    @AppStorage(Constants.processingModelKey)
    private var processingModel = Constants.defaultProcessingModel
    @AppStorage(Constants.vocabularyProfileKey)
    private var vocabularyProfile = "development"
    @AppStorage(Constants.technicalVocabularyKey)
    private var customVocabulary = ""
    @AppStorage(Constants.activationModeKey)
    private var activationMode = ActivationMode.hold.rawValue
    @AppStorage(Constants.historyEnabledKey)
    private var historyEnabled = true
    @AppStorage(Constants.historyRetentionDaysKey)
    private var historyRetentionDays = 1
    @AppStorage(Constants.inboxEnabledKey)
    private var inboxEnabled = false
    @AppStorage(Constants.inboxRetentionDaysKey)
    private var inboxRetentionDays = 30
    @AppStorage(Constants.metricsEnabledKey)
    private var metricsEnabled = false
    @AppStorage(Constants.hudPositionKey)
    private var hudPosition = HUDPosition.bottomCenter.rawValue
    @AppStorage(Constants.hudSizeKey)
    private var hudSize = HUDSize.comfortable.rawValue
    @AppStorage(Constants.hudResultDurationKey)
    private var hudResultDuration = HUDResultDuration.fast.rawValue
    @AppStorage(Constants.hudShowsResultActionsKey)
    private var hudShowsResultActions = true

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    permissionsSection
                    apiSection
                    recognitionSection
                    hudSection
                    modesSection
                    if DistributionChannel.current.supportsGlobalShortcuts {
                        shortcutSection
                    }
                    privacySection
                    if DistributionChannel.current.usesSparkle {
                        updatesSection
                    }
                    aboutSection
                }
                .padding(24)
            }
            footer
        }
        .frame(width: 520, height: 820)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { appState.refreshPermissions() }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            appState.refreshPermissions()
        }
        .onChange(of: historyEnabled) { _, _ in HistoryService.shared.applyPreferences() }
        .onChange(of: historyRetentionDays) { _, _ in HistoryService.shared.applyPreferences() }
        .onChange(of: inboxEnabled) { _, _ in VoiceInboxService.shared.applyPreferences() }
        .onChange(of: inboxRetentionDays) { _, _ in VoiceInboxService.shared.applyPreferences() }
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
                    Text("Pressay")
                        .font(.system(size: 18, weight: .bold))
                    Text("Ta barre de commande vocale sur macOS")
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
                if DistributionChannel.current.supportsAccessibility {
                    Divider().opacity(0.45)
                    permissionRow(
                        title: "Accessibilité",
                        detail: "Identifie la cible, protège les champs sensibles et remplace une sélection.",
                        granted: appState.hasAccessibilityPermission,
                        action: appState.requestAccessibilityPermission
                    )
                } else {
                    Divider().opacity(0.45)
                    Label(
                        "Version App Store : copie et Voice Inbox, sans contrôle des autres applications.",
                        systemImage: "checkmark.shield"
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
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
                Text("La validation teste la transcription. Les modes de transformation exigent aussi l’accès à la Responses API.")
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
            VStack(alignment: .leading, spacing: 13) {
                LabeledContent {
                    ShortcutRecorderField(
                        router: appState.keyboardService,
                        action: .dictate
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dictée")
                            .font(.system(size: 12, weight: .medium))
                        Text("Un modificateur seul ou une combinaison globale.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                Divider().opacity(0.45)
                LabeledContent {
                    ShortcutRecorderField(
                        router: appState.keyboardService,
                        action: .correctLastInsertion
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Corriger la dernière insertion")
                            .font(.system(size: 12, weight: .medium))
                        Text("Sélection sûre, instruction vocale puis aperçu.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                Divider().opacity(0.45)
                LabeledContent {
                    ShortcutRecorderField(
                        router: appState.keyboardService,
                        action: .transformSelection
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Transformation")
                            .font(.system(size: 12, weight: .medium))
                        Text("Parle pour transformer la sélection courante.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                Divider().opacity(0.45)
                settingPicker(title: "Mode", detail: activationMode == ActivationMode.hold.rawValue
                    ? "Maintiens le modificateur pour parler, relâche pour envoyer. Une combinaison classique bascule début/fin."
                    : "Appuie une fois pour démarrer, une fois pour envoyer.", selection: $activationMode) {
                    ForEach(ActivationMode.allCases) { item in
                        Text(item.label).tag(item.rawValue)
                    }
                }
            }
        }
    }

    private var modesSection: some View {
        SettingsSection(title: "MODES", icon: "wand.and.stars") {
            VStack(alignment: .leading, spacing: 13) {
                settingPicker(
                    title: "Mode par défaut",
                    detail: "Fidèle reste local au pipeline ; les autres transforment le texte après transcription.",
                    selection: selectedModeBinding
                ) {
                    ForEach(modes.visibleModes) { mode in
                        Text(mode.name).tag(mode.id)
                    }
                }
                Divider().opacity(0.45)
                settingPicker(
                    title: "Traitement cloud",
                    detail: "Modèle rapide pour nettoyage, structure et transformation.",
                    selection: $processingModel
                ) {
                    Text("GPT-5.6 Luna").tag("gpt-5.6-luna")
                    Text("GPT-5.6 Terra").tag("gpt-5.6-terra")
                    Text("GPT-5.6 Sol").tag("gpt-5.6-sol")
                }
                Label(
                    "Les modes « Cloud autorisé » s’exécutent directement. Seules leurs sources autorisées sont envoyées et store: false désactive leur conservation comme état applicatif.",
                    systemImage: "lock.shield"
                )
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                Button(
                    DistributionChannel.current.supportsApplicationProfiles
                        ? "Gérer les modes et profils d’app…"
                        : "Gérer les modes…"
                ) {
                    ModesWindowController.shared.show(
                        shortcutRouter: appState.keyboardService
                    )
                }
            }
        }
    }

    private var hudSection: some View {
        SettingsSection(title: "HUD", icon: "rectangle.inset.filled") {
            VStack(alignment: .leading, spacing: 13) {
                settingPicker(
                    title: "Position",
                    detail: "Écran qui contient le pointeur au début de la dictée.",
                    selection: $hudPosition
                ) {
                    ForEach(HUDPosition.allCases) { position in
                        Text(position.label).tag(position.rawValue)
                    }
                }
                Divider().opacity(0.45)
                settingPicker(
                    title: "Taille",
                    detail: "Compacte ou confortable selon ton espace de travail.",
                    selection: $hudSize
                ) {
                    ForEach(HUDSize.allCases) { size in
                        Text(size.label).tag(size.rawValue)
                    }
                }
                Divider().opacity(0.45)
                settingPicker(
                    title: "Résultat",
                    detail: "Durée avant disparition ; le survol met le délai en pause.",
                    selection: $hudResultDuration
                ) {
                    ForEach(HUDResultDuration.allCases) { duration in
                        Text(duration.label).tag(duration.rawValue)
                    }
                }
                Toggle(
                    "Afficher Copier, Retranscrire, Brut/Final et Annuler",
                    isOn: $hudShowsResultActions
                )
                .font(.system(size: 11, weight: .medium))
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
                Toggle(
                    "Conserver les dictées sans cible dans la Voice Inbox",
                    isOn: $inboxEnabled
                )
                .font(.system(size: 12, weight: .medium))
                if inboxEnabled {
                    settingPicker(
                        title: "Rétention Inbox",
                        detail: "Stockage local chiffré, distinct de l’historique.",
                        selection: $inboxRetentionDays
                    ) {
                        Text("7 jours").tag(7)
                        Text("30 jours").tag(30)
                        Text("90 jours").tag(90)
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
                Divider().opacity(0.45)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Diagnostics exportables")
                            .font(.system(size: 12, weight: .medium))
                        Text("Versions, configuration non sensible et durées agrégées uniquement.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Exporter…", action: exportDiagnostics)
                        .accessibilityHint(
                            "Crée un fichier JSON sans audio, texte, sélection ni clé API"
                        )
                }
                if let diagnosticsMessage {
                    Text(diagnosticsMessage)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(diagnosticsMessage)
                }
            }
        }
    }

    private var aboutSection: some View {
        SettingsSection(title: "À PROPOS", icon: "info.circle") {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(DistributionChannel.current.displayName)
                        .font(.system(size: 12, weight: .semibold))
                    Text("Audio temporaire · Historique AES-256 · Aucune télémétrie distante")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Link("Confidentialité", destination: URL(string: "https://github.com/YoannDrx/pressay/blob/main/PRIVACY.md")!)
                    .font(.system(size: 10))
            }
        }
    }

    private var updatesSection: some View {
        SettingsSection(title: "MISES À JOUR", icon: "arrow.triangle.2.circlepath") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(
                    "Inclure les versions bêta",
                    isOn: $updateService.includeBetaUpdates
                )
                .font(.system(size: 12, weight: .medium))
                Text(
                    updateService.includeBetaUpdates
                        ? "Les bêtas peuvent être instables. Les versions stables restent toujours proposées."
                        : "Seules les versions stables sont proposées."
                )
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                Button("Rechercher une mise à jour") {
                    updateService.checkForUpdates()
                }
                .disabled(!updateService.canCheckForUpdates)
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

    private var selectedModeBinding: Binding<UUID> {
        Binding(
            get: { modes.selectedModeID },
            set: { modes.selectedModeID = $0 }
        )
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

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "pressay-diagnostics.json"
        panel.title = "Exporter les diagnostics Pressay"
        panel.message = "Le fichier ne contient ni audio, ni texte dicté, ni sélection, ni clé API."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let report = DiagnosticReport.make(
                metricsService: metrics,
                permissions: DiagnosticPermissions(
                    microphone: appState.hasMicrophonePermission,
                    accessibility: appState.hasAccessibilityPermission
                ),
                customModeCount: modes.customModes.count,
                applicationProfileCount: modes.applicationProfiles.count,
                betaUpdatesEnabled: updateService.includeBetaUpdates
            )
            try report.encoded().write(to: url, options: [.atomic])
            diagnosticsMessage = "Diagnostics exportés : \(url.lastPathComponent)"
        } catch {
            diagnosticsMessage = "Échec de l’export : \(error.localizedDescription)"
        }
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
    SettingsView()
        .environmentObject(AppState())
        .environmentObject(
            UpdateService(
                canCheckForUpdates: true,
                checkForUpdatesAction: {}
            )
        )
}
