import AppKit
import Carbon.HIToolbox
import Foundation

enum ShortcutAction: Hashable {
    case dictate
    case transformSelection
    case mode(UUID)
}

enum ShortcutRegistrationResult: Equatable {
    case registered
    case conflict(existingOwner: String?)
    case unsupported
}

@MainActor
final class ShortcutRouter: ObservableObject {
    @Published private(set) var isMonitoring = false
    @Published private(set) var isHandsFreeActive = false
    @Published private(set) var transformationShortcutAvailable = false
    @Published private(set) var lastRegistrationMessage: String?
    @Published private(set) var isRecordingShortcut = false

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var hotKeyEventHandler: EventHandlerRef?
    private var registeredHotKeys: [
        ShortcutAction: (
            definition: ShortcutDefinition,
            reference: EventHotKeyRef,
            identifier: UInt32
        )
    ] = [:]
    private var actionsByIdentifier: [UInt32: ShortcutAction] = [:]
    private var monitoredDictationShortcut: ShortcutDefinition?
    private var nextHotKeyIdentifier: UInt32 = 10
    private var shortcutIsPressed = false
    private var pendingRelease: DispatchWorkItem?
    private var ignoresNextRelease = false

    var onShortcutPressed: (() -> Void)?
    var onShortcutReleased: (() -> Void)?
    var onCancel: (() -> Void)?
    var onHandsFreeChanged: ((Bool) -> Void)?
    var onTransformationShortcut: (() -> Void)?
    var onModeShortcut: ((UUID) -> Void)?
    var onDictationHotKey: (() -> Void)?

