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

    override convenience init() {
        self.init(defaults: .standard)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        self.includeBetaUpdates = defaults.bool(
            forKey: Constants.includeBetaUpdatesKey
        )
        super.init()
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
        checkForUpdatesAction?()
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
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func standardUserDriverWillFinishUpdateSession() {
        NSApp.setActivationPolicy(.accessory)
    }
}
