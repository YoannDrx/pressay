import SwiftUI

#if APP_STORE
@MainActor
final class AppStoreMainWindowController {
    static let shared = AppStoreMainWindowController()

    private var window: NSWindow?
    private var didPresentAtLaunch = false

    private init() {}

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
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Pressay Companion"
            window.contentView = NSHostingView(rootView: rootView)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("PressayCompanionMainWindow")
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif

@main
struct PressayApp: App {
    @StateObject private var appState: AppState
    @StateObject private var updateService: UpdateService

    init() {
        // Hosted macOS unit tests launch the complete app before XCTest is
        // attached. They must not migrate or unlock production credentials.
#if !APP_STORE
        if !Constants.isRunningTests {
            AppMigrationService().runIfNeeded()
        }
#endif
        let appState = AppState()
        let updateService = UpdateService()
        _appState = StateObject(wrappedValue: appState)
        _updateService = StateObject(wrappedValue: updateService)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(updateService)
        } label: {
            menuBarIcon
                .onAppear {
                    #if APP_STORE
                    DispatchQueue.main.async {
                        AppStoreMainWindowController.shared.showAtLaunch(
                            appState: appState,
                            updateService: updateService
                        )
                    }
                    #endif
                }
        }
        .menuBarExtraStyle(.window)

        #if !APP_STORE
        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(updateService)
        }
        #endif
    }

    @ViewBuilder
    private var menuBarIcon: some View {
        if appState.isTranscribing {
            Image("PressayMenuProcessing")
                .resizable()
                .renderingMode(.template)
                .frame(width: 20, height: 20)
                .accessibilityLabel("Pressay, transcription en cours")
        } else if appState.isRecording {
            Image("PressayMenuListening")
                .resizable()
                .renderingMode(.template)
                .frame(width: 20, height: 20)
                .foregroundStyle(.red)
                .accessibilityLabel("Pressay, enregistrement en cours")
        } else {
            Image("PressayMenuRest")
                .resizable()
                .renderingMode(.template)
                .frame(width: 20, height: 20)
                .accessibilityLabel("Pressay")
        }
    }
}
