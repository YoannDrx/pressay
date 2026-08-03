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

    func pasteDictation(_ text: String) async -> Bool {
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
    func captureSelection() async -> String? {
        guard tryAcquire() else { return nil }
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
        // A stale or concurrent clipboard transaction must never hold a
        // dictated result hostage. Failing fast routes the text to Pressay's
        // permanent copy fallback instead of waiting without a deadline.
        guard tryAcquire() else { return false }
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

    func pasteDictationUsingApplicationMenu(
        _ text: String,
        processIdentifier: pid_t
    ) async -> Bool {
        guard tryAcquire() else { return false }
        defer { release() }

        let prepared = await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return pasteboard.setString(text, forType: .string)
        }
        guard prepared else { return false }

        let pressed = await MainActor.run {
            Self.performPasteMenuItem(processIdentifier: processIdentifier)
        }
        if pressed {
            try? await Task.sleep(for: .milliseconds(120))
        }
        return pressed
    }

    func pasteDictation(_ text: String) async -> Bool {
        // Dictation favors latency and predictability. Keep the dictated text
        // in the clipboard instead of eagerly loading and restoring every
        // pasteboard representation owned by another application.
        guard tryAcquire() else { return false }
        defer { release() }

        let prepared = await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return pasteboard.setString(text, forType: .string)
        }
        guard prepared else { return false }
        let posted = await MainActor.run {
            Self.postKeyboardShortcut(keyCode: CGKeyCode(kVK_ANSI_V))
        }
        try? await Task.sleep(for: .milliseconds(120))
        return posted
    }

    func setPermanentString(_ text: String) async {
        let ownsTransaction = tryAcquire()
        defer {
            if ownsTransaction { release() }
        }
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

    private func tryAcquire() -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        return true
    }

    private func release() {
        isBusy = false
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

    @MainActor
    private static func performPasteMenuItem(
        processIdentifier: pid_t
    ) -> Bool {
        let application = AXUIElementCreateApplication(processIdentifier)
        guard let menuBar = copiedElement(
            attribute: kAXMenuBarAttribute,
            from: application
        ),
              let pasteItem = pasteMenuItem(in: menuBar, remainingDepth: 4)
        else {
            return false
        }
        return AXUIElementPerformAction(
            pasteItem,
            kAXPressAction as CFString
        ) == .success
    }

    @MainActor
    private static func pasteMenuItem(
        in element: AXUIElement,
        remainingDepth: Int
    ) -> AXUIElement? {
        let role = copiedString(attribute: kAXRoleAttribute, from: element)
        let title = copiedString(attribute: kAXTitleAttribute, from: element)?
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if role == kAXMenuItemRole as String,
           title == "paste" || title == "coller" {
            if copiedBool(attribute: kAXEnabledAttribute, from: element) == false {
                return nil
            }
            return element
        }

        guard remainingDepth > 0,
              let children = copiedElements(
                attribute: kAXChildrenAttribute,
                from: element
              ) else {
            return nil
        }
        for child in children {
            if let match = pasteMenuItem(
                in: child,
                remainingDepth: remainingDepth - 1
            ) {
                return match
            }
        }
        return nil
    }

    @MainActor
    private static func copiedElement(
        attribute: String,
        from element: AXUIElement
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    @MainActor
    private static func copiedElements(
        attribute: String,
        from element: AXUIElement
    ) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success,
              let value,
              CFGetTypeID(value) == CFArrayGetTypeID() else {
            return nil
        }
        let array = unsafeBitCast(value, to: CFArray.self)
        return (0..<CFArrayGetCount(array)).compactMap { index in
            guard let rawValue = CFArrayGetValueAtIndex(array, index) else {
                return nil
            }
            let child = unsafeBitCast(rawValue, to: CFTypeRef.self)
            guard CFGetTypeID(child) == AXUIElementGetTypeID() else {
                return nil
            }
            return unsafeBitCast(child, to: AXUIElement.self)
        }
    }

    @MainActor
    private static func copiedString(
        attribute: String,
        from element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value as? String
    }

    @MainActor
    private static func copiedBool(
        attribute: String,
        from element: AXUIElement
    ) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return (value as? NSNumber)?.boolValue
    }
}
#endif
