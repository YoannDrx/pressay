import AppKit

final class SoundService: SoundFeedback {
    static let shared = SoundService()
    private init() {}

    func playStartSound() {
        NSSound(named: "Morse")?.play()
    }

    func playStopSound() {
        NSSound(named: "Pop")?.play()
    }

    func playErrorSound() {
        NSSound(named: "Basso")?.play()
    }
}
