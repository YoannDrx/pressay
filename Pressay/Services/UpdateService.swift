#if APP_STORE
import Combine
import Foundation

@MainActor
final class UpdateService: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published var includeBetaUpdates = false

    init() {}
    init(defaults: UserDefaults) {}

    init(
        canCheckForUpdates: Bool,
        checkForUpdatesAction: @escaping () -> Void
    ) {
        self.canCheckForUpdates = false
    }

    func checkForUpdates() {}
}
#else
import AppKit
import Combine
import Sparkle

@MainActor
final class UpdateService: NSObject,
    ObservableObject,
    @preconcurrency SPUStandardUserDriverDelegate,
    SPUUpdaterDelegate {
    @Published private(set) var canCheckForUpdates = false
    @Published var includeBetaUpdates: Bool {
        didSet {
            defaults.set(
                includeBetaUpdates,
                forKey: Constants.includeBetaUpdatesKey
            )
        }
    }

    private var controller: SPUStandardUpdaterController?
    private var checkForUpdatesAction: (() -> Void)?
    private let defaults: UserDefaults
    private var defaultsObserver: NSObjectProtocol?
    private var activationDepth = 0
    private var previousActivationPolicy: NSApplication.ActivationPolicy?

    private static let hasLaunchedBeforeKey = "SUHasLaunchedBefore"
    private static let automaticChecksKey = "SUEnableAutomaticChecks"

    override convenience init() {
        self.init(defaults: .standard)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        self.includeBetaUpdates = defaults.bool(
            forKey: Constants.includeBetaUpdatesKey
        )
        super.init()
        if Self.needsAutomaticCheckPermissionPrompt(defaults: defaults) {
            beginInteractiveWindowSession()
            observeAutomaticCheckPermissionResponse()
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        self.controller = controller
        checkForUpdatesAction = {
            controller.checkForUpdates(nil)
        }
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    init(
        canCheckForUpdates: Bool,
        checkForUpdatesAction: @escaping () -> Void
    ) {
        self.defaults = .standard
        self.includeBetaUpdates = false
        self.canCheckForUpdates = canCheckForUpdates
        self.checkForUpdatesAction = checkForUpdatesAction
        super.init()
    }

    func checkForUpdates() {
        beginInteractiveWindowSession()
        checkForUpdatesAction?()
    }

    static func needsAutomaticCheckPermissionPrompt(defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: hasLaunchedBeforeKey)
            && defaults.object(forKey: automaticChecksKey) == nil
    }

    func standardUserDriverWillShowModalAlert() {
        beginInteractiveWindowSession()
    }

    func standardUserDriverDidShowModalAlert() {
        endInteractiveWindowSession()
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        includeBetaUpdates ? ["beta"] : []
    }

    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        true
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard handleShowingUpdate else { return }
        beginInteractiveWindowSession()
    }

    func standardUserDriverWillFinishUpdateSession() {
        endAllInteractiveWindowSessions()
    }

    private func observeAutomaticCheckPermissionResponse() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      self.defaults.object(forKey: Self.automaticChecksKey) != nil else {
                    return
                }
                if let observer = self.defaultsObserver {
                    NotificationCenter.default.removeObserver(observer)
                    self.defaultsObserver = nil
                }
                self.endAllInteractiveWindowSessions()
            }
        }
    }

    private func beginInteractiveWindowSession() {
        if activationDepth == 0 {
            previousActivationPolicy = NSApp.activationPolicy()
            NSApp.setActivationPolicy(.regular)
        }
        activationDepth += 1
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows
                .filter(\.isVisible)
                .forEach { $0.orderFrontRegardless() }
        }
    }

    private func endInteractiveWindowSession() {
        guard activationDepth > 0 else { return }
        activationDepth -= 1
        guard activationDepth == 0 else { return }
        restoreActivationPolicy()
    }

    private func endAllInteractiveWindowSessions() {
        activationDepth = 0
        restoreActivationPolicy()
    }

    private func restoreActivationPolicy() {
        let policy = previousActivationPolicy ?? .accessory
        previousActivationPolicy = nil
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(policy)
        }
    }
}
#endif
