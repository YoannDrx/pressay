import AppKit
import Carbon.HIToolbox

struct TextInjectionTarget {
    let processIdentifier: pid_t
}

@MainActor
final class TextInjector {
    static let shared = TextInjector()
    private init() {}

    private struct PasteboardItemSnapshot {
        let values: [NSPasteboard.PasteboardType: Data]
    }

    func captureTargetApp() -> TextInjectionTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return nil
        }
        return TextInjectionTarget(processIdentifier: app.processIdentifier)
    }

    func inject(text: String, target: TextInjectionTarget?) async -> Bool {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return false }

        let pasteboard = NSPasteboard.general
        let previousContents = snapshot(of: pasteboard)
        pasteboard.clearContents()
        guard pasteboard.setString(cleanText, forType: .string) else {
            restore(previousContents, to: pasteboard)
            return false
        }
        let transcriptionChangeCount = pasteboard.changeCount

        if let target,
           let app = NSRunningApplication(processIdentifier: target.processIdentifier),
           !app.isTerminated {
            app.activate(options: [])
        }

        try? await Task.sleep(for: .milliseconds(250))
        let didPaste = TextInjector.hasAccessibilityPermission() && pasteViaCGEvent()
        try? await Task.sleep(for: .milliseconds(300))

        if pasteboard.changeCount == transcriptionChangeCount {
            restore(previousContents, to: pasteboard)
        }
        return didPaste
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func snapshot(of pasteboard: NSPasteboard) -> [PasteboardItemSnapshot] {
        pasteboard.pasteboardItems?.map { item in
            let values = item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { result, type in
                if let data = item.data(forType: type) {
                    result[type] = data
                }
            }
            return PasteboardItemSnapshot(values: values)
        } ?? []
    }

    private func restore(_ snapshots: [PasteboardItemSnapshot], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !snapshots.isEmpty else { return }

        let items = snapshots.map { snapshot in
            let item = NSPasteboardItem()
            for (type, data) in snapshot.values {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(items)
    }

    private func pasteViaCGEvent() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: false
              ) else {
            return false
        }

        // Publier Cmd+V directement évite AppleScript/System Events et sa
        // permission Automatisation supplémentaire. L'autorisation Accessibilité
        // déjà contrôlée ci-dessus est la seule permission nécessaire.
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    nonisolated static func hasAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    nonisolated static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
