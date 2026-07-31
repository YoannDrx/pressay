import Foundation
import CryptoKit

struct TranscriptionEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let date: Date

    init(id: UUID = UUID(), text: String, date: Date = Date()) {
        self.id = id
        self.text = text
        self.date = date
    }
}

enum HistoryRetentionPolicy {
    static func retained(
        _ entries: [TranscriptionEntry],
        now: Date = Date(),
        days: Int
    ) -> [TranscriptionEntry] {
        let maxAge = TimeInterval(max(1, days)) * 24 * 60 * 60
        return entries.filter { now.timeIntervalSince($0.date) <= maxAge }
    }
}

final class HistoryService: ObservableObject, HistoryRepository {
    static let shared = HistoryService()

    @Published private(set) var entries: [TranscriptionEntry] = []

    private let fileURL: URL
    private let legacyFileURL: URL
    private let keychain: KeychainHelper
    private let defaults: UserDefaults

    init(
        fileURL: URL? = nil,
        keychain: KeychainHelper = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.keychain = keychain
        self.defaults = defaults
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent(
            Constants.applicationSupportDirectoryName,
            isDirectory: true
        )

        // Créer le dossier si nécessaire
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)

        self.fileURL = fileURL ?? appFolder.appendingPathComponent("history.enc")
        self.legacyFileURL = appFolder.appendingPathComponent("history.json")
        // A hosted test process must never unlock the user's production
        // history key before XCTest has even attached to the application.
        if !Constants.isRunningTests {
            load()
            cleanup()
        }
    }

    func add(_ text: String) {
        guard isEnabled else { return }
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }

        let entry = TranscriptionEntry(text: cleanText)
        entries.insert(entry, at: 0)
        cleanup(saveAfterCleanup: false)
        save()
    }

    func append(_ record: HistoryRecord) {
        add(record.finalText)
    }

    func delete(_ entry: TranscriptionEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clearAll() {
        entries.removeAll()
        save()
    }

    func applyPreferences() {
        if !isEnabled {
            clearAll()
        } else {
            cleanup()
        }
    }

    private func cleanup(saveAfterCleanup: Bool = true) {
        let now = Date()
        entries = HistoryRetentionPolicy.retained(entries, now: now, days: retentionDays)
        if saveAfterCleanup {
            save()
        }
    }

    private func load() {
        guard isEnabled else { return }
        let sourceURL = FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : legacyFileURL
        guard let storedData = try? Data(contentsOf: sourceURL) else { return }

        if let decrypted = try? decrypt(storedData),
           let decoded = try? JSONDecoder().decode([TranscriptionEntry].self, from: decrypted) {
            entries = decoded
            return
        }

        // Migration transparente depuis l'ancien fichier JSON non chiffré.
        if let decoded = try? JSONDecoder().decode([TranscriptionEntry].self, from: storedData) {
            entries = decoded
            save()
            if sourceURL == legacyFileURL {
                try? FileManager.default.removeItem(at: legacyFileURL)
            }
        }
    }

    private func save() {
        guard isEnabled else {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: legacyFileURL)
            return
        }
        guard let data = try? JSONEncoder().encode(entries),
              let encrypted = try? encrypt(data) else { return }
        try? encrypted.write(to: fileURL, options: .atomic)
    }

    private var isEnabled: Bool {
        defaults.object(forKey: Constants.historyEnabledKey) as? Bool ?? true
    }

    private var retentionDays: Int {
        defaults.object(forKey: Constants.historyRetentionDaysKey) as? Int ?? 1
    }

    private func encryptionKey() throws -> SymmetricKey {
        if let data = keychain.data(account: Constants.keychainHistoryKeyAccount) {
            return SymmetricKey(data: data)
        }

        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        guard keychain.save(data: data, account: Constants.keychainHistoryKeyAccount) else {
            throw HistoryError.keychainFailure
        }
        return key
    }

    private func encrypt(_ data: Data) throws -> Data {
        let box = try AES.GCM.seal(data, using: encryptionKey())
        guard let combined = box.combined else { throw HistoryError.encryptionFailure }
        return combined
    }

    private func decrypt(_ data: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: encryptionKey())
    }

    enum HistoryError: Error {
        case keychainFailure
        case encryptionFailure
    }
}

