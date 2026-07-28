import AppKit
import Carbon.HIToolbox
import OSLog

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

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "fr.yodev.pressay",
        category: "TextDelivery"
    )

    private struct UndoToken {
        let target: TextInjectionTarget
        let insertedUTF16Length: Int
        let expiresAt: Date
    }

    private var lastUndoToken: UndoToken?
    private(set) var lastDeliveryStrategy: DeliveryStrategy = .copied
    private(set) var lastDeliveryFailure: DeliveryFailureReason?

    var canUndoLastInsertion: Bool {
        guard let token = lastUndoToken else { return false }
        return token.expiresAt > Date()
    }

    func captureTargetApp() -> TextInjectionTarget? {
        AccessibilityContextService.shared.capture().target
    }

    func inject(text: String, target: TextInjectionTarget?) async -> Bool {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return fail(.emptyText) }
        guard TextInjector.hasAccessibilityPermission() else {
            return fail(.accessibilityNotGranted)
        }
        guard let target else { return fail(.missingTarget) }
        guard !target.snapshot.isSecure else { return fail(.secureTarget) }
        guard target.snapshot.isEditable else {
            logger.error(
                """
                Non-editable AX target: role=\(target.snapshot.elementRole ?? "nil", privacy: .public), \
                subrole=\(target.snapshot.elementSubrole ?? "nil", privacy: .public), \
                selectedTextSettable=\(target.snapshot.canWriteSelectedText, privacy: .public), \
                valueSettable=\(target.snapshot.canWriteValue, privacy: .public)
                """
            )
            return fail(.nonEditableTarget)
        }
        lastUndoToken = nil
        lastDeliveryStrategy = .copied
        lastDeliveryFailure = nil

        guard let app = NSRunningApplication(
            processIdentifier: target.processIdentifier
        ),
              !app.isTerminated else {
            return fail(.targetApplicationUnavailable)
        }
        app.activate(options: [.activateAllWindows])
        guard await waitForTargetApplication(target.processIdentifier) else {
            return fail(.targetApplicationNotFrontmost)
        }
        guard windowStillMatches(target) else {
            return fail(.targetWindowChanged)
        }
        guard focusedElementStillMatches(target) else {
            return false
        }
        guard await selectionStillMatches(target) else {
            return fail(.selectionChanged)
        }

        let prefersPaste = prefersPasteDelivery(for: target)
        if target.snapshot.canWriteSelectedText,
           !prefersPaste,
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
        if !didPaste {
            return fail(.clipboardPasteFailed)
        }
        return didPaste
    }

    private func prefersPasteDelivery(for target: TextInjectionTarget) -> Bool {
        let application = NSRunningApplication(
            processIdentifier: target.processIdentifier
        )
        let isElectron = application?.bundleURL
            .flatMap(Bundle.init(url:))?
            .infoDictionary?["ElectronAsarIntegrity"] != nil
        let prefersPaste = DeliveryPreferencePolicy.prefersPaste(
            bundleIdentifier: target.snapshot.bundleIdentifier,
            isElectron: isElectron
        )
        if prefersPaste {
            logger.debug(
                "Using paste delivery for web/Electron target"
            )
        }
        return prefersPaste
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
        return focusedElementStillMatches(target, recordsFailure: false)
    }

    private func focusedElementStillMatches(
        _ target: TextInjectionTarget,
        recordsFailure: Bool = true
    ) -> Bool {
        guard let originalElement = target.focusedElement else {
            if recordsFailure {
                _ = fail(.focusedElementUnavailable)
            }
            return false
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
            if recordsFailure {
                _ = fail(.focusedElementUnavailable)
            }
            return false
        }
        let currentElement = unsafeBitCast(currentValue, to: AXUIElement.self)
        if CFEqual(currentElement, originalElement) {
            return true
        }
        let role = copiedString(
            attribute: kAXRoleAttribute,
            from: currentElement
        )
        let subrole = copiedString(
            attribute: kAXSubroleAttribute,
            from: currentElement
        )
        let isProtected = copiedBool(
            attribute: NSAccessibility.Attribute.containsProtectedContent.rawValue,
            from: currentElement
        )
        let isSecure = subrole == kAXSecureTextFieldSubrole as String
            || isProtected
        let canWriteSelectedText = isAttributeSettable(
            kAXSelectedTextAttribute,
            on: currentElement
        )
        let canWriteValue = isAttributeSettable(
            kAXValueAttribute,
            on: currentElement
        )
        let reportsEditable = copiedBool(
            attribute: kAXIsEditableAttribute,
            from: currentElement
        )
        let matches = FocusedElementValidator.matches(
            snapshot: target.snapshot,
            currentIdentifier: copiedString(
                attribute: kAXIdentifierAttribute,
                from: currentElement
            ),
            currentFrameHash: elementFrameHash(for: currentElement),
            currentRole: role,
            currentSubrole: subrole,
            currentIsSecure: isSecure,
            currentIsEditable: AccessibilityEditabilityPolicy.isEditable(
                role: role,
                isSecure: isSecure,
                reportsEditable: reportsEditable,
                canWriteSelectedText: canWriteSelectedText,
                canWriteValue: canWriteValue
            )
        )
        if !matches, recordsFailure {
            _ = fail(.focusedElementChanged)
        }
        return matches
    }

    private func waitForTargetApplication(
        _ processIdentifier: pid_t
    ) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(1)
        while ContinuousClock.now < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier
                == processIdentifier {
                return true
            }
            if Task.isCancelled { return false }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return false
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

    private func copiedString(
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

    private func copiedBool(
        attribute: String,
        from element: AXUIElement
    ) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else {
            return false
        }
        return (value as? NSNumber)?.boolValue ?? false
    }

    private func isAttributeSettable(
        _ attribute: String,
        on element: AXUIElement
    ) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(
            element,
            attribute as CFString,
            &settable
        ) == .success && settable.boolValue
    }

    private func elementFrameHash(for element: AXUIElement) -> String? {
        guard let position = copiedPoint(
            attribute: kAXPositionAttribute,
            from: element
        ),
              let size = copiedSize(
                attribute: kAXSizeAttribute,
                from: element
              ) else {
            return nil
        }
        return SelectionFingerprint.hash(
            [
                stableCoordinate(position.x),
                stableCoordinate(position.y),
                stableCoordinate(size.width),
                stableCoordinate(size.height)
            ].joined(separator: "|")
        )
    }

    private func copiedPoint(
        attribute: String,
        from element: AXUIElement
    ) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    private func copiedSize(
        attribute: String,
        from element: AXUIElement
    ) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgSize else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }

    private func stableCoordinate(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
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

    private func fail(_ reason: DeliveryFailureReason) -> Bool {
        lastDeliveryStrategy = .copied
        lastDeliveryFailure = reason
        logger.error("Delivery failed: \(reason.rawValue, privacy: .public)")
        return false
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
            kAXIdentifierAttribute as CFString,
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

enum AccessibilityEditabilityPolicy {
    private static let textRoles: Set<String> = [
        "AXTextField",
        "AXTextArea",
        "AXComboBox",
        "AXSearchField"
    ]

    static func isEditable(
        role: String?,
        isSecure: Bool,
        reportsEditable: Bool,
        canWriteSelectedText: Bool,
        canWriteValue: Bool
    ) -> Bool {
        guard !isSecure else { return false }
        if textRoles.contains(role ?? "") || canWriteSelectedText {
            return true
        }
        return reportsEditable && canWriteValue
    }
}

enum DeliveryPreferencePolicy {
    private static let browserBundleIdentifiers: Set<String> = [
        "com.apple.Safari",
        "com.brave.Browser",
        "com.google.Chrome",
        "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi",
        "company.thebrowser.Browser",
        "org.mozilla.firefox"
    ]

    static func prefersPaste(
        bundleIdentifier: String?,
        isElectron: Bool
    ) -> Bool {
        isElectron
            || bundleIdentifier.map(browserBundleIdentifiers.contains) == true
    }
}

enum FocusedElementValidator {
    static func matches(
        snapshot: TargetSnapshot,
        currentIdentifier: String?,
        currentFrameHash: String?,
        currentRole: String?,
        currentSubrole: String?,
        currentIsSecure: Bool,
        currentIsEditable: Bool
    ) -> Bool {
        guard !currentIsSecure,
              currentIsEditable,
              currentRole == snapshot.elementRole,
              currentSubrole == snapshot.elementSubrole else {
            return false
        }
        if let expectedIdentifier = snapshot.elementIdentifier {
            guard currentIdentifier == expectedIdentifier else {
                return false
            }
            if let expectedFrameHash = snapshot.elementFrameHash {
                return currentFrameHash == expectedFrameHash
            }
            return true
        }
        guard let expectedFrameHash = snapshot.elementFrameHash else {
            return false
        }
        return currentFrameHash == expectedFrameHash
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
