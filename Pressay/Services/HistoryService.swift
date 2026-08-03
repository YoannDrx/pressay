import AppKit
import Foundation
import CryptoKit

struct TranscriptionEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    let date: Date
    var rawText: String
    var sessionID: UUID?
    var applicationBundleIdentifier: String?
    var modeIdentifier: UUID?
    var transcriptionProvider: String?
    var processingProvider: String?
    var language: String?
    var audioDuration: TimeInterval?
    var contextManifest: [String]
    var deliveryStatus: DeliveryStatus?
    var isFavorite: Bool
    var tags: [String]
    var parentEntryID: UUID?
    var actionProposal: ActionProposal?

    init(
        id: UUID = UUID(),
        text: String,
        date: Date = Date(),
        rawText: String? = nil,
        sessionID: UUID? = nil,
        applicationBundleIdentifier: String? = nil,
        modeIdentifier: UUID? = nil,
        transcriptionProvider: String? = nil,
        processingProvider: String? = nil,
        language: String? = nil,
        audioDuration: TimeInterval? = nil,
        contextManifest: [String] = [],
        deliveryStatus: DeliveryStatus? = nil,
        isFavorite: Bool = false,
        tags: [String] = [],
        parentEntryID: UUID? = nil,
        actionProposal: ActionProposal? = nil
    ) {
        self.id = id
        self.text = text
        self.date = date
        self.rawText = rawText ?? text
        self.sessionID = sessionID
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.modeIdentifier = modeIdentifier
        self.transcriptionProvider = transcriptionProvider
        self.processingProvider = processingProvider
        self.language = language
        self.audioDuration = audioDuration
        self.contextManifest = contextManifest
        self.deliveryStatus = deliveryStatus
        self.isFavorite = isFavorite
        self.tags = tags
        self.parentEntryID = parentEntryID
        self.actionProposal = actionProposal
    }

    init(record: HistoryRecord) {
        self.init(
            id: record.id,
            text: record.finalText,
            date: record.createdAt,
            rawText: record.rawText,
            sessionID: record.sessionID,
            applicationBundleIdentifier: record.applicationBundleIdentifier,
            modeIdentifier: record.modeIdentifier,
            transcriptionProvider: record.transcriptionProvider,
            processingProvider: record.processingProvider,
            language: record.language,
            audioDuration: record.audioDuration,
            contextManifest: record.contextManifest,
            deliveryStatus: record.deliveryStatus,
            actionProposal: record.actionProposal
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, date, rawText, sessionID, applicationBundleIdentifier
        case modeIdentifier, transcriptionProvider, processingProvider, language
        case audioDuration, contextManifest, deliveryStatus, isFavorite, tags
        case parentEntryID, actionProposal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        date = try container.decode(Date.self, forKey: .date)
        rawText = try container.decodeIfPresent(String.self, forKey: .rawText) ?? text
        sessionID = try container.decodeIfPresent(UUID.self, forKey: .sessionID)
        applicationBundleIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .applicationBundleIdentifier
        )
        modeIdentifier = try container.decodeIfPresent(UUID.self, forKey: .modeIdentifier)
        transcriptionProvider = try container.decodeIfPresent(
            String.self,
            forKey: .transcriptionProvider
        )
        processingProvider = try container.decodeIfPresent(
            String.self,
            forKey: .processingProvider
        )
        language = try container.decodeIfPresent(String.self, forKey: .language)
        audioDuration = try container.decodeIfPresent(
            TimeInterval.self,
            forKey: .audioDuration
        )
        contextManifest = try container.decodeIfPresent(
            [String].self,
            forKey: .contextManifest
        ) ?? []
        deliveryStatus = try container.decodeIfPresent(
            DeliveryStatus.self,
            forKey: .deliveryStatus
        )
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        parentEntryID = try container.decodeIfPresent(UUID.self, forKey: .parentEntryID)
        actionProposal = try container.decodeIfPresent(
            ActionProposal.self,
            forKey: .actionProposal
        )
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
        guard isEnabled else { return }
        let cleanText = record.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }
        entries.insert(TranscriptionEntry(record: record), at: 0)
        cleanup(saveAfterCleanup: false)
        save()
    }

    func appendDerived(
        from source: TranscriptionEntry,
        text: String,
        modeIdentifier: UUID?,
        processingProvider: String
    ) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEnabled, !cleanText.isEmpty else { return }
        entries.insert(
            TranscriptionEntry(
                text: cleanText,
                rawText: source.rawText,
                sessionID: source.sessionID,
                applicationBundleIdentifier: source.applicationBundleIdentifier,
                modeIdentifier: modeIdentifier,
                transcriptionProvider: source.transcriptionProvider,
                processingProvider: processingProvider,
                language: source.language,
                contextManifest: source.contextManifest,
                deliveryStatus: .notRequested,
                tags: source.tags,
                parentEntryID: source.id
            ),
            at: 0
        )
        cleanup(saveAfterCleanup: false)
        save()
    }

    func toggleFavorite(_ entry: TranscriptionEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isFavorite.toggle()
        save()
    }

    func updateTags(_ tags: [String], for entry: TranscriptionEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].tags = Self.normalizedTags(tags)
        save()
    }

    func markdownExport(for selectedEntries: [TranscriptionEntry]? = nil) -> String {
        let exported = selectedEntries ?? entries
        let formatter = ISO8601DateFormatter()
        return exported.map { entry in
            var metadata = [formatter.string(from: entry.date)]
            if let provider = entry.transcriptionProvider { metadata.append(provider) }
            if let processor = entry.processingProvider { metadata.append(processor) }
            if !entry.tags.isEmpty {
                metadata.append(entry.tags.map { "#\($0)" }.joined(separator: " "))
            }
            return "## \(metadata.joined(separator: " · "))\n\n\(entry.text)"
        }.joined(separator: "\n\n---\n\n")
    }

    func jsonExport(for selectedEntries: [TranscriptionEntry]? = nil) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(selectedEntries ?? entries)
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

    private static func normalizedTags(_ tags: [String]) -> [String] {
        Array(
            Set(
                tags.map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                        .lowercased()
                }.filter { !$0.isEmpty }
            )
        ).sorted()
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

