import Foundation

struct SpeechDetectionResult: Equatable {
    let containsSpeech: Bool
    let threshold: Float
    let voicedDuration: TimeInterval
}

enum SpeechDetectionPolicy {
    static func analyze(
        powers: [Float],
        duration: TimeInterval,
        interval: TimeInterval = Constants.audioMeteringInterval
    ) -> SpeechDetectionResult {
        guard duration >= Constants.minimumRecordingDuration, !powers.isEmpty else {
            return SpeechDetectionResult(
                containsSpeech: false,
                threshold: Constants.minimumAdaptiveThreshold,
                voicedDuration: 0
            )
        }

        let sorted = powers.sorted()
        let percentileIndex = min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.2))
        let noiseFloor = sorted[percentileIndex]
        let threshold = min(
            Constants.maximumAdaptiveThreshold,
            max(Constants.minimumAdaptiveThreshold, noiseFloor + Constants.noiseMargin)
        )
        let voicedDuration = Double(powers.filter { $0 >= threshold }.count) * interval

        return SpeechDetectionResult(
            containsSpeech: voicedDuration >= Constants.minimumVoicedDuration,
            threshold: threshold,
            voicedDuration: voicedDuration
        )
    }
}
