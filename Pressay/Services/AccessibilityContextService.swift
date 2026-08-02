#if APP_STORE
import Foundation

@MainActor
final class AccessibilityContextService: ContextCapturing {
    static let shared = AccessibilityContextService()
    private init() {}

    func capture() -> ContextCaptureResult {
        ContextCaptureResult(target: nil, context: .empty)
    }

    func recoverEditableTarget(
        from initialCapture: ContextCaptureResult
    ) async -> ContextCaptureResult {
        initialCapture
    }

    func captureSelectionFallback(
        from initialCapture: ContextCaptureResult
    ) async -> ContextCaptureResult {
        initialCapture
    }

}
#else
import AppKit
import ApplicationServices
import Foundation

@MainActor
final class AccessibilityContextService: ContextCapturing {
    static let shared = AccessibilityContextService()

    private let maximumSurroundingCharacters = 4_000

    func capture() -> ContextCaptureResult {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return ContextCaptureResult(target: nil, context: .empty)
        }

        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let focusedElement = focusedElement(
            in: appElement,
            processIdentifier: application.processIdentifier
        )
        let role = copiedString(attribute: kAXRoleAttribute, from: focusedElement)
        let subrole = copiedString(attribute: kAXSubroleAttribute, from: focusedElement)
        let isProtected = copiedBool(
            attribute: NSAccessibility.Attribute.containsProtectedContent.rawValue,
            from: focusedElement
        )
        let isSecure = subrole == kAXSecureTextFieldSubrole as String || isProtected
        let canWriteSelectedText = isAttributeSettable(
            kAXSelectedTextAttribute,
            on: focusedElement
        )
        let canWriteValue = isAttributeSettable(
            kAXValueAttribute,
            on: focusedElement
        )
        let reportsEditable = copiedBool(
            attribute: kAXIsEditableAttribute,
            from: focusedElement
        )
        let isEditable = AccessibilityEditabilityPolicy.isEditable(
            role: role,
            isSecure: isSecure,
            reportsEditable: reportsEditable,
            canWriteSelectedText: canWriteSelectedText,
            canWriteValue: canWriteValue
        )
        let window = copiedElement(attribute: kAXWindowAttribute, from: focusedElement)
            ?? copiedElement(attribute: kAXFocusedWindowAttribute, from: appElement)
        let windowTitle = copiedString(attribute: kAXTitleAttribute, from: window)
        let windowIdentifier = copiedString(attribute: kAXIdentifierAttribute, from: window)
            ?? windowTitle.flatMap {
                SelectionFingerprint.hash(
                    "\(application.processIdentifier)|\($0)"
                )
            }

        let selectedText = isSecure
            ? nil
            : copiedString(attribute: kAXSelectedTextAttribute, from: focusedElement)
        let selectedTextRange = isSecure
            ? nil
            : copiedRange(attribute: kAXSelectedTextRangeAttribute, from: focusedElement)
        let selectionHash = selectedText.flatMap(SelectionFingerprint.hash)
        let surrounding = isSecure
            ? (before: nil, after: nil)
            : surroundingText(from: focusedElement)

        let snapshot = TargetSnapshot(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            applicationName: application.localizedName,
            windowTitle: windowTitle,
            windowIdentifier: windowIdentifier,
            elementIdentifier: copiedString(
                attribute: kAXIdentifierAttribute,
                from: focusedElement
            ),
            elementFrameHash: elementFrameHash(for: focusedElement),
            elementRole: role,
            elementSubrole: subrole,
            selectedTextHash: selectionHash,
            selectionLocation: selectedTextRange?.location,
            selectionLength: selectedTextRange?.length,
            canReadSelectedText: selectedText != nil,
            canWriteSelectedText: canWriteSelectedText,
            canWriteValue: canWriteValue,
            isSecure: isSecure,
            isEditable: isEditable
        )
        let target = TextInjectionTarget(
            snapshot: snapshot,
            focusedElement: focusedElement,
            selectionRange: selectedTextRange,
            selectedText: selectedText
        )

        var sources: Set<ContextSource> = [.application]
        if windowTitle != nil { sources.insert(.windowTitle) }
        if selectedText?.isEmpty == false { sources.insert(.selection) }
        if surrounding.before != nil || surrounding.after != nil {
            sources.insert(.surroundingText)
        }

