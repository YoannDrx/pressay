import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ModesWindowController {
    static let shared = ModesWindowController()

    private var window: NSWindow?

    func show(shortcutRouter: ShortcutRouter) {
        let window = window ?? makeWindow(shortcutRouter: shortcutRouter)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(shortcutRouter: ShortcutRouter) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Modes Pressay"
        window.minSize = NSSize(width: 740, height: 520)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: ModesView(shortcutRouter: shortcutRouter)
        )
        window.center()
        return window
    }
}

private struct RunningApplicationDescriptor: Identifiable, Hashable {
    let bundleIdentifier: String
    let name: String
    var id: String { bundleIdentifier }
}

struct ModesView: View {
    @ObservedObject var shortcutRouter: ShortcutRouter
    @ObservedObject private var store = ModeStore.shared
    @State private var selectedModeID = NativeModeCatalog.faithfulID
    @State private var draft: ModeDefinition?
    @State private var runningApplications: [RunningApplicationDescriptor] = []
    @State private var examplesText = ""

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 740, minHeight: 520)
        .onAppear {
            select(selectedModeID)
            refreshApplications()
        }
        .onChange(of: selectedModeID) { _, newValue in
            select(newValue)
        }
        .alert(
            "Enregistrement des modes",
            isPresented: Binding(
                get: { store.storageError != nil },
                set: { presented in
                    if !presented { store.clearStorageError() }
                }
            )
        ) {
            Button("OK") { store.clearStorageError() }
        } message: {
            Text(store.storageError ?? "")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedModeID) {
                Section("Modes natifs") {
                    ForEach(NativeModeCatalog.visibleModes) { mode in
                        Label(mode.name, systemImage: mode.symbolName)
                            .tag(mode.id)
                    }
                }
                Section("Modes personnalisés") {
                    ForEach(store.customModes) { mode in
                        Label(mode.name, systemImage: mode.symbolName)
                            .tag(mode.id)
                    }
                }
            }
            Divider()
            HStack {
                Button {
                    createMode()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Créer un mode")
                Button {
                    deleteSelectedMode()
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(store.isBuiltIn(selectedModeID))
                .help("Supprimer le mode")
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
        .navigationSplitViewColumnWidth(min: 210, ideal: 240)
    }

    @ViewBuilder
    private var detail: some View {
        if let draft {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    modeEditor(draft)
                    Divider()
                    applicationRules
                }
                .padding(24)
            }
        } else {
            ContentUnavailableView(
                "Aucun mode sélectionné",
                systemImage: "wand.and.stars"
            )
        }
    }

    private func modeEditor(_ mode: ModeDefinition) -> some View {
        let isBuiltIn = store.isBuiltIn(mode.id)
        return VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: mode.symbolName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 42, height: 42)
                    .background(
                        Color.accentColor.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.name).font(.title2.weight(.semibold))
                    Text(isBuiltIn ? "Mode natif" : "Mode personnalisé")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if isBuiltIn {
                LabeledContent("Niveau", value: cleaningLabel(mode.cleaningLevel))
                LabeledContent("Format", value: outputLabel(mode.outputFormat))
                modeShortcutRow(mode)
                LabeledContent("Politique fournisseur") {
                    Picker(
                        "",
                        selection: builtInPolicyBinding(mode)
                    ) {
                        providerPolicyOptions
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
                providerRows(mode, isBuiltIn: true)
                Text(mode.prompt.isEmpty ? "Transcription fidèle, sans réécriture." : mode.prompt)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            } else {
                customEditor(mode)
            }
        }
    }

    private func customEditor(_ mode: ModeDefinition) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Nom") {
                TextField(
                    "Nom du mode",
                    text: draftBinding(\.name, fallback: mode.name)
                )
                .frame(width: 260)
            }
            LabeledContent("Symbole SF Symbols") {
                TextField(
                    "slider.horizontal.3",
                    text: draftBinding(\.symbolName, fallback: mode.symbolName)
                )
                .frame(width: 260)
            }
            LabeledContent("Langue") {
                Picker(
                    "",
                    selection: optionalLanguageBinding(mode)
                ) {
                    Text("Réglage général").tag("")
                    Text("Français").tag("fr")
                    Text("English").tag("en")
                }
                .labelsHidden()
                .frame(width: 210)
            }
            LabeledContent("Transformation") {
                Picker(
                    "",
                    selection: draftBinding(
                        \.cleaningLevel,
                        fallback: mode.cleaningLevel
                    )
                ) {
                    Text("Nettoyage léger").tag(CleaningLevel.light)
                    Text("Réécriture").tag(CleaningLevel.rewrite)
                    Text("Génération structurée").tag(CleaningLevel.generate)
                }
                .labelsHidden()
                .frame(width: 210)
            }
            LabeledContent("Format") {
                Picker(
                    "",
                    selection: draftBinding(\.outputFormat, fallback: mode.outputFormat)
                ) {
                    Text("Texte").tag(OutputFormat.plainText)
                    Text("Markdown").tag(OutputFormat.markdown)
                    Text("Code").tag(OutputFormat.code)
                    Text("Structuré").tag(OutputFormat.structured)
                }
                .labelsHidden()
                .frame(width: 210)
            }
            LabeledContent("Politique fournisseur") {
                Picker(
                    "",
                    selection: draftBinding(
                        \.providerPolicy,
                        fallback: mode.providerPolicy
                    )
                ) {
                    providerPolicyOptions
                }
                .labelsHidden()
                .frame(width: 210)
            }
            providerRows(mode, isBuiltIn: false)
            modeShortcutRow(mode)
            Text("Instructions du mode")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: draftBinding(\.prompt, fallback: mode.prompt))
                .font(.system(size: 12))
                .frame(minHeight: 110)
                .padding(8)
                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
            Text("Exemples (un par ligne)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: $examplesText)
                .font(.system(size: 11, design: .monospaced))
                .frame(minHeight: 70)
                .padding(8)
                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
            contextToggles(mode)
            HStack {
                Label(
                    "Traitement cloud limité aux sources autorisées ci-dessus",
                    systemImage: "cloud"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button("Enregistrer") {
                    if var draft {
                        draft.examples = examplesText
                            .split(whereSeparator: \.isNewline)
                            .map(String.init)
                            .filter { !$0.isEmpty }
                        store.updateCustomMode(draft)
                        self.draft = draft
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func modeShortcutRow(_ mode: ModeDefinition) -> some View {
        LabeledContent("Raccourci") {
            ShortcutRecorderField(
                router: shortcutRouter,
                action: .mode(mode.id)
            ) { definition in
                guard var updated = draft else { return }
                updated.shortcut = definition
                draft = updated
            }
        }
    }

    private func contextToggles(_ mode: ModeDefinition) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Contexte autorisé")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                contextToggle("Application", source: .application, mode: mode)
                contextToggle("Fenêtre", source: .windowTitle, mode: mode)
                contextToggle("Sélection", source: .selection, mode: mode)
                contextToggle("Autour du curseur", source: .surroundingText, mode: mode)
            }
        }
    }

    private func contextToggle(
        _ label: String,
        source: ContextSource,
        mode: ModeDefinition
    ) -> some View {
        Toggle(
            label,
            isOn: Binding(
                get: { draft?.allowedContextSources.contains(source) ?? false },
                set: { enabled in
                    guard var updated = draft else { return }
                    if enabled {
                        updated.allowedContextSources.insert(source)
                    } else {
                        updated.allowedContextSources.remove(source)
                    }
                    draft = updated
                }
            )
        )
        .toggleStyle(.checkbox)
        .font(.caption)
    }

    private var applicationRules: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Profils par application")
                        .font(.headline)
                    Text("La règle d’application prime sur le mode choisi manuellement.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Ajouter une app…", action: addApplicationManually)
            }

            if !availableSuggestions.isEmpty {
                Text("Suggestions installées")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(availableSuggestions) { suggestion in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.displayName)
                            Text(suggestion.bundleIdentifier)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(store.mode(withID: suggestion.modeID)?.name ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Activer") {
                            store.upsertApplicationProfile(
                                ApplicationProfile(
                                    bundleIdentifier: suggestion.bundleIdentifier,
                                    modeID: suggestion.modeID,
                                    source: .suggested,
                                    isEnabled: true
                                )
                            )
                        }
                    }
                }
                Divider()
            }

            ForEach(store.applicationProfiles) { profile in
                HStack {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { profile.isEnabled },
                            set: {
                                store.setApplicationProfileEnabled(
                                    id: profile.id,
                                    isEnabled: $0
                                )
                            }
                        )
                    )
                    .labelsHidden()
                    VStack(alignment: .leading, spacing: 1) {
                        Text(applicationName(for: profile.bundleIdentifier))
                            .font(.system(size: 12, weight: .medium))
                        Text(profile.bundleIdentifier)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker(
                        "",
                        selection: profileModeBinding(profile)
                    ) {
                        ForEach(store.visibleModes) { mode in
                            Text(mode.name).tag(mode.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 145)
                    Picker(
                        "",
                        selection: profileDeliveryPolicyBinding(profile)
                    ) {
                        Text("Automatique").tag(ApplicationDeliveryPolicy.automatic)
                        Text("Aperçu").tag(ApplicationDeliveryPolicy.preview)
                        Text("Copie seule").tag(ApplicationDeliveryPolicy.copyOnly)
                        Text("Exclue").tag(ApplicationDeliveryPolicy.excluded)
                    }
                    .labelsHidden()
                    .frame(width: 115)
                    .help("Politique de livraison pour cette application")
                    Button {
                        store.deleteApplicationProfile(id: profile.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Supprimer le profil")
                }
                Divider().opacity(0.4)
            }
            if store.applicationProfiles.isEmpty, availableSuggestions.isEmpty {
                Text("Aucun profil. Une application n’est jamais associée à un mode sans action explicite.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func select(_ id: UUID) {
        draft = store.mode(withID: id)
        examplesText = draft?.examples.joined(separator: "\n") ?? ""
    }

    private func createMode() {
        let mode = ModeDefinition(
            name: "Nouveau mode",
            symbolName: "slider.horizontal.3",
            cleaningLevel: .rewrite,
            prompt: "Décris précisément la transformation attendue.",
            providerPolicy: .askBeforeCloud,
            allowedContextSources: [.application]
        )
        store.addCustomMode(mode)
        selectedModeID = mode.id
        draft = mode
    }

    private func deleteSelectedMode() {
        guard !store.isBuiltIn(selectedModeID) else { return }
        store.deleteCustomMode(id: selectedModeID)
        selectedModeID = NativeModeCatalog.faithfulID
    }

    private func refreshApplications() {
        runningApplications = NSWorkspace.shared.runningApplications
            .filter {
                $0.activationPolicy == .regular
                    && $0.bundleIdentifier != Constants.bundleIdentifier
            }
            .compactMap { application in
                guard let bundleIdentifier = application.bundleIdentifier else {
                    return nil
                }
                return RunningApplicationDescriptor(
                    bundleIdentifier: bundleIdentifier,
                    name: application.localizedName ?? bundleIdentifier
                )
            }
            .uniqued(by: \.bundleIdentifier)
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private func profileModeBinding(_ profile: ApplicationProfile) -> Binding<UUID> {
        Binding(
            get: {
                store.applicationProfiles.first(where: { $0.id == profile.id })?
                    .modeID ?? profile.modeID
            },
            set: { newModeID in
                var updated = profile
                updated.modeID = newModeID
                store.upsertApplicationProfile(updated)
            }
        )
    }

    private func profileDeliveryPolicyBinding(
        _ profile: ApplicationProfile
    ) -> Binding<ApplicationDeliveryPolicy> {
        Binding(
            get: {
                store.applicationProfiles.first(where: { $0.id == profile.id })?
                    .deliveryPolicy ?? .automatic
            },
            set: { newPolicy in
                var updated = profile
                updated.deliveryPolicy = newPolicy == .automatic
                    ? nil
                    : newPolicy
                store.upsertApplicationProfile(updated)
            }
        )
    }

    private func builtInPolicyBinding(_ mode: ModeDefinition) -> Binding<ProviderPolicy> {
        Binding(
            get: { store.mode(withID: mode.id)?.providerPolicy ?? mode.providerPolicy },
            set: { store.setProviderPolicyOverride(modeID: mode.id, policy: $0) }
        )
    }

    @ViewBuilder
    private func providerRows(
        _ mode: ModeDefinition,
        isBuiltIn: Bool
    ) -> some View {
        LabeledContent("Transcription") {
            Picker(
                "",
                selection: transcriptionProviderBinding(
                    mode,
                    isBuiltIn: isBuiltIn
                )
            ) {
                Text("Automatique").tag("")
                Text("OpenAI · Cloud").tag("openai")
                if CapabilityMatrix.current.supportsSystemSpeechAnalyzer {
                    Text("Apple · Local").tag("speech-analyzer")
                }
            }
            .labelsHidden()
            .frame(width: 220)
        }
        if mode.cleaningLevel != .faithful
            || mode.intent == .transformSelection {
            LabeledContent("Transformation") {
                Picker(
                    "",
                    selection: processingProviderBinding(
                        mode,
                        isBuiltIn: isBuiltIn
                    )
                ) {
                    Text("Automatique").tag("")
                    Text("OpenAI · Cloud").tag("openai-responses")
                    if CapabilityMatrix.current.supportsFoundationModels {
                        Text("Apple Intelligence · Local")
                            .tag("foundation-models")
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }
        }
    }

    private func transcriptionProviderBinding(
        _ mode: ModeDefinition,
        isBuiltIn: Bool
    ) -> Binding<String> {
        Binding(
            get: {
                (isBuiltIn
                    ? store.mode(withID: mode.id)?.transcriptionProviderID
                    : draft?.transcriptionProviderID) ?? ""
            },
            set: { providerID in
                let value = providerID.isEmpty ? nil : providerID
                if isBuiltIn {
                    store.setTranscriptionProviderOverride(
                        modeID: mode.id,
                        providerID: value
                    )
                    draft = store.mode(withID: mode.id)
                } else if var updated = draft {
                    updated.transcriptionProviderID = value
                    draft = updated
                }
            }
        )
    }

    private func processingProviderBinding(
        _ mode: ModeDefinition,
        isBuiltIn: Bool
    ) -> Binding<String> {
        Binding(
            get: {
                (isBuiltIn
                    ? store.mode(withID: mode.id)?.processingProviderID
                    : draft?.processingProviderID) ?? ""
            },
            set: { providerID in
                let value = providerID.isEmpty ? nil : providerID
                if isBuiltIn {
                    store.setProcessingProviderOverride(
                        modeID: mode.id,
                        providerID: value
                    )
                    draft = store.mode(withID: mode.id)
                } else if var updated = draft {
                    updated.processingProviderID = value
                    draft = updated
                }
            }
        )
    }

    private func optionalLanguageBinding(_ mode: ModeDefinition) -> Binding<String> {
        Binding(
            get: { draft?.transcriptionLanguage ?? "" },
            set: {
                guard var updated = draft else { return }
                updated.transcriptionLanguage = $0.isEmpty ? nil : $0
                draft = updated
            }
        )
    }

    @ViewBuilder
    private var providerPolicyOptions: some View {
        Text("Local uniquement").tag(ProviderPolicy.localOnly)
        Text("Préférer le local").tag(ProviderPolicy.preferLocal)
        Text("Demander avant le cloud").tag(ProviderPolicy.askBeforeCloud)
        Text("Cloud autorisé").tag(ProviderPolicy.cloudAllowed)
    }

    private var availableSuggestions: [ApplicationProfileSuggestion] {
        let existing = Set(store.applicationProfiles.map(\.bundleIdentifier))
        return store.installedProfileSuggestions().filter {
            !existing.contains($0.bundleIdentifier)
        }
    }

    private func applicationName(for bundleIdentifier: String) -> String {
        runningApplications.first {
            $0.bundleIdentifier == bundleIdentifier
        }?.name
            ?? ApplicationProfileSuggestion.catalog.first {
                $0.bundleIdentifier == bundleIdentifier
            }?.displayName
            ?? bundleIdentifier
    }

    private func addApplicationManually() {
        let panel = NSOpenPanel()
        panel.title = "Choisir une application"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundle = Bundle(url: url),
              let bundleIdentifier = bundle.bundleIdentifier else {
            return
        }
        store.upsertApplicationProfile(
            ApplicationProfile(
                bundleIdentifier: bundleIdentifier,
                modeID: selectedModeID,
                source: .manual,
                isEnabled: true
            )
        )
        refreshApplications()
    }

    private func draftBinding<Value>(
        _ keyPath: WritableKeyPath<ModeDefinition, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: { draft?[keyPath: keyPath] ?? fallback },
            set: { value in
                guard var updated = draft else { return }
                updated[keyPath: keyPath] = value
                draft = updated
            }
        )
    }

    private func cleaningLabel(_ level: CleaningLevel) -> String {
        switch level {
        case .faithful: return "Fidèle"
        case .light: return "Nettoyage léger"
        case .rewrite: return "Réécriture"
        case .generate: return "Génération structurée"
        }
    }

    private func outputLabel(_ format: OutputFormat) -> String {
        switch format {
        case .plainText: return "Texte"
        case .markdown: return "Markdown"
        case .code: return "Code"
        case .structured: return "Structuré"
        }
    }
}

private extension Sequence {
    func uniqued<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Element] {
        var seen: Set<Key> = []
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
