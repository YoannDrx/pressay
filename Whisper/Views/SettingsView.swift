import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var apiKeyInput: String = ""
    @State private var isValidating: Bool = false
    @State private var showSuccessHint: Bool = false
    @State private var showErrorHint: Bool = false
    @AppStorage(Constants.transcriptionLanguageKey)
    private var transcriptionLanguage = Constants.defaultTranscriptionLanguage
    @AppStorage(Constants.technicalVocabularyKey)
    private var technicalVocabulary = Constants.defaultTechnicalVocabulary

    private let accentColor = Color(nsColor: .controlAccentColor)
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            headerSection
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    
                    // MARK: - API Configuration Section
                    SettingsSection(title: "CONFIGURATION API", icon: "key.fill") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                SecureField("sk-...", text: $apiKeyInput)
                                    .textFieldStyle(RefinedTextFieldStyle())
                                    .frame(maxWidth: .infinity)
                                
                                Button(action: validateKey) {
                                    HStack(spacing: 6) {
                                        if isValidating {
                                            ProgressView()
                                                .controlSize(.small)
                                                .scaleEffect(0.6)
                                        } else {
                                            Text("Valider")
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                    }
                                    .frame(width: 70, height: 24)
                                }
                                .buttonStyle(RefinedButtonStyle(isPrimary: true))
                                .disabled(apiKeyInput.isEmpty || isValidating)
                            }
                            
                            HStack(spacing: 12) {
                                statusIndicator
                                
                                Spacer()
                                
                                Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                                    HStack(spacing: 4) {
                                        Text("Obtenir une clé")
                                        Image(systemName: "arrow.up.right")
                                            .font(.system(size: 9))
                                    }
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(accentColor.opacity(0.9))
                                }
                                .buttonStyle(.plain)
                                .onHover { inside in
                                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                }
                            }

                            if showSuccessHint {
                                Label("Clé vérifiée et enregistrée dans le Trousseau.", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.green)
                            } else if showErrorHint {
                                Label("Impossible de valider cette clé. Vérifie sa valeur et ses droits API.", systemImage: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    // MARK: - Transcription Section
                    SettingsSection(title: "RECONNAISSANCE", icon: "waveform.badge.magnifyingglass") {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Langue principale")
                                        .font(.system(size: 12, weight: .medium))
                                    Text("Une langue explicite réduit la latence et les erreurs.")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Picker("", selection: $transcriptionLanguage) {
                                    Text("Français").tag("fr")
                                    Text("Anglais").tag("en")
                                    Text("Détection auto").tag("")
                                }
                                .labelsHidden()
                                .frame(width: 130)
                            }

                            Divider().opacity(0.5)

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Vocabulaire personnalisé")
                                        .font(.system(size: 12, weight: .medium))
                                    Spacer()
                                    Button("Valeurs par défaut") {
                                        technicalVocabulary = Constants.defaultTechnicalVocabulary
                                    }
                                    .font(.system(size: 10))
                                    .buttonStyle(.plain)
                                    .foregroundStyle(accentColor)
                                }

                                TextEditor(text: $technicalVocabulary)
                                    .font(.system(size: 11, design: .monospaced))
                                    .scrollContentBackground(.hidden)
                                    .padding(8)
                                    .frame(height: 72)
                                    .background(Color.primary.opacity(0.04))
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                    )

                                Text("Ajoute les noms propres et acronymes que tu dictes souvent. Laisse vide pour ne fournir aucun contexte.")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    // MARK: - Usage Section
                    SettingsSection(title: "UTILISATION", icon: "command") {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 16) {
                                ShortcutKeyView(label: "Fn", subLabel: "Maintenir")

                                Text("Maintenez la touche Fn enfoncée pour parler. Relâchez pour transcrire et coller le texte.")
                                    .font(.system(size: 12))
                                    .lineSpacing(3)
                                    .foregroundColor(.secondary)
                            }
                            
                            Divider().opacity(0.5)
                            
                            HStack(spacing: 12) {
                                Image(systemName: "text.cursor")
                                    .font(.system(size: 14))
                                    .foregroundColor(accentColor)
                                    .frame(width: 24)
                                
                                Text("Le texte transcrit sera inséré automatiquement à l'emplacement actuel de votre curseur.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // MARK: - About Section
                    SettingsSection(title: "À PROPOS", icon: "info.circle") {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Whisper for macOS")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Version \(appVersion)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("gpt-4o-mini-transcribe")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.primary.opacity(0.05))
                                .cornerRadius(4)
                        }
                    }
                }
                .padding(24)
            }
            
            // MARK: - Footer
            footerSection
        }
        .frame(width: 460, height: 700)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Subviews
    
    private var headerSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 44, height: 44)
                    .shadow(color: accentColor.opacity(0.22), radius: 8, x: 0, y: 4)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Whisper")
                        .font(.system(size: 16, weight: .bold))
                        .kerning(-0.2)
                    Text("Préférences Système")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            
            Divider().opacity(0.5)
        }
    }
    
    private var statusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appState.hasAPIKey ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
                .shadow(color: (appState.hasAPIKey ? Color.green : Color.orange).opacity(0.4), radius: 3)
            
            Text(appState.hasAPIKey ? "Clé API valide" : "Clé non configurée")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            if appState.hasAPIKey {
                Button(action: { appState.clearAPIKey() }) {
                    Text("Réinitialiser")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .underline()
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
        }
    }
    
    private var footerSection: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            HStack {
                Text("Whisper utilise l'API OpenAI pour une précision optimale.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
                
                Spacer()
                
                Button("Quitter") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(RefinedButtonStyle(isPrimary: false))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
    }
    
    // MARK: - Logic
    
    private func validateKey() {
        let cleanKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else { return }
        
        isValidating = true
        showErrorHint = false
        showSuccessHint = false
        
        Task {
            let success = await appState.updateAPIKey(cleanKey)
            await MainActor.run {
                isValidating = false
                if success {
                    apiKeyInput = ""
                    showSuccessHint = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { showSuccessHint = false }
                } else {
                    showErrorHint = true
                }
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

// MARK: - Supporting Views

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .kerning(0.5)
            }
            
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }
}

struct ShortcutKeyView: View {
    let label: String
    let subLabel: String
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 1, opacity: 0.1), Color(white: 1, opacity: 0.05)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 36, height: 36)
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    .frame(width: 36, height: 36)
                
                Text(label)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            
            Text(subLabel)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.secondary.opacity(0.8))
                .textCase(.uppercase)
        }
    }
}

// MARK: - Styles

struct RefinedTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.2))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .font(.system(size: 12, design: .monospaced))
    }
}

struct RefinedButtonStyle: ButtonStyle {
    let isPrimary: Bool
    @State private var isHovering = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    if isPrimary {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                    } else {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(isHovering ? 0.08 : 0.04))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isPrimary ? Color.white.opacity(0.1) : Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            .foregroundColor(isPrimary ? .white : .primary)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
            .onHover { inside in
                isHovering = inside
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
