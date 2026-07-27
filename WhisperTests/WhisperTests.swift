import XCTest
@testable import Whisper

final class SpeechDetectionPolicyTests: XCTestCase {
    func testSilenceIsRejected() {
        let result = SpeechDetectionPolicy.analyze(
            powers: Array(repeating: -62, count: 20),
            duration: 1
        )
        XCTAssertFalse(result.containsSpeech)
    }

    func testVoiceAboveAdaptiveNoiseFloorIsAccepted() {
        let noise = Array(repeating: Float(-58), count: 8)
        let voice = Array(repeating: Float(-24), count: 6)
        let result = SpeechDetectionPolicy.analyze(powers: noise + voice, duration: 0.8)
        XCTAssertTrue(result.containsSpeech)
        XCTAssertGreaterThanOrEqual(result.voicedDuration, Constants.minimumVoicedDuration)
    }

    func testTooShortRecordingIsRejected() {
        let result = SpeechDetectionPolicy.analyze(
            powers: Array(repeating: -20, count: 8),
            duration: 0.2
        )
        XCTAssertFalse(result.containsSpeech)
    }
}

final class TranscriptionResponseValidatorTests: XCTestCase {
    func testEmptyResponseIsRejected() {
        XCTAssertThrowsError(try TranscriptionResponseValidator.validated("  ", vocabulary: "API"))
    }

    func testVocabularyEchoIsRejectedDespitePunctuationAndCase() {
        XCTAssertThrowsError(
            try TranscriptionResponseValidator.validated(
                "api, SDK, GitHub!",
                vocabulary: "API SDK GitHub"
            )
        )
    }

    func testNaturalTranscriptionIsAccepted() throws {
        XCTAssertEqual(
            try TranscriptionResponseValidator.validated(" Bonjour le monde. ", vocabulary: "API"),
            "Bonjour le monde."
        )
    }
}

final class MultipartFormDataTests: XCTestCase {
    func testBodyContainsFieldsFileAndClosingBoundary() throws {
        var form = MultipartFormData(boundary: "test-boundary")
        form.appendField(name: "model", value: "gpt-test")
        form.appendFile(
            name: "file",
            filename: "audio.wav",
            mimeType: "audio/wav",
            data: Data([0x01, 0x02])
        )
        let url = try form.writeToTemporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try Data(contentsOf: url)
        let body = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"model\""))
        XCTAssertTrue(body.contains("filename=\"audio.wav\""))
        XCTAssertTrue(body.hasSuffix("--test-boundary--\r\n"))
    }
}

final class HistoryRetentionPolicyTests: XCTestCase {
    func testEntriesOlderThanConfiguredRetentionAreRemoved() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let recent = TranscriptionEntry(text: "récent", date: now.addingTimeInterval(-60))
        let old = TranscriptionEntry(text: "ancien", date: now.addingTimeInterval(-25 * 60 * 60))

        XCTAssertEqual(
            HistoryRetentionPolicy.retained([recent, old], now: now, days: 1),
            [recent]
        )
    }
}
