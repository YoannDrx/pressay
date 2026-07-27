import XCTest
@testable import Pressay

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

    func testShortSoundSpikeIsRejected() {
        let silence = Array(repeating: Float(-62), count: 30)
        let stopSoundSpike = Array(repeating: Float(-12), count: 3)

        let result = SpeechDetectionPolicy.analyze(
            powers: silence + stopSoundSpike,
            duration: 2
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

    func testFrenchPromptEchoIsRejected() {
        let vocabulary = Constants.defaultTechnicalVocabulary
        let prompt = "Dictée naturelle avec une ponctuation fidèle. Le vocabulaire technique peut inclure : \(vocabulary)."

        XCTAssertThrowsError(
            try TranscriptionResponseValidator.validated(
                prompt,
                vocabulary: vocabulary,
                prompt: prompt
            )
        ) { error in
            XCTAssertEqual(
                error as? TranscriptionService.TranscriptionError,
                .noSpeech
            )
        }
    }

    func testEnglishPromptEchoIsRejected() {
        let vocabulary = "API, SDK, GitHub, TypeScript"
        let prompt = "Natural dictation with accurate punctuation. Technical vocabulary may include: \(vocabulary)."

        XCTAssertThrowsError(
            try TranscriptionResponseValidator.validated(
                prompt,
                vocabulary: vocabulary,
                prompt: prompt
            )
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

final class AppMigrationServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var yodevDefaults: UserDefaults!
    private var hyrakDefaults: UserDefaults!
    private var applicationSupportRoot: URL!

    override func setUp() {
        super.setUp()
        defaults = makeDefaults(suffix: "current")
        yodevDefaults = makeDefaults(suffix: "fr.yodev.whisper")
        hyrakDefaults = makeDefaults(suffix: "com.hyrak.whisper")
        applicationSupportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PressayMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: applicationSupportRoot,
            withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName(suffix: "current"))
        yodevDefaults.removePersistentDomain(
            forName: defaultsSuiteName(suffix: "fr.yodev.whisper")
        )
        hyrakDefaults.removePersistentDomain(
            forName: defaultsSuiteName(suffix: "com.hyrak.whisper")
        )
        try? FileManager.default.removeItem(at: applicationSupportRoot)
        defaults = nil
        yodevDefaults = nil
        hyrakDefaults = nil
        applicationSupportRoot = nil
        super.tearDown()
    }

    func testMigratesPreferencesAndKeychainUsingIdentityPriorityOnlyOnce() {
        yodevDefaults.set("en", forKey: Constants.transcriptionLanguageKey)
        yodevDefaults.set(false, forKey: Constants.historyEnabledKey)
        hyrakDefaults.set("fr", forKey: Constants.transcriptionLanguageKey)
        let yodevKeychain = MemoryKeychainStore(items: [
            Constants.keychainAPIKeyAccount: Data("sk-old".utf8),
            Constants.keychainHistoryKeyAccount: Data([0x01, 0x02])
        ])
        let hyrakKeychain = MemoryKeychainStore(items: [
            Constants.keychainAPIKeyAccount: Data("sk-older".utf8)
        ])
        let currentKeychain = MemoryKeychainStore()
        let service = makeService(
            currentKeychain: currentKeychain,
            yodevKeychain: yodevKeychain,
            hyrakKeychain: hyrakKeychain
        )

        XCTAssertTrue(service.runIfNeeded())
        XCTAssertEqual(defaults.string(forKey: Constants.transcriptionLanguageKey), "en")
        XCTAssertEqual(defaults.object(forKey: Constants.historyEnabledKey) as? Bool, false)
        XCTAssertEqual(
            currentKeychain.data(account: Constants.keychainAPIKeyAccount),
            Data("sk-old".utf8)
        )
        XCTAssertNil(yodevKeychain.data(account: Constants.keychainAPIKeyAccount))
        XCTAssertEqual(
            hyrakKeychain.data(account: Constants.keychainAPIKeyAccount),
            Data("sk-older".utf8)
        )
        XCTAssertTrue(defaults.bool(forKey: Constants.identityMigrationCompletedKey))

        defaults.set("fr", forKey: Constants.transcriptionLanguageKey)
        yodevDefaults.set("auto", forKey: Constants.transcriptionLanguageKey)

        XCTAssertTrue(service.runIfNeeded())
        XCTAssertEqual(defaults.string(forKey: Constants.transcriptionLanguageKey), "fr")
    }

    func testDoesNotOverwriteCurrentValues() {
        defaults.set("fr", forKey: Constants.transcriptionLanguageKey)
        yodevDefaults.set("en", forKey: Constants.transcriptionLanguageKey)
        let currentKeychain = MemoryKeychainStore(items: [
            Constants.keychainAPIKeyAccount: Data("sk-current".utf8)
        ])
        let yodevKeychain = MemoryKeychainStore(items: [
            Constants.keychainAPIKeyAccount: Data("sk-old".utf8)
        ])

        let service = makeService(
            currentKeychain: currentKeychain,
            yodevKeychain: yodevKeychain
        )

        XCTAssertTrue(service.runIfNeeded())
        XCTAssertEqual(defaults.string(forKey: Constants.transcriptionLanguageKey), "fr")
        XCTAssertEqual(
            currentKeychain.data(account: Constants.keychainAPIKeyAccount),
            Data("sk-current".utf8)
        )
    }

    func testCompletesWhenNoLegacyDataExists() {
        let service = makeService(currentKeychain: MemoryKeychainStore())

        XCTAssertTrue(service.runIfNeeded())
        XCTAssertTrue(defaults.bool(forKey: Constants.identityMigrationCompletedKey))
    }

    func testRetriesWhenKeychainWriteFails() {
        let yodevKeychain = MemoryKeychainStore(items: [
            Constants.keychainAPIKeyAccount: Data("sk-old".utf8)
        ])
        let service = makeService(
            currentKeychain: MemoryKeychainStore(acceptsWrites: false),
            yodevKeychain: yodevKeychain
        )

        XCTAssertFalse(service.runIfNeeded())
        XCTAssertFalse(defaults.bool(forKey: Constants.identityMigrationCompletedKey))
        XCTAssertNotNil(yodevKeychain.data(account: Constants.keychainAPIKeyAccount))
    }

    func testMovesLegacyApplicationSupportDirectoryAtomically() throws {
        let legacyDirectory = applicationSupportRoot.appendingPathComponent(
            Constants.legacyApplicationSupportDirectoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: legacyDirectory,
            withIntermediateDirectories: true
        )
        let history = Data("encrypted-history".utf8)
        try history.write(to: legacyDirectory.appendingPathComponent("history.enc"))

        XCTAssertTrue(makeService(currentKeychain: MemoryKeychainStore()).runIfNeeded())

        let currentDirectory = applicationSupportRoot.appendingPathComponent(
            Constants.applicationSupportDirectoryName,
            isDirectory: true
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyDirectory.path))
        XCTAssertEqual(
            try Data(contentsOf: currentDirectory.appendingPathComponent("history.enc")),
            history
        )
    }

    func testCurrentHistoryWinsWhenBothDirectoriesExist() throws {
        let legacyDirectory = applicationSupportRoot.appendingPathComponent(
            Constants.legacyApplicationSupportDirectoryName,
            isDirectory: true
        )
        let currentDirectory = applicationSupportRoot.appendingPathComponent(
            Constants.applicationSupportDirectoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: currentDirectory, withIntermediateDirectories: true)
        try Data("legacy".utf8).write(to: legacyDirectory.appendingPathComponent("history.enc"))
        try Data("current".utf8).write(to: currentDirectory.appendingPathComponent("history.enc"))

        XCTAssertTrue(makeService(currentKeychain: MemoryKeychainStore()).runIfNeeded())
        XCTAssertEqual(
            try Data(contentsOf: currentDirectory.appendingPathComponent("history.enc")),
            Data("current".utf8)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: legacyDirectory.appendingPathComponent("history.enc").path
            )
        )
    }

    private func makeService(
        currentKeychain: KeychainStoring,
        yodevKeychain: KeychainStoring = MemoryKeychainStore(),
        hyrakKeychain: KeychainStoring = MemoryKeychainStore()
    ) -> AppMigrationService {
        AppMigrationService(
            defaults: defaults,
            currentKeychain: currentKeychain,
            legacySources: [
                LegacyIdentitySource(
                    identifier: "fr.yodev.whisper",
                    defaults: yodevDefaults,
                    keychain: yodevKeychain
                ),
                LegacyIdentitySource(
                    identifier: "com.hyrak.whisper",
                    defaults: hyrakDefaults,
                    keychain: hyrakKeychain
                )
            ],
            applicationSupportRoot: applicationSupportRoot
        )
    }

    private func makeDefaults(suffix: String) -> UserDefaults {
        let suiteName = defaultsSuiteName(suffix: suffix)
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func defaultsSuiteName(suffix: String) -> String {
        "fr.yodev.pressay.tests.migration.\(suffix)"
    }
}

@MainActor
final class UpdateServiceTests: XCTestCase {
    func testManualUpdateCheckDelegatesToSparkle() {
        var didCheck = false
        let service = UpdateService(
            canCheckForUpdates: true,
            checkForUpdatesAction: {
                didCheck = true
            }
        )

        XCTAssertTrue(service.canCheckForUpdates)
        XCTAssertTrue(service.supportsGentleScheduledUpdateReminders)
        service.checkForUpdates()
        XCTAssertTrue(didCheck)
    }

    func testSparkleConfigurationDisablesSystemProfiling() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)

        XCTAssertEqual(
            info["SUFeedURL"] as? String,
            "https://www.yoann-andrieux.fr/download/pressay/appcast.xml"
        )
        XCTAssertEqual(
            info["SUPublicEDKey"] as? String,
            "UZhQqKvJ2hCq/tcAznz/tbwCMF0N5Jx01IjEltwQ/Y4="
        )
        XCTAssertEqual(info["SUEnableSystemProfiling"] as? Bool, false)
        XCTAssertEqual(info["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
        XCTAssertNil(info["SUEnableAutomaticChecks"])
    }
}

private final class MemoryKeychainStore: KeychainStoring {
    private var items: [String: Data]
    private let acceptsWrites: Bool

    init(items: [String: Data] = [:], acceptsWrites: Bool = true) {
        self.items = items
        self.acceptsWrites = acceptsWrites
    }

    func save(data: Data, account: String) -> Bool {
        guard acceptsWrites else { return false }
        items[account] = data
        return true
    }

    func data(account: String) -> Data? {
        items[account]
    }

    func delete(account: String) -> Bool {
        items.removeValue(forKey: account)
        return true
    }
}