@MainActor
final class HistoryReprocessingService: ObservableObject {
    static let shared = HistoryReprocessingService()

    @Published private(set) var isProcessing = false
    @Published private(set) var lastMessage: String?
    @Published private(set) var lastError: String?

    private let router: ProcessingRouting
    private let consent: CloudConsentRequesting
    private let history: HistoryService

    init(
        router: ProcessingRouting? = nil,
        consent: CloudConsentRequesting? = nil,
        history: HistoryService? = nil
    ) {
        self.router = router ?? ProcessingRouter(
            registrations: SystemProviderRegistry.processingRegistrations(
                openAI: OpenAITextProcessingService.shared
            )
        )
        self.consent = consent ?? CloudConsentController.shared
        self.history = history ?? HistoryService.shared
    }

    func reprocess(_ entry: TranscriptionEntry, with mode: ModeDefinition) async {
        guard !isProcessing else { return }
        isProcessing = true
        lastMessage = "Retraitement avec \(mode.name)…"
        lastError = nil
        defer { isProcessing = false }

        do {
            if mode.cleaningLevel == .faithful {
                history.appendDerived(
                    from: entry,
                    text: entry.rawText,
                    modeIdentifier: mode.id,
                    processingProvider: "local-faithful"
                )
                lastMessage = "Nouvelle version Fidèle ajoutée à l’historique."
                return
            }

            let processor = try router.provider(
                for: mode,
                capabilities: .current
            )
            if processor.locality == .cloud {
                let decision = await consent.requestConsent(
                    for: CloudPreflight(
                        sessionID: entry.sessionID ?? UUID(),
                        modeID: mode.id,
                        providerID: processor.identifier,
                        modelID: processor.modelIdentifier,
                        spokenText: entry.text,
                        sources: [],
                        characterCounts: [:],
                        exactPayloadPreview: [:]
                    ),
                    allowsRawTranscription: false,
                    requiresExplicitChoice: true
                )
                guard decision == .sendOnce || decision == .alwaysAllowMode else {
                    lastMessage = "Retraitement annulé."
                    return
                }
            }

            let result = try await processor.process(
                TextProcessingRequest(
                    text: entry.text,
                    mode: mode,
                    context: .empty
                )
            )
            history.appendDerived(
                from: entry,
                text: result.text,
                modeIdentifier: mode.id,
                processingProvider: result.providerIdentifier
            )
            lastMessage = "Version \(mode.name) ajoutée ; l’original reste intact."
        } catch is CancellationError {
            lastMessage = "Retraitement annulé."
        } catch {
            lastError = error.localizedDescription
            lastMessage = nil
        }
    }

