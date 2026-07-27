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
        let focusedElement = copiedElement(attribute: kAXFocusedUIElementAttribute, from: appElement)
        let role = copiedString(attribute: kAXRoleAttribute, from: focusedElement)
        let subrole = copiedString(attribute: kAXSubroleAttribute, from: focusedElement)
        let isProtected = copiedBool(
            attribute: NSAccessibility.Attribute.containsProtectedContent.rawValue,
            from: focusedElement
        )
        let isSecure = subrole == kAXSecureTextFieldSubrole as String || isProtected
        let isEditable = Self.editableRoles.contains(role ?? "")
        let window = copiedElement(attribute: kAXWindowAttribute, from: focusedElement)
            ?? copiedElement(attribute: kAXFocusedWindowAttribute, from: appElement)
        let windowTitle = copiedString(attribute: kAXTitleAttribute, from: window)
        let windowIdentifier = copiedString(attribute: "AXIdentifier", from: window)
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
            elementRole: role,
            elementSubrole: subrole,
            selectedTextHash: selectionHash,
            selectionLocation: selectedTextRange?.location,
            selectionLength: selectedTextRange?.length,
            canReadSelectedText: selectedText != nil,
            canWriteSelectedText: isAttributeSettable(
                kAXSelectedTextAttribute,
                on: focusedElement
            ),
            canWriteValue: isAttributeSettable(
                kAXValueAttribute,
                on: focusedElement
            ),
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

    private static let editableRoles: Set<String> = [
        "AXTextField",
        "AXTextArea",
        "AXComboBox",
        "AXSearchField"
    ]
}