        let context = ContextSnapshot(
            applicationBundleIdentifier: application.bundleIdentifier,
            applicationName: application.localizedName,
            windowTitle: isSecure ? nil : windowTitle,
            selectedText: selectedText?.isEmpty == false ? selectedText : nil,
            textBeforeSelection: surrounding.before,
            textAfterSelection: surrounding.after,
            sources: isSecure ? [.application] : sources
        )
        return ContextCaptureResult(target: target, context: context)
    }

    func recoverEditableTarget(
        from initialCapture: ContextCaptureResult
    ) async -> ContextCaptureResult {
        guard let initialTarget = initialCapture.target,
              !initialTarget.snapshot.isSecure,
              !initialTarget.snapshot.isEditable else {
            return initialCapture
        }

        for _ in 0..<8 {
            try? await Task.sleep(for: .milliseconds(35))
            guard !Task.isCancelled,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier
                    == initialTarget.processIdentifier else {
                return initialCapture
            }
            let candidate = capture()
            guard targetIdentityMatches(
                initial: initialTarget.snapshot,
                candidate: candidate.target?.snapshot
            ) else {
                continue
            }
            if candidate.target?.snapshot.isEditable == true {
                return candidate
            }
        }
        return initialCapture
    }

    func captureSelectionFallback(
        from initialCapture: ContextCaptureResult
    ) async -> ContextCaptureResult {
        guard initialCapture.context.selectedText?.isEmpty != false,
              let target = initialCapture.target,
              !target.snapshot.isSecure,
              TextInjector.hasAccessibilityPermission(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier
                == target.processIdentifier,
              let selectedText = await copiedSelectionViaPasteboard(),
              !selectedText.isEmpty else {
            return initialCapture
        }

        let snapshot = target.snapshot
        let updatedSnapshot = TargetSnapshot(
            processIdentifier: snapshot.processIdentifier,
            bundleIdentifier: snapshot.bundleIdentifier,
            applicationName: snapshot.applicationName,
            windowTitle: snapshot.windowTitle,
            windowIdentifier: snapshot.windowIdentifier,
            elementIdentifier: snapshot.elementIdentifier,
            elementFrameHash: snapshot.elementFrameHash,
            elementRole: snapshot.elementRole,
            elementSubrole: snapshot.elementSubrole,
            selectedTextHash: SelectionFingerprint.hash(selectedText),
            selectionLocation: snapshot.selectionLocation,
            selectionLength: snapshot.selectionLength,
            canReadSelectedText: snapshot.canReadSelectedText,
            canWriteSelectedText: snapshot.canWriteSelectedText,
            canWriteValue: snapshot.canWriteValue,
            isSecure: snapshot.isSecure,
            isEditable: snapshot.isEditable
        )
        let updatedTarget = TextInjectionTarget(
            snapshot: updatedSnapshot,
            focusedElement: target.focusedElement,
            selectionRange: target.selectionRange,
            selectedText: selectedText
        )
        var context = initialCapture.context
        context.selectedText = selectedText
        context.sources.insert(.selection)
        return ContextCaptureResult(target: updatedTarget, context: context)
    }

    private func surroundingText(from element: AXUIElement?) -> (before: String?, after: String?) {
        guard let element,
              let value = copiedString(attribute: kAXValueAttribute, from: element),
              let range = copiedRange(attribute: kAXSelectedTextRangeAttribute, from: element) else {
            return (nil, nil)
        }

        let string = value as NSString
        let safeLocation = min(max(0, range.location), string.length)
        let safeLength = min(max(0, range.length), string.length - safeLocation)
        let beforeStart = max(0, safeLocation - maximumSurroundingCharacters)
        let afterEnd = min(
            string.length,
            safeLocation + safeLength + maximumSurroundingCharacters
        )
        let before = string.substring(
            with: NSRange(location: beforeStart, length: safeLocation - beforeStart)
        )
        let afterLocation = safeLocation + safeLength
        let after = string.substring(
            with: NSRange(location: afterLocation, length: afterEnd - afterLocation)
        )
        return (
            before.isEmpty ? nil : before,
            after.isEmpty ? nil : after
        )
    }

    private func targetIdentityMatches(
        initial: TargetSnapshot,
        candidate: TargetSnapshot?
    ) -> Bool {
        guard let candidate,
              candidate.processIdentifier == initial.processIdentifier,
              candidate.bundleIdentifier == initial.bundleIdentifier else {
            return false
        }
        if let initialWindowIdentifier = initial.windowIdentifier,
           let candidateWindowIdentifier = candidate.windowIdentifier {
            return initialWindowIdentifier == candidateWindowIdentifier
        }
        return candidate.windowTitle == initial.windowTitle
    }

    private func copiedElement(attribute: String, from element: AXUIElement?) -> AXUIElement? {
        guard let element else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func focusedElement(
        in appElement: AXUIElement,
        processIdentifier: pid_t
    ) -> AXUIElement? {
        if let focused = copiedElement(
            attribute: kAXFocusedUIElementAttribute,
            from: appElement
        ) {
            return focused
        }
        guard TextInjector.hasAccessibilityPermission(),
              AXUIElementSetAttributeValue(
                appElement,
                "AXManualAccessibility" as CFString,
                kCFBooleanTrue
              ) == .success else {
            return nil
        }

        // Electron/Chromium may publish its accessibility tree one run-loop
        // turn after AXManualAccessibility is enabled.
        for _ in 0..<5 {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier
                    == processIdentifier else {
                return nil
            }
            if let focused = copiedElement(
                attribute: kAXFocusedUIElementAttribute,
                from: appElement
            ) {
                return focused
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return nil
    }

    private func copiedString(attribute: String, from element: AXUIElement?) -> String? {
        guard let element else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func copiedBool(attribute: String, from element: AXUIElement?) -> Bool {
        guard let element else { return false }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return false
        }
        return (value as? NSNumber)?.boolValue ?? false
    }

    private func copiedRange(attribute: String, from element: AXUIElement?) -> CFRange? {
        guard let element else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        return AXValueGetValue(axValue, .cfRange, &range) ? range : nil
    }

    private func elementFrameHash(for element: AXUIElement?) -> String? {
        guard let element,
              let position = copiedPoint(
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

    private func isAttributeSettable(
        _ attribute: String,
        on element: AXUIElement?
    ) -> Bool {
        guard let element else { return false }
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(
            element,
            attribute as CFString,
            &settable
        ) == .success && settable.boolValue
    }

    private func copiedSelectionViaPasteboard() async -> String? {
        await ClipboardTransactionCoordinator.shared.captureSelection()
    }
}
#endif