    func clearMessage() {
        lastMessage = nil
        lastError = nil
    }
}

enum VoiceInboxStatus: String, Codable, CaseIterable {
    case inbox
    case archived
}

struct VoiceInboxEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let sessionID: UUID
    let text: String
    let rawText: String
    let date: Date
    let applicationBundleIdentifier: String?
    let modeIdentifier: UUID?
    var title: String
    var project: String?
    var tags: [String]
    var tasks: [String]
    var detectedDates: [Date]
    var status: VoiceInboxStatus

    init(record: HistoryRecord) {
        id = record.id
        sessionID = record.sessionID
        text = record.finalText
        rawText = record.rawText
        date = record.createdAt
        applicationBundleIdentifier = record.applicationBundleIdentifier
        modeIdentifier = record.modeIdentifier
        let structure = VoiceInboxStructure.extract(from: record.finalText)
        title = structure.title
        project = structure.project
        tags = structure.tags
        tasks = structure.tasks
        detectedDates = structure.dates
        status = .inbox
    }

    private enum CodingKeys: String, CodingKey {
        case id, sessionID, text, rawText, date, applicationBundleIdentifier
        case modeIdentifier, title, project, tags, tasks, detectedDates, status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sessionID = try container.decode(UUID.self, forKey: .sessionID)
        text = try container.decode(String.self, forKey: .text)
        rawText = try container.decodeIfPresent(String.self, forKey: .rawText) ?? text
        date = try container.decode(Date.self, forKey: .date)
        applicationBundleIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .applicationBundleIdentifier
        )
        modeIdentifier = try container.decodeIfPresent(UUID.self, forKey: .modeIdentifier)
        let structure = VoiceInboxStructure.extract(from: text)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? structure.title
        project = try container.decodeIfPresent(String.self, forKey: .project) ?? structure.project
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? structure.tags
        tasks = try container.decodeIfPresent([String].self, forKey: .tasks) ?? structure.tasks
        detectedDates = try container.decodeIfPresent(
            [Date].self,
            forKey: .detectedDates
        ) ?? structure.dates
        status = try container.decodeIfPresent(
            VoiceInboxStatus.self,
            forKey: .status
        ) ?? .inbox
    }
}

private enum VoiceInboxStructure {
    struct Result {
        let title: String
        let project: String?
        let tags: [String]
        let tasks: [String]
        let dates: [Date]
    }

    static func extract(from text: String) -> Result {
        let lines = text.split(whereSeparator: \.isNewline).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        let firstLine = lines.first ?? "Note vocale"
        let title = String(firstLine.prefix(80))
        let tags = hashtags(in: text)
        let project = tags.first
        let tasks = lines.compactMap { line -> String? in
            let markers = ["- [ ] ", "[ ] ", "todo: ", "à faire : ", "action : "]
            let lowercased = line.lowercased()
            guard let marker = markers.first(where: { lowercased.hasPrefix($0) }) else {
                return nil
            }
            return String(line.dropFirst(marker.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        return Result(
            title: title,
            project: project,
            tags: tags,
            tasks: tasks,
            dates: detectedDates(in: text)
        )
    }

    private static func hashtags(in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?<![\p{L}\p{N}_])#([\p{L}\p{N}_-]+)"#
        ) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let values = expression.matches(in: text, range: range).compactMap { match -> String? in
            guard let swiftRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[swiftRange]).lowercased()
        }
        return Array(Set(values)).sorted()
    }

