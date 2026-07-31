#if APP_STORE
import AppKit
import Foundation

actor ClipboardTransactionCoordinator {
    static let shared = ClipboardTransactionCoordinator()

    func captureSelection() async -> String? { nil }

    func paste(_ text: String) async -> Bool {
        await setPermanentString(text)
        return false
    }

    func setPermanentString(_ text: String) async {
        await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
    }
}
#else
import AppKit
import Carbon.HIToolbox
import Foundation

actor ClipboardTransactionCoordinator {
    static let shared = ClipboardTransactionCoordinator()

    private struct ItemSnapshot: Sendable {
        let values: [String: Data]
    }

    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func captureSelection() async -> String? {
        await acquire()
        defer { release() }

        let initial = await MainActor.run { snapshot(NSPasteboard.general) }
        let preparedCount = await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return pasteboard.changeCount
        }

        guard await MainActor.run(body: {
            Self.postKeyboardShortcut(keyCode: CGKeyCode(kVK_ANSI_C))
        }) else {
            await restoreIfUnchanged(initial, expectedChangeCount: preparedCount)
            return nil
        }

        guard let producedCount = await waitForFirstChange(after: preparedCount)
        else {
            await restoreIfUnchanged(initial, expectedChangeCount: preparedCount)
            return nil
        }

        try? await Task.sleep(for: .milliseconds(50))
        let stable = await MainActor.run {
            NSPasteboard.general.changeCount == producedCount
        }
        guard stable else {
            // Un autre producteur a écrit pendant la transaction : Pressay ne
            // lit ni ne restaure un presse-papiers dont il n'est plus propriétaire.
            return nil
        }

        let selectedText = await MainActor.run {
            NSPasteboard.general.string(forType: .string)
        }
        await restoreIfUnchanged(initial, expectedChangeCount: producedCount)
        return selectedText
    }

    func paste(_ text: String) async -> Bool {
        await acquire()
        defer { release() }

        let initial = await MainActor.run { snapshot(NSPasteboard.general) }
        let pressayChangeCount: Int? = await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.setString(text, forType: .string) else {
                restore(initial, to: pasteboard)
                return nil
            }
            return pasteboard.changeCount
        }
        guard let pressayChangeCount else { return false }

        let posted = await MainActor.run {
            Self.postKeyboardShortcut(keyCode: CGKeyCode(kVK_ANSI_V))
        }
        try? await Task.sleep(for: .milliseconds(300))
        await restoreIfUnchanged(initial, expectedChangeCount: pressayChangeCount)
        return posted
    }

    func setPermanentString(_ text: String) async {
        await acquire()
        defer { release() }
        await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
    }

    private func waitForFirstChange(after changeCount: Int) async -> Int? {
        let deadline = ContinuousClock.now + .milliseconds(500)
        while ContinuousClock.now < deadline {
            if Task.isCancelled { return nil }
            let current = await MainActor.run { NSPasteboard.general.changeCount }
            if current != changeCount {
                return current
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }

    private func restoreIfUnchanged(
        _ snapshots: [ItemSnapshot],
        expectedChangeCount: Int
    ) async {
        await MainActor.run {
            let pasteboard = NSPasteboard.general
            guard pasteboard.changeCount == expectedChangeCount else { return }
            restore(snapshots, to: pasteboard)
        }
    }

    private func acquire() async {
        if !isBusy {
            isBusy = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            waiters.removeFirst().resume()
        }
    }

    @MainActor
    private func snapshot(_ pasteboard: NSPasteboard) -> [ItemSnapshot] {
        pasteboard.pasteboardItems?.map { item in
            ItemSnapshot(
                values: item.types.reduce(into: [String: Data]()) {
                    result,
                    type in
                    if let data = item.data(forType: type) {
                        result[type.rawValue] = data
                    }
                }
            )
        } ?? []
    }

    @MainActor
    private func restore(
        _ snapshots: [ItemSnapshot],
        to pasteboard: NSPasteboard
    ) {
        pasteboard.clearContents()
        guard !snapshots.isEmpty else { return }
        let items = snapshots.map { snapshot in
            let item = NSPasteboardItem()
            for (rawType, data) in snapshot.values {
                item.setData(data, forType: NSPasteboard.PasteboardType(rawType))
            }
            return item
        }
        pasteboard.writeObjects(items)
    }

    @MainActor
    private static func postKeyboardShortcut(keyCode: CGKeyCode) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: false
              ) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
#endif
