import AVFoundation
import Foundation

final class AudioRecorder: NSObject, ObservableObject {
    typealias RecordingResult = CapturedAudio

    @Published private(set) var isRecording = false
    @Published private(set) var hasPermission = false
    var onLevelUpdate: ((Float) -> Void)?

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var meterTimer: DispatchSourceTimer?
    private var powerSamples: [Float] = []

    override init() {
        super.init()
        refreshPermission()
    }

    func refreshPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            hasPermission = true
        case .notDetermined, .denied, .restricted:
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

    func startRecording() throws {
        guard hasPermission else { throw RecordingError.noPermission }
        cleanupCurrentRecording()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pressay_recording_\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()
        guard recorder.record() else { throw RecordingError.recordingFailed }

        self.recorder = recorder
        recordingURL = url
        powerSamples = []
        isRecording = true
        onLevelUpdate?(0)
        startMetering()
    }

    func stopRecording() -> CapturedAudio? {
        guard let recorder, let recordingURL else { return nil }
        samplePower()
        let duration = recorder.currentTime
        recorder.stop()
        stopMetering()

        self.recorder = nil
        self.recordingURL = nil
        isRecording = false
        onLevelUpdate?(0)

        let detection = SpeechDetectionPolicy.analyze(
            powers: powerSamples,
            duration: duration
        )
        powerSamples = []
        return CapturedAudio(
            url: recordingURL,
            duration: duration,
            detection: detection
        )
    }

    func cleanupCurrentRecording() {
        recorder?.stop()
        recorder = nil
        stopMetering()
        isRecording = false

        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
            self.recordingURL = nil
        }
        powerSamples = []
        onLevelUpdate?(0)
    }

    func cleanup(url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func startMetering() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now(),
            repeating: Constants.audioMeteringInterval
        )
        timer.setEventHandler { [weak self] in
            self?.samplePower()
        }
        meterTimer = timer
        timer.resume()
    }

    private func stopMetering() {
        meterTimer?.cancel()
        meterTimer = nil
    }

    private func samplePower() {
        guard let recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        if recorder.currentTime >= Constants.ignoredLeadingAudioDuration {
            powerSamples.append(power)
        }
        onLevelUpdate?(max(0, min(1, (power + 60) / 60)))
    }

    enum RecordingError: LocalizedError {
        case noPermission
        case recordingFailed

        var errorDescription: String? {
            switch self {
            case .noPermission:
                "Accès au microphone refusé"
            case .recordingFailed:
                "Échec de l’enregistrement"
            }
        }
    }
}

extension AudioRecorder: AudioCapturing {}
