#if APP_STORE
import SwiftUI

struct ShortcutRecorderField: View {
    @ObservedObject var router: ShortcutRouter
    let action: ShortcutAction
    var onRegistered: ((ShortcutDefinition) -> Void)?

    var body: some View {
        Text("Version directe uniquement")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

extension ShortcutDefinition {
    var displayName: String { "Indisponible" }
}
#else
import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorderField: View {
    @ObservedObject var router: ShortcutRouter
    let action: ShortcutAction
    var onRegistered: ((ShortcutDefinition) -> Void)?

    @State private var isRecording = false
    @State private var shortcut: ShortcutDefinition?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Button {
                isRecording.toggle()
                message = nil
            } label: {
                Text(
                    isRecording
                        ? "Saisis le raccourci…"
                        : shortcut?.displayName ?? "Non défini"
                )
                .font(.system(.body, design: .rounded).weight(.semibold))
                .frame(minWidth: 150)
                .padding(.horizontal, 8)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(
                isRecording
                    ? "Enregistrement du raccourci en cours"
                    : "Raccourci \(shortcut?.displayName ?? "non défini")"
            )
            .background {
                ShortcutEventMonitor(
                    isRecording: $isRecording,
                    onCapture: register
                )
                .frame(width: 0, height: 0)
            }

            if let message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Erreur de raccourci. \(message)")
            } else if isRecording {
                Text("Échap annule · maintiens un modificateur pour l’utiliser seul")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            shortcut = router.currentShortcut(for: action)
        }
        .onChange(of: isRecording) { _, active in
            router.setShortcutRecording(active)
        }
        .onDisappear {
            router.setShortcutRecording(false)
        }
    }

    private func register(_ definition: ShortcutDefinition) {
        let result = router.updateShortcut(
            action: action,
            shortcut: definition
        )
        switch result {
        case .registered:
            shortcut = definition
            message = nil
            onRegistered?(definition)
        case .conflict(let owner):
            message = owner.map {
                "Déjà utilisé par \($0). L’ancien raccourci est conservé."
            } ?? "Déjà utilisé par macOS ou une autre app. L’ancien raccourci est conservé."
        case .unsupported:
            message = "Combinaison non prise en charge. L’ancien raccourci est conservé."
        }
    }
}

private struct ShortcutEventMonitor: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (ShortcutDefinition) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        if isRecording {
            context.coordinator.start()
        } else {
            context.coordinator.stop()
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var parent: ShortcutEventMonitor
        private var monitor: Any?
        private var pendingModifier: DispatchWorkItem?

        init(parent: ShortcutEventMonitor) {
            self.parent = parent
        }

        func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .flagsChanged]
            ) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func stop() {
            pendingModifier?.cancel()
            pendingModifier = nil
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            if event.type == .keyDown {
                pendingModifier?.cancel()
                pendingModifier = nil
                if event.keyCode == UInt16(kVK_Escape) {
                    parent.isRecording = false
                    return nil
                }
                let modifiers = ShortcutModifiers(event.modifierFlags)
                guard !modifiers.isEmpty else { return nil }
                capture(
                    ShortcutDefinition(
                        keyCode: event.keyCode,
                        modifiers: modifiers,
                        side: nil
                    )
                )
                return nil
            }

            guard let modifier = ModifierKey(event.keyCode),
                  modifier.isPressed(in: event.modifierFlags) else {
                pendingModifier?.cancel()
                pendingModifier = nil
                return event
            }
            pendingModifier?.cancel()
            let definition = ShortcutDefinition(
                keyCode: event.keyCode,
                modifiers: modifier.modifier,
                side: modifier.side
            )
            let work = DispatchWorkItem { [weak self] in
                self?.capture(definition)
            }
            pendingModifier = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.35,
                execute: work
            )
            return event
        }

        private func capture(_ definition: ShortcutDefinition) {
            pendingModifier?.cancel()
            pendingModifier = nil
            parent.onCapture(definition)
            parent.isRecording = false
        }
    }
}

private struct ModifierKey {
    let modifier: ShortcutModifiers
    let side: ModifierSide?
    let appKitFlag: NSEvent.ModifierFlags

