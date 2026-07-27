import AppKit
import Carbon.HIToolbox
import Foundation

final class KeyboardService: ObservableObject {
    @Published private(set) var isMonitoring = false

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var shortcutIsPressed = false

    var onShortcutPressed: (() -> Void)?
    var onShortcutReleased: (() -> Void)?

    func startMonitoring() {
        guard !isMonitoring else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
        isMonitoring = true
    }

    func stopMonitoring() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        shortcutIsPressed = false
        isMonitoring = false
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let defaults = UserDefaults.standard
        let shortcut = DictationShortcut(
            rawValue: defaults.string(forKey: Constants.shortcutKey) ?? ""
        ) ?? .function
        let activationMode = ActivationMode(
            rawValue: defaults.string(forKey: Constants.activationModeKey) ?? ""
        ) ?? .hold

        guard event.keyCode == shortcut.keyCode else { return }
        let isPressed: Bool
        if shortcut == .function {
            isPressed = event.modifierFlags.contains(.function)
        } else {
            isPressed = CGEventSource.keyState(
                .combinedSessionState,
                key: CGKeyCode(shortcut.keyCode)
            )
        }

        if isPressed && !shortcutIsPressed {
            shortcutIsPressed = true
            DispatchQueue.main.async { [weak self] in
                self?.onShortcutPressed?()
            }
        } else if !isPressed && shortcutIsPressed {
            shortcutIsPressed = false
            guard activationMode == .hold else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onShortcutReleased?()
            }
        }
    }

    deinit {
        stopMonitoring()
    }
}

private extension DictationShortcut {
    var keyCode: UInt16 {
        switch self {
        case .function: return UInt16(kVK_Function)
        case .rightOption: return UInt16(kVK_RightOption)
        case .rightCommand: return UInt16(kVK_RightCommand)
        }
    }
}
