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
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 16, weight: .regular))
                .symbolEffect(.pulse)
                .accessibilityLabel("Pressay, transcription en cours")
        } else if appState.isRecording {
            Image(systemName: "waveform.circle.fill")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 16, weight: .regular))
                .symbolEffect(.variableColor.iterative)
                .foregroundStyle(.red)
                .accessibilityLabel("Pressay, enregistrement en cours")
        } else {
            Image(systemName: "waveform.circle")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 16, weight: .regular))
                .accessibilityLabel("Pressay")
        }
    }
}
