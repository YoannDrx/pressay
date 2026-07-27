import AppKit
import Carbon.HIToolbox

struct TextInjectionTarget {
    let snapshot: TargetSnapshot
    let focusedElement: AXUIElement?
    let selectionRange: CFRange?
    let selectedText: String?

    var processIdentifier: pid_t { snapshot.processIdentifier }

    init(
        snapshot: TargetSnapshot,
        focusedElement: AXUIElement?,
        selectionRange: CFRange? = nil,
        selectedText: String? = nil
    ) {
        self.snapshot = snapshot
        self.focusedElement = focusedElement
        self.selectionRange = selectionRange
        self.selectedText = selectedText
    }
}

@MainActor
final class TextInjector: TextDelivering {
    static let shared = TextInjector()
    private init() {}

    private struct UndoToken {
        let target: TextInjectionTarget
        let insertedUTF16Length: Int
        let expiresAt: Date
    }

    private var lastUndoToken: UndoToken?
    private(set) var lastDeliveryStrategy: DeliveryStrategy = .copied

    var canUndoLastInsertion: Bool {
        guard let token = lastUndoToken else { return false }
        return token.expiresAt > Date()
    }

    func captureTargetApp() -> TextInjectionTarget? {
        AccessibilityContextService.shared.capture().target
    }

    func inject(text: String, target: TextInjectionTarget?) async -> Bool {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty,
              let target,
              !target.snapshot.isSecure,
              target.snapshot.isEditable else {
            lastDeliveryStrategy = .copied
            return false
        }
        lastUndoToken = nil
        lastDeliveryStrategy = .copied

        if let app = NSRunningApplication(processIdentifier: target.processIdentifier),
           !app.isTerminated {
            app.activate(options: [])
        }
        try? await Task.sleep(for: .milliseconds(250))
        guard TextInjector.hasAccessibilityPermission(),
              isOriginalTargetStillFocused(target),
              await selectionStillMatches(target) else {
            return false
        }

        if target.snapshot.canWriteSelectedText,
           let element = target.focusedElement,
           AXUIElementSetAttributeValue(
               element,
               kAXSelectedTextAttribute as CFString,
               cleanText as CFString
           ) == .success {
            rememberUndo(for: target, insertedText: cleanText)
            lastDeliveryStrategy = .accessibilityReplacement
            return true
        }

        let didPaste = await ClipboardTransactionCoordinator.shared.paste(cleanText)
        if didPaste,
           target.focusedElement != nil,
           target.selectionRange != nil {
            rememberUndo(for: target, insertedText: cleanText)
        }
        lastDeliveryStrategy = didPaste ? .paste : .copied
        return didPaste
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func undoLastInsertion() -> Bool {
        guard let token = lastUndoToken,
              token.expiresAt > Date(),
              let element = token.target.focusedElement,
              let originalRange = token.target.selectionRange,
              isOriginalTargetStillFocused(token.target),
              let currentRange = selectedTextRange(from: element),
              currentRange.location == originalRange.location + token.insertedUTF16Length,
              currentRange.length == 0 else {
            lastUndoToken = nil
            return false
        }

        var insertedRange = CFRange(
            location: originalRange.location,
            length: token.insertedUTF16Length
        )
        guard let rangeValue = AXValueCreate(.cfRange, &insertedRange),
              AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                rangeValue
              ) == .success,
              AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                (token.target.selectedText ?? "") as CFString
              ) == .success else {
            lastUndoToken = nil
            return false
        }

        var restoredRange = originalRange
        if let restoredRangeValue = AXValueCreate(.cfRange, &restoredRange) {
            _ = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                restoredRangeValue
            )
        }
        lastUndoToken = nil
        return true
    }

    private func isOriginalTargetStillFocused(_ target: TextInjectionTarget) -> Bool {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier == target.processIdentifier,
              target.snapshot.bundleIdentifier == nil
                || application.bundleIdentifier == target.snapshot.bundleIdentifier else {
            return false
        }
        guard windowStillMatches(target) else { return false }
        guard let originalElement = target.focusedElement else {
            return true
        }
        let appElement = AXUIElementCreateApplication(target.processIdentifier)
        var currentValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &currentValue
        ) == .success,
              let currentValue,
              CFGetTypeID(currentValue) == AXUIElementGetTypeID() else {
            return false
        }
        let currentElement = unsafeBitCast(currentValue, to: AXUIElement.self)
        return CFEqual(currentElement, originalElement)
    }

    private func selectedTextRange(from element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        ) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        return AXValueGetValue(axValue, .cfRange, &range) ? range : nil
    }

    private func selectionStillMatches(_ target: TextInjectionTarget) async -> Bool {
        let currentRange = target.focusedElement.flatMap(
            selectedTextRange(from:)
        )
        let currentAXText = target.focusedElement.flatMap(
            selectedText(from:)
        )
        let fallbackText: String?
        if target.snapshot.selectedTextHash != nil,
           !target.snapshot.canReadSelectedText {
            fallbackText = await ClipboardTransactionCoordinator.shared
                .captureSelection()
        } else {
            fallbackText = nil
        }
        return TargetSelectionValidator.matches(
            snapshot: target.snapshot,
            currentRange: currentRange,
            currentAXText: currentAXText,
            fallbackText: fallbackText
        )
    }

    private func selectedText(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value as? String
    }

    private func rememberUndo(
        for target: TextInjectionTarget,
        insertedText: String
    ) {
        lastUndoToken = UndoToken(
            target: target,
            insertedUTF16Length: (insertedText as NSString).length,
            expiresAt: Date().addingTimeInterval(8)
        )
    }

    private func windowStillMatches(_ target: TextInjectionTarget) -> Bool {
        guard let expected = target.snapshot.windowIdentifier else {
            return true
        }
        let appElement = AXUIElementCreateApplication(target.processIdentifier)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        ) == .success,
              let windowValue,
              CFGetTypeID(windowValue) == AXUIElementGetTypeID() else {
            return false
        }
        let window = unsafeBitCast(windowValue, to: AXUIElement.self)
        var identifierValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            window,
            "AXIdentifier" as CFString,
            &identifierValue
        ) == .success,
           let identifier = identifierValue as? String {
            return identifier == expected
        }
        var titleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window,
            kAXTitleAttribute as CFString,
            &titleValue
        ) == .success,
              let title = titleValue as? String else {
            return false
        }
        return SelectionFingerprint.hash(
            "\(target.processIdentifier)|\(title)"
        ) == expected
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

enum TargetSelectionValidator {
    static func matches(
        snapshot: TargetSnapshot,
        currentRange: CFRange?,
        currentAXText: String?,
        fallbackText: String?
    ) -> Bool {
        if let expectedLocation = snapshot.selectionLocation,
           let expectedLength = snapshot.selectionLength {
            guard let currentRange,
                  currentRange.location == expectedLocation,
                  currentRange.length == expectedLength else {
                return false
            }
        }

        guard let expectedHash = snapshot.selectedTextHash else {
            return true
        }
        let currentText: String?
        if snapshot.canReadSelectedText {
            currentText = currentAXText
        } else {
            currentText = fallbackText
        }
        guard let currentText else { return false }
        return SelectionFingerprint.hash(currentText) == expectedHash
    }
}
