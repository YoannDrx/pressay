import Combine
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var didPresentAtLaunch = false
    private var previousActivationPolicy: NSApplication.ActivationPolicy?

    private override init() {}

    func showAtLaunch(appState: AppState, updateService: UpdateService) {
        guard !didPresentAtLaunch else { return }
        didPresentAtLaunch = true
        show(appState: appState, updateService: updateService)
    }

    func show(appState: AppState, updateService: UpdateService) {
        if window == nil {
            let rootView = SettingsView()
                .environmentObject(appState)
                .environmentObject(updateService)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            #if APP_STORE
            window.title = "Pressay Companion"
            #else
            window.title = "Réglages Pressay"
            #endif
            window.contentView = NSHostingView(rootView: rootView)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setFrameAutosaveName("PressayCompanionMainWindow")
            window.center()
            self.window = window
        }
        if previousActivationPolicy == nil {
            previousActivationPolicy = NSApp.activationPolicy()
        }
        // LSUIElement windows can be ordered without becoming interactive.
        // Temporarily making Pressay a regular app gives the settings window a
        // proper key-window session; the original policy is restored on close.
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.orderFrontRegardless()
        DispatchQueue.main.async { [weak window] in
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            window?.orderFrontRegardless()
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let previousActivationPolicy else { return }
        self.previousActivationPolicy = nil
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(previousActivationPolicy)
        }
    }
}

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?

    private override init() {}

    @discardableResult
    func showIfNeeded(appState: AppState, updateService: UpdateService) -> Bool {
        guard !UserDefaults.standard.bool(
            forKey: Constants.onboardingCompletedKey
        ) else { return false }
        let rootView = OnboardingView { [weak self] in
            UserDefaults.standard.set(
                true,
                forKey: Constants.onboardingCompletedKey
            )
            self?.window?.close()
        }
        .environmentObject(appState)
        .environmentObject(updateService)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 590),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Bienvenue dans Pressay"
        window.contentView = NSHostingView(rootView: rootView)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

private struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var updateService: UpdateService

    let onComplete: () -> Void

    @State private var step = 0
    @State private var apiKey = ""
    @State private var validationMessage: String?
    @State private var isValidating = false
    @State private var guidedResult = ""

    private let lastStep = 4

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(0...lastStep, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Color.accentColor : .secondary.opacity(0.18))
                        .frame(height: 5)
                }
            }
            .padding(24)

            Group {
                switch step {
                case 0: promiseStep
                case 1: permissionsStep
                case 2: providerStep
                case 3: guidedDictationStep
                default: completionStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 54)
            .padding(.bottom, 28)

            Divider()
            HStack {
                if step > 0 {
                    Button("Retour") { step -= 1 }
                }
                Spacer()
                if step < lastStep {
                    Button(step == 0 ? "Commencer" : "Continuer") { step += 1 }
                        .buttonStyle(.borderedProminent)
                        .disabled(step == 2 && !appState.hasAPIKey)
                } else {
                    Button("Utiliser Pressay", action: onComplete)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .frame(width: 720, height: 590)
        .onReceive(appState.sessionCoordinator.objectWillChange) { _ in
            DispatchQueue.main.async {
                guidedResult = appState.sessionCoordinator.lastSession?.finalText
                    ?? appState.sessionCoordinator.lastSession?.rawText
                    ?? guidedResult
            }
        }
    }

    private var promiseStep: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 104, height: 104)
            Text("Écris partout, simplement en parlant")
                .font(.system(size: 28, weight: .bold))
            Text("Maintiens Fn, parle, puis relâche. Pressay transcrit avec OpenAI ou WhisperKit en local et protège toujours le champ de destination.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Label(
                DistributionChannel.current.deliveryDescription,
                systemImage: "checkmark.shield.fill"
            )
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            onboardingTitle(
                "Autorisations",
                detail: "Pressay ne demande une autorisation que lorsque tu déclenches l’action correspondante."
            )
            onboardingPermission(
                title: "Microphone",
                detail: "Utilisé seulement pendant une dictée.",
                granted: appState.hasMicrophonePermission,
                action: appState.requestMicrophonePermission
            )
            if DistributionChannel.current.supportsAccessibility {
                onboardingPermission(
                    title: "Accessibilité",
                    detail: "Permet de retrouver le champ initial et d’y insérer le résultat.",
                    granted: appState.hasAccessibilityPermission,
                    action: appState.requestAccessibilityPermission
                )
            } else {
                Label(
                    "L’édition App Store copie le résultat dans le presse-papiers.",
                    systemImage: "doc.on.clipboard"
                )
                .foregroundStyle(.secondary)
            }
        }
    }

    private var providerStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingTitle(
                "Choisis ton moteur de transcription",
                detail: "Commence avec OpenAI. Tu pourras télécharger WhisperKit pour dicter entièrement hors ligne depuis les réglages."
            )
            SecureField("sk-…", text: $apiKey)
                .textFieldStyle(.roundedBorder)
            HStack {
                Link(
                    "Créer une clé OpenAI",
                    destination: URL(string: "https://platform.openai.com/api-keys")!
                )
                Spacer()
                if isValidating { ProgressView().controlSize(.small) }
                Button("Vérifier et enregistrer") { validateProviderKey() }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating)
            }
            if let validationMessage {
                Text(validationMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(appState.hasAPIKey ? .green : .orange)
            }
        }
    }

    private var guidedDictationStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingTitle(
                "Fais ta première dictée",
                detail: "Maintiens Fn, dis « Bonjour Pressay », puis relâche. Comme ce champ appartient à Pressay, le résultat de démonstration est affiché ici."
            )
            TextEditor(text: $guidedResult)
                .font(.system(size: 16))
                .padding(8)
                .frame(height: 150)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            guidedResult.isEmpty
                                ? Color.secondary.opacity(0.25)
                                : Color.green,
                            lineWidth: 1
                        )
                )
            HStack {
                Label("Maintenir Fn", systemImage: "globe")
                Spacer()
                if appState.isRecording {
                    Label("Je t’écoute…", systemImage: "waveform")
                        .foregroundStyle(.red)
                } else if !guidedResult.isEmpty {
                    Label("Première dictée réussie", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .font(.system(size: 12, weight: .medium))
        }
    }

    private var completionStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
            Text("Pressay est prêt")
                .font(.system(size: 28, weight: .bold))
            Text("L’icône reste dans la barre des menus. Tu peux basculer entre OpenAI et WhisperKit, créer des modes et consulter l’historique depuis ce menu.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
            Text("Maintenir Fn → parler → relâcher")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
    }

    private func onboardingTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 24, weight: .bold))
            Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

    private func onboardingPermission(
        title: String,
        detail: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 24))
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted { Button("Autoriser", action: action) }
        }
        .padding(14)
        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private func validateProviderKey() {
        let value = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        isValidating = true
        validationMessage = nil
        Task {
            let valid = await appState.updateAPIKey(value)
            isValidating = false
            validationMessage = valid
                ? "Clé vérifiée et enregistrée."
                : "Cette clé n’a pas pu être validée."
            if valid { apiKey = "" }
        }
    }
}

