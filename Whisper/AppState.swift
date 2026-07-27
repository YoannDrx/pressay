import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var lastError: String?
    @Published var lastNotice: String?
    @Published var hasAPIKey: Bool

    let audioRecorder = AudioRecorder()
    let keyboardService = KeyboardService()

    init() {
        hasAPIKey = KeychainHelper.shared.hasAPIKey

        // Push-to-talk: Fn pressé = enregistre, Fn relâché = transcrit
        keyboardService.onFnPressed = { [weak self] in
            Task { @MainActor in
                self?.startRecording()
            }
        }

        keyboardService.onFnReleased = { [weak self] in
            Task { @MainActor in
                self?.stopRecordingAndTranscribe()
            }
        }

        // Démarrer le monitoring du clavier
        keyboardService.startMonitoring()

        // Vérifier les permissions d'accessibilité
        if !TextInjector.hasAccessibilityPermission() {
            TextInjector.requestAccessibilityPermission()
        }
    }

    private func startRecording() {
        guard hasAPIKey else {
            lastError = "Configure ta clé API dans les préférences"
            lastNotice = nil
            SoundService.shared.playErrorSound()
            return
        }

        guard !isTranscribing else { return }
        guard !isRecording else { return }

        // Démarrer l'enregistrement EN PREMIER pour capturer les premiers mots
        do {
            try audioRecorder.startRecording()
            isRecording = true
            lastError = nil
            lastNotice = nil
            SoundService.shared.playStartSound()
        } catch {
            lastError = error.localizedDescription
            SoundService.shared.playErrorSound()
            return
        }

        // Capturer l'app qui a le focus APRÈS (en parallèle de l'enregistrement)
        TextInjector.shared.captureTargetApp()
    }

    private func stopRecordingAndTranscribe() {
        guard isRecording else { return }

        guard let recording = audioRecorder.stopRecording() else {
            lastError = "Aucun enregistrement trouvé"
            isRecording = false
            SoundService.shared.playErrorSound()
            return
        }

        isRecording = false
        SoundService.shared.playStopSound()

        guard recording.containsSpeech else {
            lastError = nil
            lastNotice = "Aucune parole détectée — rien n’a été collé"
            TextInjector.shared.clearTargetApp()
            audioRecorder.cleanup()
            return
        }

        isTranscribing = true

        Task {
            defer {
                audioRecorder.cleanup()
            }

            do {
                let text = try await TranscriptionService.shared.transcribe(audioURL: recording.url)

                HistoryService.shared.add(text)
                TextInjector.shared.inject(text: text)
                lastError = nil
                lastNotice = "Transcription insérée"
                isTranscribing = false
            } catch {
                lastError = error.localizedDescription
                lastNotice = nil
                isTranscribing = false
                TextInjector.shared.clearTargetApp()
                SoundService.shared.playErrorSound()
            }
        }
    }

    func updateAPIKey(_ key: String) async -> Bool {
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let isValid = await TranscriptionService.shared.validateAPIKey(cleanKey)

        if isValid, KeychainHelper.shared.save(apiKey: cleanKey) {
            hasAPIKey = true
            lastError = nil
            return true
        }

        return false
    }

    func clearAPIKey() {
        KeychainHelper.shared.delete()
        hasAPIKey = false
        lastNotice = nil
    }
}
