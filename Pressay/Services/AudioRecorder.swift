import AVFoundation
import Foundation

final class AudioRecorder: NSObject, ObservableObject {
    typealias RecordingResult = CapturedAudio

    @Published private(set) var isRecording = false
    @Published private(set) var hasPermission = false
    var onLevelUpdate: ((Float) -> Void)?
    var onPCMChunk: ((Data) -> Void)?

    private var audioEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var powerSamples: [Float] = []
    private var recordedFrames: AVAudioFramePosition = 0
    private let processingQueue = DispatchQueue(
        label: "fr.yodev.pressay.audio-processing",
        qos: .userInteractive
    )

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
        return tempDir.appendingPathComponent("pressay_recording_\(UUID().uuidString).wav")
    }

    func startRecording() throws {
        guard hasPermission else {
            throw RecordingError.noPermission
        }

        cleanupCurrentRecording()

        let url = getRecordingURL()
        recordingURL = url

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24_000,
            channels: 1,
            interleaved: true
        ) else { throw RecordingError.recordingFailed }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0,
              inputFormat.channelCount > 0,
              let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecordingError.recordingFailed
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: targetFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )

        audioEngine = engine
        audioConverter = converter
        audioFile = file
        recordedFrames = 0
        // A moderate buffer keeps level updates responsive while avoiding
        // excessive work on the realtime audio thread.
        input.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) {
            [weak self] buffer, _ in
            self?.processingQueue.async {
                self?.process(buffer, targetFormat: targetFormat)
            }
        }
        engine.prepare()
        try engine.start()

        powerSamples = []
        onLevelUpdate?(0)
        isRecording = true
    }

    func stopRecording() -> CapturedAudio? {
        guard let engine = audioEngine, let recordingURL else {
            return nil
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        processingQueue.sync {}
        let duration = Double(recordedFrames) / 24_000
        isRecording = false
        audioEngine = nil
        audioConverter = nil
        audioFile = nil
        self.recordingURL = nil
        let detection = SpeechDetectionPolicy.analyze(powers: powerSamples, duration: duration)
        powerSamples = []
        onLevelUpdate?(0)

        return CapturedAudio(
            url: recordingURL,
            duration: duration,
            detection: detection
        )
    }

    func cleanupCurrentRecording() {
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        processingQueue.sync {}
        audioEngine = nil
        audioConverter = nil
        audioFile = nil
        isRecording = false

        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }

        powerSamples = []
        onLevelUpdate?(0)
    }

    func cleanup(url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func process(_ inputBuffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        guard let converter = audioConverter,
              let audioFile,
              let output = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: AVAudioFrameCount(
                    ceil(Double(inputBuffer.frameLength) * 24_000 / inputBuffer.format.sampleRate)
                ) + 32
              ) else { return }
        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) {
            _, statusPointer in
            if supplied {
                statusPointer.pointee = .noDataNow
                return nil
            }
            supplied = true
            statusPointer.pointee = .haveData
            return inputBuffer
        }
        guard conversionError == nil,
              status != .error,
              output.frameLength > 0 else { return }
        do {
            try audioFile.write(from: output)
        } catch {
            return
        }
        recordedFrames += AVAudioFramePosition(output.frameLength)
        let power = averagePower(from: output)
        if Double(recordedFrames) / 24_000 >= Constants.ignoredLeadingAudioDuration {
            powerSamples.append(power)
        }
        if let samples = output.int16ChannelData?.pointee {
            onPCMChunk?(
                Data(
                    bytes: samples,
                    count: Int(output.frameLength) * MemoryLayout<Int16>.size
                )
            )
        }
        let normalized = max(0, min(1, (power + 60) / 60))
        onLevelUpdate?(normalized)
    }

    private func averagePower(from buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.int16ChannelData?.pointee else { return -80 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return -80 }
        var sum: Double = 0
        for index in 0..<count {
            let normalized = Double(samples[index]) / Double(Int16.max)
            sum += normalized * normalized
        }
        let rms = sqrt(sum / Double(count))
        return rms > 0 ? Float(20 * log10(rms)) : -80
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

extension AudioRecorder: AudioCapturing {}
extension AudioRecorder: PCMChunkProviding {}
