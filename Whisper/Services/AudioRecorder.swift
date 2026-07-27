import AVFoundation
import Foundation

final class AudioRecorder: NSObject, ObservableObject {
    struct RecordingResult {
        let url: URL
        let duration: TimeInterval
        let detection: SpeechDetectionResult

        var containsSpeech: Bool { detection.containsSpeech }
    }

    @Published private(set) var isRecording = false
    @Published private(set) var hasPermission = false

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var meteringTimer: Timer?
    private var powerSamples: [Float] = []

    override init() {
        super.init()
        refreshPermission()
    }

    func refreshPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            hasPermission = true
        case .notDetermined:
            hasPermission = false
        case .denied, .restricted:
            hasPermission = false
        @unknown default:
            hasPermission = false
        }
    }

    func requestPermission(completion: ((Bool) -> Void)? = nil) {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                self?.hasPermission = granted
                completion?(granted)
            }
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

        cleanupCurrentRecording()

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
            cleanupCurrentRecording()
            throw RecordingError.recordingFailed
        }

        powerSamples = []
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
        self.recordingURL = nil
        let detection = SpeechDetectionPolicy.analyze(powers: powerSamples, duration: duration)
        powerSamples = []

        return RecordingResult(
            url: recordingURL,
            duration: duration,
            detection: detection
        )
    }

    func cleanupCurrentRecording() {
        stopMetering()
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false

        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }

        powerSamples = []
    }

    func cleanup(url: URL) {
        try? FileManager.default.removeItem(at: url)
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

        powerSamples.append(recorder.averagePower(forChannel: 0))
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
