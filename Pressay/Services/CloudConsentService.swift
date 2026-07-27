import AppKit
import SwiftUI

@MainActor
final class CloudConsentController: NSObject, ObservableObject, CloudConsentRequesting {
    static let shared = CloudConsentController()

    @Published private(set) var preflight: CloudPreflight?
    @Published private(set) var allowsRawTranscription = false

    private let defaults: UserDefaults
    private let modeStore: ModeStore
    private var panel: NSPanel?
    private var continuation: CheckedContinuation<CloudConsentDecision, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var persistsDisclosureOnSend = false

    init(
        defaults: UserDefaults = .standard,
        modeStore: ModeStore? = nil
    ) {
        self.defaults = defaults
        self.modeStore = modeStore ?? .shared
    }

    func requestConsent(
        for preflight: CloudPreflight,
        allowsRawTranscription: Bool,
        requiresExplicitChoice: Bool
    ) async -> CloudConsentDecision {
        if !requiresExplicitChoice, hasDisclosure(for: preflight) {
            return .sendOnce
        }
        if continuation != nil {
            return .cancel
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                self.preflight = preflight
                self.allowsRawTranscription = allowsRawTranscription
                self.persistsDisclosureOnSend = !requiresExplicitChoice

                let panel = self.panel ?? self.makePanel()
                self.panel = panel
                panel.center()
                NSApp.activate(ignoringOtherApps: true)
                panel.makeKeyAndOrderFront(nil)

                self.timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(60))
                    guard !Task.isCancelled else { return }
                    self?.resolve(.cancel)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.resolve(.cancel)
            }
        }
    }

    func resolve(_ decision: CloudConsentDecision) {
        guard let continuation else { return }
        if let preflight {
            if decision == .alwaysAllowMode {
                rememberDisclosure(for: preflight)
                modeStore.setProviderPolicyOverride(
                    modeID: preflight.modeID,
                    policy: .cloudAllowed
                )
            } else if decision == .sendOnce, persistsDisclosureOnSend {
                rememberDisclosure(for: preflight)
            }
        }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        panel?.orderOut(nil)
        preflight = nil
        allowsRawTranscription = false
        persistsDisclosureOnSend = false
        continuation.resume(returning: decision)
    }

    private func hasDisclosure(for preflight: CloudPreflight) -> Bool {
        disclosedSignatures.contains(preflight.consentSignature)
    }

    private func rememberDisclosure(for preflight: CloudPreflight) {
        var values = disclosedSignatures
        values.insert(preflight.consentSignature)
        defaults.set(
            Array(values).sorted(),
            forKey: Constants.cloudDisclosureSignaturesKey
        )
    }

    private var disclosedSignatures: Set<String> {
        Set(
            defaults.stringArray(
                forKey: Constants.cloudDisclosureSignaturesKey
            ) ?? []
        )
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Envoi cloud — Pressay"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.minSize = NSSize(width: 520, height: 450)
        panel.delegate = self
        panel.contentView = NSHostingView(
            rootView: CloudConsentView(controller: self)
        )
        return panel
    }
}

extension CloudConsentController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        resolve(.cancel)
        return false
    }
}

final class AllowingCloudConsentService: CloudConsentRequesting {
    func requestConsent(
        for preflight: CloudPreflight,
        allowsRawTranscription: Bool,
        requiresExplicitChoice: Bool
    ) async -> CloudConsentDecision {
        .sendOnce
    }
}

private struct CloudConsentView: View {
    @ObservedObject var controller: CloudConsentController

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            payload
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand { controller.resolve(.cancel) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Consentement avant envoi cloud")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "cloud")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 42, height: 42)
                .background(.orange.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("Vérifier ce qui quitte votre Mac")
                    .font(.headline)
                if let value = controller.preflight {
                    Text("\(value.providerID) · \(value.modelID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("La parole est l’instruction. Les autres sources sont uniquement du contexte non fiable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var payload: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                disclosureSection(
                    title: "PAROLE",
                    source: nil,
                    text: controller.preflight?.spokenText ?? ""
                )
                ForEach(controller.preflight?.sources ?? [], id: \.self) {
                    source in
                    disclosureSection(
                        title: source.rawValue.uppercased(),
                        source: source,
                        text: controller.preflight?
                            .exactPayloadPreview[source] ?? ""
                    )
                }
            }
            .padding(20)
        }
    }

    private func disclosureSection(
        title: String,
        source: ContextSource?,
        text: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if let source,
                   let count = controller.preflight?.characterCounts[source] {
                    Text("\(count) caractères")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(text.isEmpty ? "Aucun contenu" : text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel(
                    "\(title). \(text.isEmpty ? "Aucun contenu" : text)"
                )
        }
    }

    private var footer: some View {
        HStack {
            Button("Annuler") {
                controller.resolve(.cancel)
            }
            .keyboardShortcut(.cancelAction)
            if controller.allowsRawTranscription {
                Button("Utiliser le brut") {
                    controller.resolve(.useRawTranscription)
                }
            }
            Spacer()
            Button("Toujours autoriser ce mode") {
                controller.resolve(.alwaysAllowMode)
            }
            .accessibilityHint(
                "Mémorise ce fournisseur, ce modèle et ces sources pour ce mode"
            )
            Button("Envoyer") {
                controller.resolve(.sendOnce)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .accessibilityHint(
                "Envoie uniquement le contenu affiché à ce fournisseur"
            )
        }
        .padding(16)
    }
}
