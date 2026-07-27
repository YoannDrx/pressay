import AppKit
import Carbon.HIToolbox

final class TextInjector {
    static let shared = TextInjector()
    private init() {}

    private struct PasteboardItemSnapshot {
        let values: [NSPasteboard.PasteboardType: Data]
    }

    /// L'app qui avait le focus quand l'enregistrement a commencé
    private var targetApp: NSRunningApplication?

    /// Capture l'app frontale actuelle (à appeler au début de l'enregistrement)
    func captureTargetApp() {
        targetApp = NSWorkspace.shared.frontmostApplication
    }

    func clearTargetApp() {
        targetApp = nil
    }

    /// Injecte le texte à la position actuelle du curseur via CGEvent
    func inject(text: String) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            clearTargetApp()
            return
        }

        // Sauvegarder tous les types (texte, image, fichier…), pas uniquement String.
        let pasteboard = NSPasteboard.general
        let previousContents = snapshot(of: pasteboard)

        pasteboard.clearContents()
        guard pasteboard.setString(cleanText, forType: .string) else {
            restore(previousContents, to: pasteboard)
            clearTargetApp()
            return
        }
        let transcriptionChangeCount = pasteboard.changeCount

        // S'assurer que l'app cible a le focus
        if let app = targetApp, !app.isTerminated {
            app.activate(options: [])
        }

        // Délai pour s'assurer que l'app est vraiment active
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.pasteViaCGEvent()

            // Ne jamais écraser une nouvelle copie effectuée par l'utilisateur
            // pendant l'injection.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if pasteboard.changeCount == transcriptionChangeCount {
                    self.restore(previousContents, to: pasteboard)
                }
                self.clearTargetApp()
            }
        }
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

    private func pasteViaCGEvent() {
        // CGEvent ne fonctionne pas bien sur macOS récent, utiliser AppleScript
        pasteViaAppleScript()
    }

    private func pasteViaAppleScript() {
        let script = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }

        if error != nil {
            // Fallback: via le menu Edit > Paste de l'app frontale
            pasteViaMenuClick()
        }
    }

    private func pasteViaMenuClick() {
        guard let appName = targetApp?.localizedName else { return }
        let escapedAppName = appName
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "\(escapedAppName)"
            activate
        end tell
        delay 0.1
        tell application "System Events"
            tell process "\(escapedAppName)"
                click menu item "Paste" of menu "Edit" of menu bar 1
            end tell
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
    }

    /// Vérifie si l'app a les permissions d'accessibilité
    static func hasAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Demande les permissions d'accessibilité
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
