import AppKit
import Foundation

@MainActor
final class InMemoryReplayBuffer: ReplayBuffer {
    static let shared = InMemoryReplayBuffer()

    private struct Entry {
        let data: Data
        let expiresAt: Date
        let insertedAt: Date
    }

    private let maximumEntries: Int
    private let maximumEntryBytes: Int
    private let retention: TimeInterval
    private var entries: [UUID: Entry] = [:]
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    init(
        maximumEntries: Int = 3,
        maximumEntryBytes: Int = 10 * 1_024 * 1_024,
        retention: TimeInterval = 5 * 60
    ) {
        self.maximumEntries = maximumEntries
        self.maximumEntryBytes = maximumEntryBytes
        self.retention = retention
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.removeAll()
        }
        source.resume()
        memoryPressureSource = source
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.removeAll()
            }
        }
    }

    func retain(_ audio: Data, for sessionID: UUID) {
        purgeExpired()
        guard audio.count <= maximumEntryBytes else {
            entries.removeValue(forKey: sessionID)
            return
        }
        entries[sessionID] = Entry(
            data: audio,
            expiresAt: Date().addingTimeInterval(retention),
            insertedAt: Date()
        )
        while entries.count > maximumEntries,
              let oldest = entries.min(by: {
                  $0.value.insertedAt < $1.value.insertedAt
              })?.key {
            entries.removeValue(forKey: oldest)
        }
    }

    func audio(for sessionID: UUID) -> Data? {
        purgeExpired()
        return entries[sessionID]?.data
    }

    func remove(sessionID: UUID) {
        entries.removeValue(forKey: sessionID)
    }

    func removeAll() {
        entries.removeAll(keepingCapacity: false)
    }

    private func purgeExpired() {
        let now = Date()
        entries = entries.filter { $0.value.expiresAt > now }
    }
}
