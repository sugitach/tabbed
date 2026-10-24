import AppKit
import Carbon
import CoreGraphics

/// Receives registered hotkey actions. A false result means the focused window
/// is ineligible; it does not replay the reserved chord into another app.
@MainActor
protocol KeyboardShortcutMonitorDelegate: AnyObject {
    func keyboardShortcutSelectTab(at index: Int) -> Bool
    func keyboardShortcutCycleTab(forward: Bool) -> Bool
}

struct SystemHotKeyChord: Hashable {
    let keyCode: UInt32
    let modifiers: UInt32
}

/// OS registration boundary, replaceable in tests without registering any keys.
@MainActor
protocol SystemHotKeyRegistering: AnyObject {
    func systemShortcuts() -> (OSStatus, Set<SystemHotKeyChord>)
    func installHandler(_ handler: @escaping (UInt32) -> Void) -> OSStatus
    func register(_ chord: SystemHotKeyChord, id: UInt32) -> OSStatus
    func stop()
}

/// Registers only configured chords with the system. No keyboard event tap,
/// raw key observer, input suppression callback, or synthetic input is used.
@MainActor
final class KeyboardShortcutMonitor {
    weak var delegate: KeyboardShortcutMonitorDelegate?
    private(set) var settings: ShortcutSettings
    private(set) var registrationIssues: [String] = [] {
        didSet { onRegistrationIssuesChanged?(registrationIssues) }
    }
    var onRegistrationIssuesChanged: (([String]) -> Void)?

    private enum Action { case select(Int), cycle(Bool) }
    private let registrar: SystemHotKeyRegistering
    private var actions: [UInt32: Action] = [:]
    private var isStarted = false
    // Do not reuse IDs on reload: queued events from old registrations are stale.
    private var nextID: UInt32 = 1

    init(settings: ShortcutSettings, registrar: SystemHotKeyRegistering? = nil) {
        self.settings = settings
        self.registrar = registrar ?? CarbonHotKeyRegistrar()
    }

    @discardableResult
    func start() -> Bool {
        guard !isStarted else { return true }
        registrationIssues = []
        guard settings.enabled else { return true }

        let (queryStatus, reserved) = registrar.systemShortcuts()
        guard queryStatus == noErr else {
            registrationIssues = ["Could not check system shortcuts (\(queryStatus)); no shortcuts registered."]
            // Window management can still run without keyboard shortcuts.
            isStarted = true
            return true
        }
        let status = registrar.installHandler { [weak self] id in self?.handle(id: id) }
        guard status == noErr else {
            registrationIssues = ["Could not install shortcut handler (\(status))."]
            registrar.stop()
            return false
        }
        isStarted = true

        let base = Self.carbonModifiers(settings.modifiers)
        var bindings: [(UInt32, UInt32, String, Action)] = []
        if settings.selectByNumber {
            let codes: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
            for (index, code) in codes.enumerated() {
                bindings.append((code, base, String(index + 1), .select(index)))
            }
        }
        if settings.cycle {
            bindings.append((48, base, "Tab", .cycle(true)))
            if !settings.modifiers.contains(.maskShift) {
                bindings.append((48, base | UInt32(shiftKey), "Tab", .cycle(false)))
            }
        }

        var issues: [String] = []
        for (code, modifiers, key, action) in bindings {
            let chord = SystemHotKeyChord(keyCode: code, modifiers: modifiers)
            let label = Self.label(modifiers: modifiers, key: key)
            guard !reserved.contains(chord) else {
                issues.append("\(label): conflicts with a system shortcut; not registered.")
                continue
            }
            let id = nextID
            nextID &+= 1
            let result = registrar.register(chord, id: id)
            if result == noErr {
                actions[id] = action
            } else {
                issues.append("\(label): could not register (\(result)); choose another modifier in Configuration.")
            }
        }
        registrationIssues = issues
        for issue in issues { NSLog("[KeyboardShortcutMonitor] %@", issue) }
        return true
    }

    func stop() {
        actions.removeAll()
        registrar.stop()
        isStarted = false
    }

    func apply(settings: ShortcutSettings) {
        stop()
        self.settings = settings
        start()
    }

    private func handle(id: UInt32) {
        guard isStarted, settings.enabled, let action = actions[id], let delegate else { return }
        switch action {
        case .select(let index): _ = delegate.keyboardShortcutSelectTab(at: index)
        case .cycle(let forward): _ = delegate.keyboardShortcutCycleTab(forward: forward)
        }
    }

    private static func carbonModifiers(_ flags: CGEventFlags) -> UInt32 {
        var result: UInt32 = 0
        for (flag, mask): (CGEventFlags, Int) in [
            (.maskCommand, cmdKey), (.maskControl, controlKey),
            (.maskAlternate, optionKey), (.maskShift, shiftKey),
            (.maskSecondaryFn, kEventKeyModifierFnMask)
        ] where flags.contains(flag) { result |= UInt32(mask) }
        return result
    }

    private static func label(modifiers: UInt32, key: String) -> String {
        var result = ""
        for (mask, symbol): (Int, String) in [
            (controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"),
            (cmdKey, "⌘"), (kEventKeyModifierFnMask, "fn+")
        ] where modifiers & UInt32(mask) != 0 { result += symbol }
        return result + key
    }
}

@MainActor
final class CarbonHotKeyRegistrar: SystemHotKeyRegistering {
    private static let signature: OSType = 0x54616264 // Tabd
    private var handlerRef: EventHandlerRef?
    private var handler: ((UInt32) -> Void)?
    private var hotKeys: [EventHotKeyRef] = []

    func systemShortcuts() -> (OSStatus, Set<SystemHotKeyChord>) {
        var array: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&array)
        guard status == noErr, let entries = array?.takeRetainedValue() as? [[String: Any]] else {
            return (status == noErr ? OSStatus(paramErr) : status, [])
        }
        let chords = entries.compactMap { entry -> SystemHotKeyChord? in
            guard (entry[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true,
                  let code = entry[kHISymbolicHotKeyCode as String] as? NSNumber,
                  let modifiers = entry[kHISymbolicHotKeyModifiers as String] as? NSNumber else { return nil }
            return SystemHotKeyChord(keyCode: code.uint32Value, modifiers: modifiers.uint32Value)
        }
        return (noErr, Set(chords))
    }

    func installHandler(_ handler: @escaping (UInt32) -> Void) -> OSStatus {
        self.handler = handler
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        return InstallEventHandler(GetApplicationEventTarget(), Self.callback, 1, &type,
            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    func register(_ chord: SystemHotKeyChord, id: UInt32) -> OSStatus {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(chord.keyCode, chord.modifiers,
            EventHotKeyID(signature: Self.signature, id: id), GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive), &ref)
        if status == noErr, let ref { hotKeys.append(ref) }
        return status
    }

    func stop() {
        handler = nil
        for ref in hotKeys {
            let status = UnregisterEventHotKey(ref)
            if status != noErr { NSLog("[KeyboardShortcutMonitor] unregister failed: %d", status) }
        }
        hotKeys.removeAll()
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
    }

    private static let callback: EventHandlerUPP = { _, event, context in
        guard let event, let context else { return OSStatus(eventNotHandledErr) }
        var key = EventHotKeyID()
        let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
        guard status == noErr else { return status }
        return MainActor.assumeIsolated {
            guard key.signature == signature else { return OSStatus(eventNotHandledErr) }
            let registrar = Unmanaged<CarbonHotKeyRegistrar>.fromOpaque(context).takeUnretainedValue()
            registrar.handler?(key.id)
            return noErr
        }
    }
}
