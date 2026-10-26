import AppKit
import Carbon

typealias WindowID = UInt32

@MainActor final class FakeRegistrar: SystemHotKeyRegistering {
    var reserved: Set<SystemHotKeyChord> = []
    var fail: Set<SystemHotKeyChord> = []
    var systemStatus: OSStatus = noErr
    var installStatus: OSStatus = noErr
    var installed = 0, stopped = 0
    var handler: ((UInt32) -> Void)?
    var keys: [SystemHotKeyChord: UInt32] = [:]
    func systemShortcuts() -> (OSStatus, Set<SystemHotKeyChord>) { (systemStatus, reserved) }
    func installHandler(_ handler: @escaping (UInt32) -> Void) -> OSStatus {
        installed += 1
        self.handler = handler
        return installStatus
    }
    func register(_ chord: SystemHotKeyChord, id: UInt32) -> OSStatus {
        if fail.contains(chord) { return OSStatus(eventHotKeyExistsErr) }
        precondition(keys[chord] == nil, "Must unregister old chords before reloading")
        keys[chord] = id
        return noErr
    }
    func stop() { stopped += 1; keys.removeAll(); handler = nil }
    func press(_ keyCode: UInt32, _ modifiers: UInt32 = UInt32(optionKey)) {
        if let id = keys[.init(keyCode:keyCode,modifiers:modifiers)] { handler?(id) }
    }
}

struct ManagedWindow { let id: UInt32; let pid: Int32 }
@MainActor final class TabGroup {
    var windows: [ManagedWindow]
    var activeIndex = 0
    var onActiveSpace = true
    var activeWindow: ManagedWindow? { windows.indices.contains(activeIndex) ? windows[activeIndex] : nil }
    init(_ windows: [ManagedWindow]) { self.windows = windows }
}
struct FakeApp { let processIdentifier: Int32 }
@MainActor final class NSWorkspace {
    static let shared = NSWorkspace()
    var frontmostApplication: FakeApp? = FakeApp(processIdentifier:1)
}
@MainActor final class FakeEngine {
    var focusedID: UInt32? = 11
    var mainID: UInt32?
    func mainWindowID(for pid: Int32) -> UInt32? { mainID }
    func focusedOrMainWindowID(for pid: Int32) -> UInt32? { focusedID }
}
@MainActor final class TabGroupController {
    let ownPID: Int32 = 999
    let engine = FakeEngine()
    var groups: [TabGroup] = []
    var selections: [UInt32] = []
    var preferredMainWindowPID: pid_t?
    var mainWindowPreferenceDeadline = Date.distantPast
    func isGroupOnActiveSpace(_ group: TabGroup) -> Bool { group.onActiveSpace }
    func selectTab(_ id: UInt32, in group: TabGroup) {
        selections.append(id)
        group.activeIndex = group.windows.firstIndex(where: { $0.id == id })!
        engine.focusedID = id
    }
}