    func startMonitoring() {
        guard !isMonitoring else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.flagsChanged, .keyDown]
        ) { [weak self] event in
            DispatchQueue.main.async {
                self?.handle(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.flagsChanged, .keyDown]
        ) { [weak self] event in
            self?.handle(event)
            return event
        }
        installHotKeyHandler()
        let dictationDefinition = persistedDictationShortcut()
            ?? legacyDictationShortcut()
        _ = register(
            action: .dictate,
            shortcut: dictationDefinition
        )
        let transformDefinition = ModeStore.shared
            .mode(withID: NativeModeCatalog.transformSelectionID)?
            .shortcut
            ?? ShortcutDefinition(
                keyCode: UInt16(kVK_Space),
                modifiers: [.option, .shift],
                side: nil
            )
        transformationShortcutAvailable =
            register(
                action: .transformSelection,
                shortcut: transformDefinition
            ) == .registered
        for mode in ModeStore.shared.visibleModes {
            if let shortcut = mode.shortcut {
                _ = register(action: .mode(mode.id), shortcut: shortcut)
            }
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
        for registration in registeredHotKeys.values {
            UnregisterEventHotKey(registration.reference)
        }
        registeredHotKeys.removeAll()
        actionsByIdentifier.removeAll()
        if let hotKeyEventHandler {
            RemoveEventHandler(hotKeyEventHandler)
            self.hotKeyEventHandler = nil
        }
        pendingRelease?.cancel()
        pendingRelease = nil
        shortcutIsPressed = false
        monitoredDictationShortcut = nil
        ignoresNextRelease = false
        isHandsFreeActive = false
        transformationShortcutAvailable = false
        isMonitoring = false
    }

    @discardableResult
    func register(
        action: ShortcutAction,
        shortcut: ShortcutDefinition
    ) -> ShortcutRegistrationResult {
        guard !shortcut.modifiers.isEmpty else {
            return .unsupported
        }
        if let owner = conflictingOwner(
            for: shortcut,
            excluding: action
        ) {
            return .conflict(existingOwner: owner.displayName)
        }
        if shortcut.side != nil || shortcut.modifiers.contains(.function) {
            guard action == .dictate,
                  shortcut.isSupportedModifierOnlyShortcut else {
                return .unsupported
            }
            if let previous = registeredHotKeys.removeValue(forKey: action) {
                UnregisterEventHotKey(previous.reference)
                actionsByIdentifier.removeValue(
                    forKey: previous.identifier
                )
            }
            monitoredDictationShortcut = shortcut
            lastRegistrationMessage = nil
            return .registered
        }
        guard hotKeyEventHandler != nil else { return .unsupported }

        let identifier = nextHotKeyIdentifier
        nextHotKeyIdentifier += 1
        let hotKeyID = EventHotKeyID(signature: 0x50525359, id: identifier)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.modifiers.carbonFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            return status == eventHotKeyExistsErr
                ? .conflict(existingOwner: nil)
                : .unsupported
        }

        if let previous = registeredHotKeys[action] {
            UnregisterEventHotKey(previous.reference)
            actionsByIdentifier.removeValue(forKey: previous.identifier)
        }
        registeredHotKeys[action] = (shortcut, reference, identifier)
        actionsByIdentifier[identifier] = action
        if action == .dictate {
            monitoredDictationShortcut = nil
        }
        lastRegistrationMessage = nil
        return .registered
    }

    @discardableResult
    func updateShortcut(
        action: ShortcutAction,
        shortcut: ShortcutDefinition
    ) -> ShortcutRegistrationResult {
        let result = register(action: action, shortcut: shortcut)
        switch result {
        case .registered:
            persist(shortcut: shortcut, for: action)
            lastRegistrationMessage = nil
        case .conflict(let owner):
            lastRegistrationMessage = owner.map {
                "Ce raccourci est déjà utilisé par \($0)."
            } ?? "Ce raccourci est déjà réservé par macOS ou une autre application."
        case .unsupported:
            lastRegistrationMessage =
                "Cette combinaison n’est pas prise en charge. Ajoute au moins ⌘, ⌥, ⌃ ou ⇧."
        }
        return result
    }

    func currentShortcut(for action: ShortcutAction) -> ShortcutDefinition? {
        if action == .dictate, let monitoredDictationShortcut {
            return monitoredDictationShortcut
        }
        return registeredHotKeys[action]?.definition
    }

    func setShortcutRecording(_ active: Bool) {
        isRecordingShortcut = active
    }

    func unregister(action: ShortcutAction) {
        if action == .dictate {
            monitoredDictationShortcut = nil
        }
        guard let registration = registeredHotKeys.removeValue(forKey: action)
        else { return }
        UnregisterEventHotKey(registration.reference)
        actionsByIdentifier.removeValue(forKey: registration.identifier)
    }

    private func installHotKeyHandler() {
        guard hotKeyEventHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr,
                      hotKeyID.signature == 0x50525359 else {
                    return OSStatus(eventNotHandledErr)
                }
                let router = Unmanaged<ShortcutRouter>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                DispatchQueue.main.async {
                    router.handleHotKey(identifier: hotKeyID.id)
                }
                return noErr
            },
            1,
            &eventType,
            context,
            &hotKeyEventHandler
        )
        guard handlerStatus == noErr else {
            transformationShortcutAvailable = false
            return
        }
    }

    private func handleHotKey(identifier: UInt32) {
        guard !isRecordingShortcut else { return }
        guard let action = actionsByIdentifier[identifier] else { return }
        switch action {
        case .dictate:
            onDictationHotKey?()
        case .transformSelection:
            onTransformationShortcut?()
        case .mode(let id):
            onModeShortcut?(id)
        }
    }

    private func handle(_ event: NSEvent) {
        guard !isRecordingShortcut else { return }
        if event.type == .keyDown {
            handleKeyDown(event)
            return
        }
        handleFlagsChanged(event)
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard event.keyCode == UInt16(kVK_Escape) else { return }
        pendingRelease?.cancel()
        pendingRelease = nil
        ignoresNextRelease = false
        if isHandsFreeActive {
            isHandsFreeActive = false
            onHandsFreeChanged?(false)
        }
        DispatchQueue.main.async { [weak self] in
            self?.onCancel?()
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard let shortcut = monitoredDictationShortcut else { return }
        let activationMode = ActivationMode(
            rawValue: UserDefaults.standard.string(
                forKey: Constants.activationModeKey
            ) ?? ""
        ) ?? .hold

        guard event.keyCode == shortcut.keyCode else { return }
        let isPressed: Bool
        if shortcut.modifiers.contains(.function) {
            isPressed = event.modifierFlags.contains(.function)
        } else {
            isPressed = CGEventSource.keyState(
                .combinedSessionState,
                key: CGKeyCode(shortcut.keyCode)
            )
        }

        if isPressed && !shortcutIsPressed {
            shortcutIsPressed = true
            if activationMode == .hold {
                handleHoldPressed()
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.onShortcutPressed?()
                }
            }
        } else if !isPressed && shortcutIsPressed {
            shortcutIsPressed = false
            guard activationMode == .hold else { return }
            handleHoldReleased()
        }
    }

    private func handleHoldPressed() {
        if isHandsFreeActive {
            isHandsFreeActive = false
            ignoresNextRelease = true
            onHandsFreeChanged?(false)
            DispatchQueue.main.async { [weak self] in
                self?.onShortcutReleased?()
            }
            return
        }

        if let pendingRelease {
            pendingRelease.cancel()
            self.pendingRelease = nil
            isHandsFreeActive = true
            ignoresNextRelease = true
            onHandsFreeChanged?(true)
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.onShortcutPressed?()
        }
    }

    private func handleHoldReleased() {
        if ignoresNextRelease {
            ignoresNextRelease = false
            return
        }
        guard !isHandsFreeActive else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingRelease = nil
            self.onShortcutReleased?()
        }
        pendingRelease?.cancel()
        pendingRelease = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Constants.handsFreeDoublePressInterval,
            execute: workItem
        )
    }

    private func conflictingOwner(
        for shortcut: ShortcutDefinition,
        excluding action: ShortcutAction
    ) -> ShortcutAction? {
        if action != .dictate,
           monitoredDictationShortcut == shortcut {
            return .dictate
        }
        return registeredHotKeys.first {
            $0.key != action && $0.value.definition == shortcut
        }?.key
    }

    private func persistedDictationShortcut() -> ShortcutDefinition? {
        guard let data = UserDefaults.standard.data(
            forKey: Constants.dictationShortcutDefinitionKey
        ) else {
            return nil
        }
        return try? JSONDecoder().decode(
            ShortcutDefinition.self,
            from: data
        )
    }

    private func legacyDictationShortcut() -> ShortcutDefinition {
        let shortcut = DictationShortcut(
            rawValue: UserDefaults.standard.string(
                forKey: Constants.shortcutKey
            ) ?? ""
        ) ?? .function
        switch shortcut {
        case .function:
            return ShortcutDefinition(
                keyCode: UInt16(kVK_Function),
                modifiers: [.function],
                side: nil
            )
        case .rightOption:
            return ShortcutDefinition(
                keyCode: UInt16(kVK_RightOption),
                modifiers: [.option],
                side: .right
            )
        case .rightCommand:
            return ShortcutDefinition(
                keyCode: UInt16(kVK_RightCommand),
                modifiers: [.command],
                side: .right
            )
        }
    }

    private func persist(
        shortcut: ShortcutDefinition,
        for action: ShortcutAction
    ) {
        switch action {
        case .dictate:
            if let data = try? JSONEncoder().encode(shortcut) {
                UserDefaults.standard.set(
                    data,
                    forKey: Constants.dictationShortcutDefinitionKey
                )
            }
        case .transformSelection:
            ModeStore.shared.setShortcutOverride(
                modeID: NativeModeCatalog.transformSelectionID,
                shortcut: shortcut
            )
        case .mode(let modeID):
            ModeStore.shared.setShortcutOverride(
                modeID: modeID,
                shortcut: shortcut
            )
        }
    }

}

