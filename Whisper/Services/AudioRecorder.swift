import AVFoundation
import Foundation

final class AudioRecorder: NSObject, ObservableObject {
    struct RecordingResult {
        let url: URL
        let duration: TimeInterval
        let voicedDuration: TimeInterval

        var containsSpeech: Bool {
            duration >= Constants.minimumRecordingDuration &&
            voicedDuration >= Constants.minimumVoicedDuration
        }
    }

    @Published private(set) var isRecording = false
    @Published private(set) var hasPermission = false

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var meteringTimer: Timer?
    private var voicedDuration: TimeInterval = 0

    override init() {
        super.init()
        checkPermission()
    }

    private func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            hasPermission = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.hasPermission = granted
                }
            }
        case .denied, .restricted:
            hasPermission = false
        @unknown default:
            hasPermission = false
        }
    }

    private func getRecordingURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent("whisper_recording_\(UUID().uuidString).m4a")
    }

    func startRecording() throws {
        guard hasPermission else {
            throw RecordingError.noPermission
        }

        cleanup()

        let url = getRecordingURL()
        recordingURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000, // 16kHz recommandé pour Whisper
            AVNumberOfChannelsKey: 1, // Mono
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.delegate = self
        audioRecorder?.isMeteringEnabled = true

        guard audioRecorder?.record() == true else {
            cleanup()
            throw RecordingError.recordingFailed
        }

        voicedDuration = 0
        startMetering()
        isRecording = true
    }

    func stopRecording() -> RecordingResult? {
        guard let recorder = audioRecorder, let recordingURL else {
            return nil
        }

        sampleAudioLevel()
        let duration = recorder.currentTime
        recorder.stop()
        stopMetering()
        isRecording = false
        audioRecorder = nil

        return RecordingResult(
            url: recordingURL,
            duration: duration,
            voicedDuration: voicedDuration
        )
    }

    func cleanup() {
        stopMetering()
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false

        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }

        voicedDuration = 0
    }

    private func startMetering() {
        let timer = Timer(timeInterval: Constants.audioMeteringInterval, repeats: true) { [weak self] _ in
            self?.sampleAudioLevel()
        }
        RunLoop.main.add(timer, forMode: .common)
        meteringTimer = timer
    }

    private func stopMetering() {
        meteringTimer?.invalidate()
        meteringTimer = nil
    }

    private func sampleAudioLevel() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }

        recorder.updateMeters()
        guard recorder.currentTime >= Constants.ignoredLeadingAudioDuration else { return }

        if recorder.averagePower(forChannel: 0) >= Constants.speechPowerThreshold {
            voicedDuration += Constants.audioMeteringInterval
        }
    }

    enum RecordingError: LocalizedError {
        case noPermission
        case recordingFailed

        var errorDescription: String? {
            switch self {
            case .noPermission:
                return "Accès au microphone refusé"
            case .recordingFailed:
                return "Échec de l'enregistrement"
            }
        }
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("Enregistrement terminé avec erreur")
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            print("Erreur d'encodage: \(error.localizedDescription)")
        }
    }
}
