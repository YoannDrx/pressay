import AppKit
import Carbon.HIToolbox
import Foundation

final class KeyboardService: ObservableObject {
    @Published private(set) var isMonitoring = false

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var fnIsPressed = false

    /// Appelé quand Fn est pressé (début enregistrement)
    var onFnPressed: (() -> Void)?
    /// Appelé quand Fn est relâché (fin enregistrement)
    var onFnReleased: (() -> Void)?

    func startMonitoring() {
        guard !isMonitoring else { return }

        // Monitor global (quand l'app n'est pas au premier plan)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        // Monitor local (quand l'app est au premier plan)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        isMonitoring = true
    }

    func stopMonitoring() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        isMonitoring = false
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        // Les touches F1…F12 portent aussi le flag `.function`. Seule la vraie
        // touche Fn/Globe (keyCode 63) doit piloter l'enregistrement.
        guard event.keyCode == UInt16(kVK_Function) else { return }

        let fnKeyPressed = event.modifierFlags.contains(.function)

        // Fn vient d'être pressé
        if fnKeyPressed && !fnIsPressed {
            fnIsPressed = true
            DispatchQueue.main.async { [weak self] in
                self?.onFnPressed?()
            }
        }
        // Fn vient d'être relâché
        else if !fnKeyPressed && fnIsPressed {
            fnIsPressed = false
            DispatchQueue.main.async { [weak self] in
                self?.onFnReleased?()
            }
        }
    }

    deinit {
        stopMonitoring()
    }
}