struct VoiceInboxEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let sessionID: UUID
    let text: String
    let rawText: String
    let date: Date
    let applicationBundleIdentifier: String?
    let modeIdentifier: UUID?

    init(record: HistoryRecord) {
        id = record.id
        sessionID = record.sessionID
        text = record.finalText
        rawText = record.rawText
        date = record.createdAt
        applicationBundleIdentifier = record.applicationBundleIdentifier
        modeIdentifier = record.modeIdentifier
    }
}

@MainActor
final class VoiceInboxService: ObservableObject, VoiceInboxRepository {
    static let shared = VoiceInboxService()

    @Published private(set) var entries: [VoiceInboxEntry] = []
    @Published private(set) var storageError: String?

    private let fileURL: URL
    private let keychain: KeychainStoring
    private let defaults: UserDefaults

    init(
        fileURL: URL? = nil,
        keychain: KeychainStoring = KeychainHelper.shared,
        defaults: UserDefaults = .standard
    ) {
        self.keychain = keychain
        self.defaults = defaults
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let folder = appSupport.appendingPathComponent(
            Constants.applicationSupportDirectoryName,
            isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        self.fileURL = fileURL ?? folder.appendingPathComponent("inbox.enc")
        if !Constants.isRunningTests {
            load()
            cleanup()
        }
    }

    func append(_ record: HistoryRecord) {
        guard isEnabled else { return }
        let text = record.finalText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !text.isEmpty else { return }
        entries.insert(VoiceInboxEntry(record: record), at: 0)
        cleanup(saveAfterCleanup: false)
        save()
    }

    func delete(_ entry: VoiceInboxEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clearAll() {
        entries.removeAll()
        save()
    }

    func clearStorageError() {
        storageError = nil
    }

    func applyPreferences() {
        if isEnabled {
            cleanup()
        } else {
            entries.removeAll()
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func cleanup(saveAfterCleanup: Bool = true) {
        let maxAge = TimeInterval(max(1, retentionDays)) * 86_400
        let now = Date()
        entries.removeAll { now.timeIntervalSince($0.date) > maxAge }
        if saveAfterCleanup { save() }
    }

    private func load() {
        guard isEnabled,
              FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        do {
            let stored = try Data(contentsOf: fileURL)
            let decrypted = try decrypt(stored)
            entries = try JSONDecoder().decode(
                [VoiceInboxEntry].self,
                from: decrypted
            )
            storageError = nil
        } catch {
            storageError = "Impossible de lire la Voice Inbox chiffrée : \(error.localizedDescription)"
        }
    }

    private func save() {
        guard isEnabled else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        do {
            let data = try JSONEncoder().encode(entries)
            let encrypted = try encrypt(data)
            try encrypted.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
            storageError = nil
        } catch {
            storageError = "Impossible d’enregistrer la Voice Inbox : \(error.localizedDescription)"
        }
    }

    private var isEnabled: Bool {
        defaults.object(forKey: Constants.inboxEnabledKey) as? Bool ?? false
    }

    private var retentionDays: Int {
        defaults.object(forKey: Constants.inboxRetentionDaysKey) as? Int ?? 30
    }

    private func encryptionKey() throws -> SymmetricKey {
        if let data = keychain.data(account: Constants.keychainInboxKeyAccount) {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        guard keychain.save(
            data: data,
            account: Constants.keychainInboxKeyAccount
        ) else {
            throw HistoryError.keychainFailure
        }
        return key
    }

    private func encrypt(_ data: Data) throws -> Data {
        let box = try AES.GCM.seal(data, using: encryptionKey())
        guard let combined = box.combined else {
            throw HistoryError.encryptionFailure
        }
        return combined
    }

    private func decrypt(_ data: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: encryptionKey())
    }

    private enum HistoryError: Error {
        case keychainFailure
        case encryptionFailure
    }
}