    private static func detectedDates(in text: String) -> [Date] {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.date.rawValue
        ) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, range: range).compactMap(\.date)
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

    func toggleArchived(_ entry: VoiceInboxEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].status = entries[index].status == .inbox ? .archived : .inbox
        save()
    }

    func updateMetadata(
        for entry: VoiceInboxEntry,
        project: String?,
        tags: [String]
    ) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let cleanProject = project?.trimmingCharacters(in: .whitespacesAndNewlines)
        entries[index].project = cleanProject?.isEmpty == false ? cleanProject : nil
        entries[index].tags = Array(
            Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        ).filter { !$0.isEmpty }.sorted()
        save()
    }

    func markdownExport(for selectedEntries: [VoiceInboxEntry]? = nil) -> String {
        let exported = selectedEntries ?? entries
        return exported.map { entry in
            var frontmatter = ["date: \(entry.date.ISO8601Format())"]
            if let project = entry.project { frontmatter.append("project: \(project)") }
            if !entry.tags.isEmpty { frontmatter.append("tags: [\(entry.tags.joined(separator: ", "))]") }
            let tasks = entry.tasks.map { "- [ ] \($0)" }.joined(separator: "\n")
            return "---\n\(frontmatter.joined(separator: "\n"))\n---\n\n# \(entry.title)\n\n\(entry.text)\n\n\(tasks)"
        }.joined(separator: "\n\n")
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

enum ActionJournalStatus: String, Codable, CaseIterable {
    case proposed
    case executed
    case rejected
    case failed
}

struct ActionJournalEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var proposal: ActionProposal
    let createdAt: Date
    var completedAt: Date?
    var status: ActionJournalStatus
    var resultSummary: String?

    init(
        id: UUID = UUID(),
        proposal: ActionProposal,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        status: ActionJournalStatus = .proposed,
        resultSummary: String? = nil
    ) {
        self.id = id
        self.proposal = proposal
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.status = status
        self.resultSummary = resultSummary
    }
}

enum SafeActionPolicy {
    static func normalized(_ proposal: ActionProposal) -> ActionProposal {
        var result = proposal
        result.risk = risk(for: proposal.kind)
        if result.idempotencyKey.isEmpty {
            result.idempotencyKey = fingerprint(
                kind: result.kind,
                parameters: result.parameters
            )
        }
        return result
    }

    static func risk(for kind: ActionKind) -> ActionRisk {
        switch kind {
        case .copyText:
            .automatic
        case .createNoteDraft, .createReminderDraft, .createCalendarDraft,
             .prepareShortcut, .prepareTerminalCommand:
            .preview
        case .openApplication, .openURL, .revealFile:
            .confirmationRequired
        case .writeAuthorizedFile, .createRemoteResource:
            .forbidden
        }
    }

