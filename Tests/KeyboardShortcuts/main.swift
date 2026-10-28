import AppKit
import Carbon

MainActor.assumeIsolated {
    func drain() { RunLoop.main.run(until: Date().addingTimeInterval(0.08)) }
    let os = FakeRegistrar()
    let monitor = KeyboardShortcutMonitor(settings:.default,registrar:os)
    let controller = TabGroupController()
    let group = TabGroup([.init(id:11,pid:1),.init(id:12,pid:1)])
    controller.groups = [group]
    monitor.delegate = controller
    var messages: [String] = []
    monitor.onRegistrationIssuesChanged = { messages = $0 }
    precondition(monitor.start() && monitor.start())
    precondition(os.installed==1 && os.keys.count==11 && messages.isEmpty)
    os.press(19); drain() // Option+2
    precondition(controller.selections==[12])
    os.press(19) // Already active: no extra window action.
    precondition(controller.selections==[12])
    os.press(25) // No ninth tab: no window action.
    precondition(controller.selections==[12])
    os.press(48); drain() // Next wraps to first.
    precondition(controller.selections==[12,11])
    os.press(48,UInt32(optionKey|shiftKey)); drain() // Previous wraps to last.
    precondition(controller.selections==[12,11,12])
    // Same application, different focused window: do nothing.
    let before = controller.selections
    controller.engine.focusedID = 13
    os.press(18); os.press(48)
    precondition(controller.selections==before)
    // Foreign application / own app / no frontmost app / other Space: no action.
    controller.engine.focusedID = 12
    for app in [FakeApp(processIdentifier:2),FakeApp(processIdentifier:999),nil] {
        NSWorkspace.shared.frontmostApplication = app
        os.press(18)
        precondition(controller.selections==before)
    }
    NSWorkspace.shared.frontmostApplication = FakeApp(processIdentifier:1)
    group.onActiveSpace = false
    os.press(18); precondition(controller.selections==before)
    group.onActiveSpace = true
    do {
        // A notification changed the main window, while focused still names
        // an active tab in a different group of the same process.
        let c = TabGroupController()
        let old = TabGroup([.init(id:11,pid:1),.init(id:12,pid:1)])
        let target = TabGroup([.init(id:21,pid:1),.init(id:22,pid:1)])
        target.activeIndex = 1; c.groups = [old,target]
        c.engine.mainID = 22
        c.preferredMainWindowPID = 1
        c.mainWindowPreferenceDeadline = Date().addingTimeInterval(1)
        precondition(c.keyboardShortcutSelectTab(at:0)); drain(); precondition(c.selections == [21])
        precondition(old.activeIndex == 0 && target.activeIndex == 0)
        c.engine.mainID = nil
        c.engine.focusedID = 99
        precondition(!c.keyboardShortcutCycleTab(forward:true) && c.selections == [21],
                     "missing Main cannot give an ungrouped Focused window shortcut ownership")
        c.engine.focusedID = 21
        precondition(c.keyboardShortcutCycleTab(forward:true)); drain()
        precondition(c.selections == [21,22], "Focused fallback keeps subsequent shortcuts available")
        c.engine.focusedID = 21 // Previous member while native activation settles.
        target.focusSettlementUntil = ProcessInfo.processInfo.systemUptime + 1
        precondition(c.keyboardShortcutCycleTab(forward:true)); drain()
        precondition(c.selections == [21,22,21], "missing Main also supports settling-group shortcuts")
        c.mainWindowPreferenceDeadline = .distantPast
        c.engine.focusedID = 11
        precondition(c.keyboardShortcutCycleTab(forward:true)); drain(); precondition(c.selections == [21,22,21,12])
    }
    // A queued burst applies the final logical intent once, preserving every
    // cycle step and mixed numeric/reverse commands without native AX replay.
    do {
        let c = TabGroupController()
        let g = TabGroup([.init(id:11,pid:1),.init(id:12,pid:1),.init(id:13,pid:1)])
        c.groups = [g]
        for _ in 0..<101 { precondition(c.keyboardShortcutCycleTab(forward:true)) }
        precondition(c.selections.isEmpty)
        drain()
        precondition(c.selections == [13] && g.activeIndex == 2)
        precondition(c.keyboardShortcutSelectTab(at:0))
        precondition(c.keyboardShortcutCycleTab(forward:false))
        precondition(c.keyboardShortcutCycleTab(forward:true))
        drain()
        precondition(c.selections == [13,11])
        for _ in 0..<3 { precondition(c.keyboardShortcutCycleTab(forward:true)) }
        drain()
        precondition(c.selections == [13,11], "full cycle needs no native switch")
        precondition(c.keyboardShortcutSelectTab(at:1))
        c.engine.focusedID = 99
        drain()
        precondition(c.selections == [13,11], "focus leaving the group cancels the queued switch")
        c.engine.focusedID = 11
        precondition(c.keyboardShortcutSelectTab(at:1))
        c.groups = []
        drain()
        precondition(c.selections == [13,11], "removed groups cannot be revived")
    }
    do {
        let c = TabGroupController()
        let g = TabGroup([.init(id:11,pid:1),.init(id:12,pid:1),.init(id:13,pid:1)])
        c.groups = [g]
        // A notification/mouse selection wins over an older queued shortcut.
        precondition(c.keyboardShortcutSelectTab(at:1))
        g.activeIndex = 2; c.engine.focusedID = 13
        drain()
        precondition(c.selections.isEmpty)
        g.focusSettlementUntil = ProcessInfo.processInfo.systemUptime + 1
        c.engine.focusedID = 11 // Previous AX member while current tab is 13.
        precondition(c.keyboardShortcutCycleTab(forward:false))
        drain()
        precondition(c.selections == [12], "settling AX cannot discard the next shortcut batch")
        c.isApplyingLayout = true
        precondition(c.keyboardShortcutSelectTab(at:0))
        drain()
        precondition(c.selections == [12], "no shortcut switch during another layout")
        c.isApplyingLayout = false
        drain()
        precondition(c.selections == [12,11])
        precondition(c.keyboardShortcutSelectTab(at:1))
        c.isStopping = true
        drain()
        precondition(c.selections == [12,11], "Quit cancels queued shortcut work")
    }
    do {
        let c = TabGroupController()
        let g = TabGroup([.init(id:11,pid:1),.init(id:12,pid:1),.init(id:13,pid:1)])
        c.groups = [g]
        var nested = false
        c.duringSelection = {
            precondition(!nested, "AX pumping cannot start a reentrant shortcut switch")
            nested = true
            c.duringSelection = nil
            precondition(c.keyboardShortcutCycleTab(forward:true))
            drain() // Simulated AX call that pumps the main run loop.
            precondition(c.selections == [12])
            nested = false
        }
        precondition(c.keyboardShortcutCycleTab(forward:true))
        drain(); drain()
        precondition(c.selections == [12,13])
    }
    // Stop and reload discard queued old IDs rather than invoking new bindings.
    let oldHandler = os.handler!, oldID = os.keys[.init(keyCode:18,modifiers:UInt32(optionKey))]!
    monitor.stop(); monitor.stop()
    oldHandler(oldID)
    precondition(os.keys.isEmpty && controller.selections==before)
    monitor.apply(settings:.default)
    oldHandler(oldID)
    precondition(controller.selections==before && os.keys.count==11)
    // A system conflict is never passed to registration. Other conflicts stay unbound.
    os.reserved = [.init(keyCode:18,modifiers:UInt32(optionKey))]
    os.fail = [.init(keyCode:19,modifiers:UInt32(optionKey))]
    monitor.apply(settings:.default)
    precondition(os.keys.count==9 && messages.count==2)
    precondition(os.keys[.init(keyCode:18,modifiers:UInt32(optionKey))]==nil)
    precondition(os.keys[.init(keyCode:19,modifiers:UInt32(optionKey))]==nil)
    let selections = controller.selections
    os.press(18); os.press(19)
    precondition(controller.selections==selections)
    // Disabling removes all registrations; reconfiguration changes exact modifiers.
    var settings = ShortcutSettings.default
    settings.enabled = false
    monitor.apply(settings:settings)
    precondition(os.keys.isEmpty && os.handler==nil && messages.isEmpty)
    settings.enabled = true
    settings.selectByNumber = false
    settings.modifiers = [.maskCommand,.maskControl,.maskShift,.maskSecondaryFn]
    monitor.apply(settings:settings)
    precondition(os.keys.count==1) // Shift is already part of base, no duplicate reverse.
    let modifiers = UInt32(cmdKey|controlKey|shiftKey|kEventKeyModifierFnMask)
    precondition(os.keys[.init(keyCode:48,modifiers:modifiers)] != nil)
    os.press(48,modifiers); drain()
    precondition(controller.selections.count==selections.count+1)
    // Failed system conflict lookup reserves no keys; no unverified fallback.
    os.systemStatus = OSStatus(memFullErr)
    monitor.apply(settings:.default)
    precondition(os.keys.isEmpty && messages.count==1)
    os.systemStatus = noErr; os.installStatus = OSStatus(eventInternalErr)
    monitor.stop()
    precondition(!monitor.start() && os.keys.isEmpty && os.handler==nil)
    os.installStatus = noErr
    precondition(monitor.start())
    monitor.stop()
    print("PASS: registered hotkey lifecycle, modifier mapping, conflict refusal, reload/stale IDs, disabled/failure cleanup, real focused-window/Space dispatch, select/cycle/no-op outside groups; no OS hooks or input")
}
