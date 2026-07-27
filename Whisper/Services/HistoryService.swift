import Foundation

struct TranscriptionEntry: Codable, Identifiable {
    let id: UUID
    let text: String
    let date: Date

    init(text: String) {
        self.id = UUID()
        self.text = text
        self.date = Date()
    }
}

final class HistoryService: ObservableObject {
    static let shared = HistoryService()

    @Published private(set) var entries: [TranscriptionEntry] = []

    private let fileURL: URL
    private let maxAge: TimeInterval = 24 * 60 * 60 // 24 heures

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("Whisper", isDirectory: true)

        // Créer le dossier si nécessaire
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)

        fileURL = appFolder.appendingPathComponent("history.json")
        load()
        cleanup()
    }

    func add(_ text: String) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }

        let entry = TranscriptionEntry(text: cleanText)
        entries.insert(entry, at: 0)
        cleanup(saveAfterCleanup: false)
        save()
    }

    func delete(_ entry: TranscriptionEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clearAll() {
        entries.removeAll()
        save()
    }

    private func cleanup(saveAfterCleanup: Bool = true) {
        let now = Date()
        entries.removeAll { now.timeIntervalSince($0.date) > maxAge }
        if saveAfterCleanup {
            save()
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([TranscriptionEntry].self, from: data) else {
            return
        }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