    static func fingerprint(
        kind: ActionKind,
        parameters: [String: String]
    ) -> String {
        let canonical = ([kind.rawValue] + parameters.keys.sorted().map {
            "\($0)=\(parameters[$0] ?? "")"
        }).joined(separator: "|")
        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

@MainActor
enum VoiceInboxActionFactory {
    static func note(from entry: VoiceInboxEntry) -> ActionProposal {
        let body = VoiceInboxService.shared.markdownExport(for: [entry])
        return proposal(
            kind: .createNoteDraft,
            parameters: ["text": body, "title": entry.title],
            summary: "Préparer une note Markdown « \(entry.title) »",
            preview: body
        )
    }

    static func reminder(from entry: VoiceInboxEntry) -> ActionProposal {
        let reminderText = entry.tasks.first ?? entry.text
        return proposal(
            kind: .createReminderDraft,
            parameters: ["text": reminderText],
            summary: "Préparer un rappel",
            preview: reminderText
        )
    }

    static func calendar(from entry: VoiceInboxEntry) -> ActionProposal? {
        guard let date = entry.detectedDates.first else { return nil }
        return proposal(
            kind: .createCalendarDraft,
            parameters: [
                "title": entry.title,
                "date": date.ISO8601Format(),
                "notes": entry.text
            ],
            summary: "Préparer un événement « \(entry.title) »",
            preview: "\(entry.title)\n\(date.formatted(date: .long, time: .shortened))\n\n\(entry.text)"
        )
    }

    private static func proposal(
        kind: ActionKind,
        parameters: [String: String],
        summary: String,
        preview: String
    ) -> ActionProposal {
        SafeActionPolicy.normalized(
            ActionProposal(
                kind: kind,
                parameters: parameters,
                summary: summary,
                risk: .preview,
                preconditions: ["Aperçu validé par l’utilisateur"],
                idempotencyKey: SafeActionPolicy.fingerprint(
                    kind: kind,
                    parameters: parameters
                ),
                preview: preview
            )
        )
    }
}

@MainActor
final class ActionJournalService: ObservableObject {
    static let shared = ActionJournalService()

    @Published private(set) var entries: [ActionJournalEntry] = []
    @Published private(set) var storageError: String?

    private let fileURL: URL
    private let keychain: KeychainStoring

    init(fileURL: URL? = nil, keychain: KeychainStoring = KeychainHelper.shared) {
        self.keychain = keychain
        let folder = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent(
            Constants.applicationSupportDirectoryName,
            isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        self.fileURL = fileURL ?? folder.appendingPathComponent("action-journal.enc")
        if !Constants.isRunningTests { load() }
    }

    var pendingEntries: [ActionJournalEntry] {
        entries.filter { $0.status == .proposed }
    }

    @discardableResult
    func propose(_ proposal: ActionProposal) -> ActionJournalEntry {
        let normalized = SafeActionPolicy.normalized(proposal)
        if let existing = entries.first(where: {
            $0.proposal.idempotencyKey == normalized.idempotencyKey
                && $0.status != .rejected
        }) {
            return existing
        }
        let entry = ActionJournalEntry(proposal: normalized)
        entries.insert(entry, at: 0)
        save()
        return entry
    }

    func reject(_ entry: ActionJournalEntry) {
        complete(entry, status: .rejected, summary: "Action refusée")
    }

    func execute(_ entry: ActionJournalEntry) {
        guard entry.status == .proposed else { return }
        let proposal = SafeActionPolicy.normalized(entry.proposal)
        guard proposal.risk != .forbidden else {
            complete(
                entry,
                status: .failed,
                summary: "Cette action est interdite par la politique de sécurité."
            )
            return
        }

        let didExecute: Bool
        let summary: String
        switch proposal.kind {
        case .copyText, .createNoteDraft, .createReminderDraft,
             .createCalendarDraft, .prepareShortcut, .prepareTerminalCommand:
            let text = proposal.parameters["text"]
                ?? proposal.preview
                ?? proposal.parameters.values.joined(separator: "\n")
            TextInjector.shared.copyToPasteboard(text)
            didExecute = true
            summary = "Brouillon copié dans le presse-papiers"
        case .openURL:
            if let value = proposal.parameters["url"],
               let url = URL(string: value),
               ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                didExecute = NSWorkspace.shared.open(url)
                summary = didExecute ? "Lien ouvert" : "Impossible d’ouvrir le lien"
            } else {
                didExecute = false
                summary = "URL absente ou non autorisée"
            }
        case .openApplication:
            if let bundleID = proposal.parameters["bundleIdentifier"],
               let url = NSWorkspace.shared.urlForApplication(
                   withBundleIdentifier: bundleID
               ) {
                NSWorkspace.shared.openApplication(
                    at: url,
                    configuration: .init()
                ) { _, _ in }
                didExecute = true
                summary = "Application ouverte"
            } else {
                didExecute = false
                summary = "Application introuvable"
            }
        case .revealFile, .writeAuthorizedFile, .createRemoteResource:
            didExecute = false
            summary = "Action non autorisée dans cette version"
        }
        complete(
            entry,
            status: didExecute ? .executed : .failed,
            summary: summary
        )
    }

    func clearCompleted() {
        entries.removeAll { $0.status != .proposed }
        save()
    }

    private func complete(
        _ entry: ActionJournalEntry,
        status: ActionJournalStatus,
        summary: String
    ) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].status = status
        entries[index].completedAt = Date()
        entries[index].resultSummary = summary
        save()
    }

    private func load() {
        guard let stored = try? Data(contentsOf: fileURL) else { return }
        do {
            let box = try AES.GCM.SealedBox(combined: stored)
            let decrypted = try AES.GCM.open(box, using: encryptionKey())
            entries = try JSONDecoder().decode([ActionJournalEntry].self, from: decrypted)
        } catch {
            storageError = "Impossible de lire le journal d’actions chiffré."
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            let box = try AES.GCM.seal(data, using: encryptionKey())
            guard let combined = box.combined else { throw JournalError.encryptionFailure }
            try combined.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
            storageError = nil
        } catch {
            storageError = "Impossible d’enregistrer le journal d’actions chiffré."
        }
    }

    private func encryptionKey() throws -> SymmetricKey {
        if let data = keychain.data(account: Constants.keychainActionJournalKeyAccount) {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        guard keychain.save(
            data: data,
            account: Constants.keychainActionJournalKeyAccount
        ) else { throw JournalError.keychainFailure }
        return key
    }

    private enum JournalError: Error {
        case keychainFailure
        case encryptionFailure
    }
}
