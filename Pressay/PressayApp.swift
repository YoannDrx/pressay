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