@MainActor
final class StatusItemController: NSObject, ObservableObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let appState: AppState
    private let updateService: UpdateService
    private var observations = Set<AnyCancellable>()

    init(appState: AppState, updateService: UpdateService) {
        self.appState = appState
        self.updateService = updateService
        self.statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        super.init()

        statusItem.isVisible = true
        let rootView = MenuBarView()
            .environmentObject(appState)
            .environmentObject(updateService)
        let hostingController = NSHostingController(rootView: rootView)
        popover.contentViewController = hostingController
        popover.behavior = .transient
        popover.animates = true
        hostingController.view.layoutSubtreeIfNeeded()
        let fittingHeight = hostingController.view.fittingSize.height
        popover.contentSize = NSSize(
            width: 286,
            height: min(max(fittingHeight, 360), 720)
        )

        if let button = statusItem.button {
            button.isEnabled = true
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp])
        }
        updateStatusItem()

        appState.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                DispatchQueue.main.async {
                    self?.updateStatusItem()
                }
            }
            .store(in: &observations)

    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }

        // Keep the destination application frontmost. Activating Pressay here
        // makes a dictation started from the popover capture Pressay itself as
        // the target, so delivery can only fall back to the pasteboard.
        popover.show(
            relativeTo: sender.bounds,
            of: sender,
            preferredEdge: .minY
        )
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let assetName: String
        let accessibilityLabel: String
        if appState.isTranscribing {
            assetName = "PressayMenuProcessing"
            accessibilityLabel = "Pressay, transcription en cours"
        } else if appState.isRecording {
            assetName = "PressayMenuListening"
            accessibilityLabel = "Pressay, enregistrement en cours"
        } else {
            assetName = "PressayMenuRest"
            accessibilityLabel = "Pressay"
        }
        let image = NSImage(named: assetName)
            ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)
        image?.isTemplate = true
        image?.size = NSSize(width: 20, height: 20)
        button.image = image
        // A template image must inherit the menu-bar tint. Forcing labelColor
        // makes it stay black even when macOS expects a light status icon.
        button.contentTintColor = appState.isRecording ? .systemRed : nil
        button.setAccessibilityLabel(accessibilityLabel)
        button.toolTip = accessibilityLabel
    }
}

@MainActor
final class PressayApplicationDelegate: NSObject, NSApplicationDelegate {
    let appState: AppState
    let updateService: UpdateService

    private var statusItemController: StatusItemController?

    override init() {
        // Hosted macOS unit tests launch the complete app before XCTest is
        // attached. They must not migrate or unlock production credentials.
#if DEBUG
        // A locally built Pressay and /Applications/Pressay.app have distinct
        // bundle identifiers, so macOS otherwise lets both global Fn monitors
        // run at once. Keep the developer build authoritative while testing.
        if !Constants.isRunningTests {
            NSRunningApplication.runningApplications(
                withBundleIdentifier: "fr.yodev.pressay"
            ).forEach { $0.terminate() }
        }
#endif
#if !APP_STORE
        if !Constants.isRunningTests {
            AppMigrationService().runIfNeeded()
        }
#endif
        appState = AppState()
        updateService = UpdateService()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Constants.isRunningTests else { return }

        // NSStatusItem buttons are backed by SystemUIServer. Creating one
        // while SwiftUI is still constructing its App value can leave a
        // visible button whose physical mouse events never reach its menu.
        // Install it only once AppKit has completed application launch and
        // retain its controller for the entire process lifetime.
        statusItemController = StatusItemController(
            appState: appState,
            updateService: updateService
        )
        let presentedOnboarding = OnboardingWindowController.shared.showIfNeeded(
            appState: appState,
            updateService: updateService
        )
        #if APP_STORE
        if !presentedOnboarding {
            SettingsWindowController.shared.showAtLaunch(
                appState: appState,
                updateService: updateService
            )
        }
        #endif
    }
}

@main
struct PressayApp: App {
    @NSApplicationDelegateAdaptor(PressayApplicationDelegate.self)
    private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
                .environmentObject(appDelegate.updateService)
        }
    }
}
