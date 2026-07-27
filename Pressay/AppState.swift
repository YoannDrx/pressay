import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var pendingCount = 0
    @Published var lastError: String?
    @Published var lastNotice: String?
    @Published var hasAPIKey: Bool
    @Published var hasMicrophonePermission = false
    @Published var hasAccessibilityPermission = TextInjector.hasAccessibilityPermission()

    let audioRecorder = AudioRecorder()
    let keyboardService = KeyboardService()

    private struct PendingRecording {
        let recording: AudioRecorder.RecordingResult
        let target: TextInjectionTarget?
        let startedAt: Date
    }

    private var currentTarget: TextInjectionTarget?
    private var recordingStartedAt: Date?
    private var pendingRecordings: [PendingRecording] = []
    private var transcriptionTask: Task<Void, Never>?

    init() {
        hasAPIKey = KeychainHelper.shared.hasAPIKey
        hasMicrophonePermission = audioRecorder.hasPermission

        keyboardService.onShortcutPressed = { [weak self] in
            Task { @MainActor in
                self?.shortcutPressed()
            }
        }
        keyboardService.onShortcutReleased = { [weak self] in
            Task { @MainActor in
                self?.stopRecordingAndQueue()
            }
        }
        keyboardService.startMonitoring()
    }

    func refreshPermissions() {
        audioRecorder.refreshPermission()
        hasMicrophonePermission = audioRecorder.hasPermission
        hasAccessibilityPermission = TextInjector.hasAccessibilityPermission()
    }

    func requestMicrophonePermission() {
        audioRecorder.requestPermission { [weak self] granted in
            self?.hasMicrophonePermission = granted
        }
    }

    func requestAccessibilityPermission() {
        TextInjector.requestAccessibilityPermission()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.refreshPermissions()
        }
    }

    func cancelTranscription() {
        guard transcriptionTask != nil else { return }
        transcriptionTask?.cancel()
        lastNotice = "Transcription annulée"
        lastError = nil
        StatusHUDController.shared.show(.cancelled, autoHide: true)
    }

    func copyLastTranscription() {
        guard let text = HistoryService.shared.entries.first?.text else { return }
        TextInjector.shared.copyToPasteboard(text)
        lastNotice = "Dernière transcription copiée"
    }

    private func shortcutPressed() {
        let mode = ActivationMode(
            rawValue: UserDefaults.standard.string(forKey: Constants.activationModeKey) ?? ""
        ) ?? .hold
        if mode == .toggle, isRecording {
            stopRecordingAndQueue()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard hasAPIKey else {
            fail("Configure ta clé API dans les préférences")
            return
        }
        guard !isRecording else { return }
        guard audioRecorder.hasPermission else {
            fail("Autorise le microphone dans les préférences")
            return
        }

        do {
            try audioRecorder.startRecording()
            isRecording = true
            recordingStartedAt = Date()
            currentTarget = TextInjector.shared.captureTargetApp()
            lastError = nil
            lastNotice = nil
            SoundService.shared.playStartSound()
            StatusHUDController.shared.show(.listening)
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func stopRecordingAndQueue() {
        guard isRecording else { return }
        isRecording = false

        guard let recording = audioRecorder.stopRecording() else {
            fail("Aucun enregistrement trouvé")
            return
        }
        // Le son de fin ne doit jamais faire partie de l'enregistrement :
        // il pourrait être pris pour de la parole et provoquer une hallucination.
        SoundService.shared.playStopSound()

        let startedAt = recordingStartedAt ?? Date()
        PerformanceMetricsService.shared.record(.capture, duration: recording.duration)
        recordingStartedAt = nil

        guard recording.containsSpeech else {
            audioRecorder.cleanup(url: recording.url)
            currentTarget = nil
            lastError = nil
            lastNotice = "Aucune parole détectée — rien n’a été collé"
            StatusHUDController.shared.show(.cancelled, autoHide: true)
            return
        }

        pendingRecordings.append(
            PendingRecording(recording: recording, target: currentTarget, startedAt: startedAt)
        )
        currentTarget = nil
        pendingCount = pendingRecordings.count
        processNextRecording()
    }

    private func processNextRecording() {
        guard transcriptionTask == nil, !pendingRecordings.isEmpty else { return }
        let item = pendingRecordings.removeFirst()
        pendingCount = pendingRecordings.count
        isTranscribing = true
        StatusHUDController.shared.show(.transcribing)

        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.audioRecorder.cleanup(url: item.recording.url)
                self.transcriptionTask = nil
                self.isTranscribing = false
                self.processNextRecording()
            }

            do {
                let apiStartedAt = Date()
                let result = try await TranscriptionService.shared.transcribe(
                    audioURL: item.recording.url
                )
                PerformanceMetricsService.shared.record(
                    .transcription,
                    duration: Date().timeIntervalSince(apiStartedAt)
                )
                try Task.checkCancellation()

                HistoryService.shared.add(result.text)
                let insertionStartedAt = Date()
                let inserted = await TextInjector.shared.inject(text: result.text, target: item.target)
                PerformanceMetricsService.shared.record(
                    .insertion,
                    duration: Date().timeIntervalSince(insertionStartedAt)
                )
                PerformanceMetricsService.shared.record(
                    .total,
                    duration: Date().timeIntervalSince(item.startedAt)
                )

                lastError = nil
                if inserted {
                    lastNotice = result.isLowConfidence
                        ? "Texte inséré — vérifie cette transcription incertaine"
                        : "Transcription insérée"
                } else {
                    TextInjector.shared.copyToPasteboard(result.text)
                    lastNotice = "Transcription copiée — autorise l’accessibilité pour la coller automatiquement"
                }
                StatusHUDController.shared.show(.success, autoHide: true)
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                    lastError = nil
                    lastNotice = "Transcription annulée"
                } else {
                    lastError = error.localizedDescription
                    lastNotice = nil
                    SoundService.shared.playErrorSound()
                }
                StatusHUDController.shared.show(.cancelled, autoHide: true)
            }
        }
    }

    private func fail(_ message: String) {
        lastError = message
        lastNotice = nil
        SoundService.shared.playErrorSound()
        StatusHUDController.shared.show(.cancelled, autoHide: true)
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