    init?(_ keyCode: UInt16) {
        switch Int(keyCode) {
        case kVK_Function:
            modifier = .function
            side = nil
            appKitFlag = .function
        case kVK_Option:
            modifier = .option
            side = .left
            appKitFlag = .option
        case kVK_RightOption:
            modifier = .option
            side = .right
            appKitFlag = .option
        case kVK_Command:
            modifier = .command
            side = .left
            appKitFlag = .command
        case kVK_RightCommand:
            modifier = .command
            side = .right
            appKitFlag = .command
        case kVK_Control:
            modifier = .control
            side = .left
            appKitFlag = .control
        case kVK_RightControl:
            modifier = .control
            side = .right
            appKitFlag = .control
        case kVK_Shift:
            modifier = .shift
            side = .left
            appKitFlag = .shift
        case kVK_RightShift:
            modifier = .shift
            side = .right
            appKitFlag = .shift
        default:
            return nil
        }
    }

    func isPressed(in flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(appKitFlag)
    }
}

extension ShortcutDefinition {
    var displayName: String {
        if let modifier = ModifierKey(keyCode),
           modifiers == modifier.modifier {
            let sideLabel = side.map {
                $0 == .left ? " gauche" : " droite"
            } ?? ""
            return "\(modifier.modifier.displaySymbols)\(sideLabel)"
        }
        return "\(modifiers.displaySymbols)\(Self.keyLabel(keyCode))"
    }

    private static func keyLabel(_ keyCode: UInt16) -> String {
        let labels: [UInt16: String] = [
            UInt16(kVK_ANSI_A): "A", UInt16(kVK_ANSI_B): "B",
            UInt16(kVK_ANSI_C): "C", UInt16(kVK_ANSI_D): "D",
            UInt16(kVK_ANSI_E): "E", UInt16(kVK_ANSI_F): "F",
            UInt16(kVK_ANSI_G): "G", UInt16(kVK_ANSI_H): "H",
            UInt16(kVK_ANSI_I): "I", UInt16(kVK_ANSI_J): "J",
            UInt16(kVK_ANSI_K): "K", UInt16(kVK_ANSI_L): "L",
            UInt16(kVK_ANSI_M): "M", UInt16(kVK_ANSI_N): "N",
            UInt16(kVK_ANSI_O): "O", UInt16(kVK_ANSI_P): "P",
            UInt16(kVK_ANSI_Q): "Q", UInt16(kVK_ANSI_R): "R",
            UInt16(kVK_ANSI_S): "S", UInt16(kVK_ANSI_T): "T",
            UInt16(kVK_ANSI_U): "U", UInt16(kVK_ANSI_V): "V",
            UInt16(kVK_ANSI_W): "W", UInt16(kVK_ANSI_X): "X",
            UInt16(kVK_ANSI_Y): "Y", UInt16(kVK_ANSI_Z): "Z",
            UInt16(kVK_Space): "Espace", UInt16(kVK_Return): "↩",
            UInt16(kVK_Tab): "⇥", UInt16(kVK_Delete): "⌫",
            UInt16(kVK_ForwardDelete): "⌦",
            UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
            UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
            UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2",
            UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4",
            UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
            UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8",
            UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10",
            UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
            UInt16(kVK_F13): "F13", UInt16(kVK_F14): "F14",
            UInt16(kVK_F15): "F15", UInt16(kVK_F16): "F16",
            UInt16(kVK_F17): "F17", UInt16(kVK_F18): "F18",
            UInt16(kVK_F19): "F19", UInt16(kVK_F20): "F20"
        ]
        return labels[keyCode] ?? "Touche \(keyCode)"
    }
}

private extension ShortcutModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var value: ShortcutModifiers = []
        if flags.contains(.command) { value.insert(.command) }
        if flags.contains(.option) { value.insert(.option) }
        if flags.contains(.control) { value.insert(.control) }
        if flags.contains(.shift) { value.insert(.shift) }
        if flags.contains(.function) { value.insert(.function) }
        self = value
    }

    var displaySymbols: String {
        var value = ""
        if contains(.control) { value += "⌃" }
        if contains(.option) { value += "⌥" }
        if contains(.shift) { value += "⇧" }
        if contains(.command) { value += "⌘" }
        if contains(.function) { value += "Fn" }
        return value
    }
}
#endif