typealias KeyboardService = ShortcutRouter

private extension DictationShortcut {
    var keyCode: UInt16 {
        switch self {
        case .function: return UInt16(kVK_Function)
        case .rightOption: return UInt16(kVK_RightOption)
        case .rightCommand: return UInt16(kVK_RightCommand)
        }
    }
}

private extension ShortcutModifiers {
    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.command) { flags |= UInt32(cmdKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }
}

private extension ShortcutDefinition {
    var isSupportedModifierOnlyShortcut: Bool {
        let supportedKeyCodes: Set<UInt16> = [
            UInt16(kVK_Function),
            UInt16(kVK_Option),
            UInt16(kVK_RightOption),
            UInt16(kVK_Command),
            UInt16(kVK_RightCommand),
            UInt16(kVK_Control),
            UInt16(kVK_RightControl),
            UInt16(kVK_Shift),
            UInt16(kVK_RightShift)
        ]
        return supportedKeyCodes.contains(keyCode)
            && modifiers.subtracting([.function]).rawValue.nonzeroBitCount <= 1
    }
}

private extension ShortcutAction {
    var displayName: String {
        switch self {
        case .dictate: return "Dictée"
        case .transformSelection: return "Transformation"
        case .mode: return "Un autre mode Pressay"
        }
    }
}
