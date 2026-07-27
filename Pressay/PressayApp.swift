import SwiftUI

@main
struct PressayApp: App {
    @StateObject private var appState: AppState
    @StateObject private var updateService: UpdateService

    init() {
        AppMigrationService().runIfNeeded()
        _appState = StateObject(wrappedValue: AppState())
        _updateService = StateObject(wrappedValue: UpdateService())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(updateService)
        } label: {
            menuBarIcon
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(updateService)
        }
    }

    @ViewBuilder
    private var menuBarIcon: some View {
        if appState.isTranscribing {
            Image(systemName: "ellipsis.circle")
                .symbolEffect(.pulse)
        } else if appState.isRecording {
            Image(systemName: "waveform.circle.fill")
                .symbolEffect(.variableColor.iterative)
                .foregroundStyle(.red)
        } else {
            Image("PressayMenuIcon")
                .renderingMode(.template)
        }
    }
}
