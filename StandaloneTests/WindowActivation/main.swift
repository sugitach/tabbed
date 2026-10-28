import Foundation
import CoreGraphics

@MainActor func run() {
    var checks = 0
    func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message); checks += 1
    }
    func fixture() -> (TabGroupController, TabGroup) {
        let c = TabGroupController()
        let g = TabGroup([ManagedWindow(1, 100), ManagedWindow(2, 100), ManagedWindow(3, 200)])
        c.groups = [g]
        NSWorkspace.shared.frontmostApplication = Application(100)
        c.engine.focused[100] = 2
        c.engine.main[100] = 2
        return (c, g)
    }
    do {
        let (c, g) = fixture()
        c.activeMoveGroup = g
        c.syncPanelZOrderWithFrontmostGroup()
        check(g.activeWindow?.id == 2, "same-app parked member selected")
        check(c.selections == [2], "selection entry point used")
        check(c.selectedFrames == [g.contentFrame], "group frame preserved")
        check(c.trackingEnds == 1, "stale move tracking stopped")
        check(c.panelPositions == 1, "panel positioned for new selection")
        c.syncPanelZOrderWithFrontmostGroup()
        check(c.selections == [2], "self-generated focus is idempotent")
        NSWorkspace.shared.frontmostApplication = Application(200)
        c.engine.focused[200] = 3
        c.engine.main[200] = 3
        c.syncPanelZOrderWithFrontmostGroup()
        check(g.activeWindow?.id == 3, "cross-app member selected")
    }
    for scenario in 0..<9 {
        let (c, g) = fixture()
        switch scenario {
        case 0: c.isStopping = true
        case 1: c.isApplyingLayout = true
        case 2: c.draggedWindow = g.windows[0]
        case 3: g.moveAnchorFrame = g.contentFrame
        case 4: g.onActiveSpace = false
        case 5: NSWorkspace.shared.frontmostApplication = Application(c.ownPID); c.engine.focused[c.ownPID] = 2
        case 6: c.engine.focused[100] = 44 // ungrouped window
        case 7: NSWorkspace.shared.frontmostApplication = nil
        default: c.engine.focused[100] = nil
        }
        c.syncPanelZOrderWithFrontmostGroup()
        check(c.selections.isEmpty && g.activeIndex == 0, "ignored unsafe/unrelated focus scenario \(scenario)")
    }
    do {
        let (c, g) = fixture()
        // An old notification must use current focus, not its original target.
        c.engine.focused[100] = 1
        c.syncPanelZOrderWithFrontmostGroup()
        check(c.selections.isEmpty, "current focus wins over stale notification")
        // A background app reporting the same ID cannot select a member.
        NSWorkspace.shared.frontmostApplication = Application(300)
        c.engine.focused[300] = 2
        c.syncPanelZOrderWithFrontmostGroup()
        check(c.selections.isEmpty, "PID must match the grouped member")
        NSWorkspace.shared.frontmostApplication = Application(100)
        c.engine.focused[100] = 2
        c.duringSelection = {
            c.engine.focused[100] = 1
            c.selectExternallyFocusedWindow()
            c.engine.focused[100] = 2
        }
        c.syncPanelZOrderWithFrontmostGroup()
        check(c.selections == [2] && g.activeIndex == 1, "reentrant layout focus does not loop")
    }
    do {
        let (c, g) = fixture()
        c.engine.focused[100] = 1 // Chrome's focused attribute still points at the old tab.
        c.engine.main[100] = 2
        c.syncPanelZOrderWithFrontmostGroup(preferMainWindowForPID: 100)
        check(g.activeWindow?.id == 2 && c.selections == [2], "notification main change overrides stale focused attribute")
        check(c.panelPositions == 1 && c.frontmostGroup(preferMainWindowForPID: 100) === g,
              "selection and immediate panel lookup resolve the same main window")
        c.engine.main[100] = 44
        c.syncPanelZOrderWithFrontmostGroup(preferMainWindowForPID: 100)
        check(c.selections == [2], "ungrouped main window is never adopted")
        c.engine.main[100] = nil
        c.syncPanelZOrderWithFrontmostGroup(preferMainWindowForPID: 100)
        check(c.selections == [2], "unknown main window does not fall back to stale focus")
        c.engine.main[100] = 1
        NSWorkspace.shared.frontmostApplication = Application(200)
        c.engine.focused[200] = 3
        c.engine.main[200] = 3
        c.syncPanelZOrderWithFrontmostGroup(preferMainWindowForPID: 100)
        check(g.activeWindow?.id == 3, "background main hint cannot override current frontmost app")
        NSWorkspace.shared.frontmostApplication = Application(100)
        g.focusSettlementUntil = 0
        c.engine.main[100] = 2 // Event originally concerned 1, but main changed again.
        c.syncPanelZOrderWithFrontmostGroup(preferMainWindowForPID: 100)
        check(g.activeWindow?.id == 2, "latest main query wins over old notification")
    }
    do {
        let (c, g) = fixture()
        c.engine.focused[100] = 1
        c.engine.main[100] = 2
        c.syncPanelZOrderWithFrontmostGroupSoon(preferMainWindowForPID: 100)
        c.syncPanelZOrderWithFrontmostGroupSoon() // Subsequent focused/app event coalesces.
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        check(g.activeWindow?.id == 2 && c.selections == [2], "coalesced focus events retain main intent through final retry")
        check(c.frontmostGroup() === g, "shared shortcut/group lookup retains bounded main preference")
        c.engine.main[100] = 44
        check(c.frontmostGroup() == nil, "unrelated main cannot dispatch to stale focused group")
        c.engine.main[100] = nil
        c.engine.focused[100] = 44
        check(c.frontmostGroup() == nil, "missing main cannot dispatch from an ungrouped focused window")
        c.engine.focused[100] = 2
        check(c.frontmostGroup() === g, "missing main falls back to the live focused member")
        c.mainWindowPreferenceDeadline = .distantPast
        c.engine.focused[100] = 2
        check(c.frontmostGroup() === g, "expired preference resumes ordinary focused-window lookup")
    }
    do {
        let (c, oldGroup) = fixture()
        let targetGroup = TabGroup([ManagedWindow(4, 100), ManagedWindow(5, 100)])
        c.groups.append(targetGroup)
        c.engine.focused[100] = 1
        c.engine.main[100] = 5
        c.preferredMainWindowPID = 100
        c.mainWindowPreferenceDeadline = Date().addingTimeInterval(1)
        c.syncPanelZOrderWithFrontmostGroup()
        check(targetGroup.activeWindow?.id == 5 && oldGroup.activeWindow?.id == 1,
              "main change selects target group without altering stale-focus group")
        check(c.frontmostGroup() === targetGroup, "two-group lookup never targets stale focused group")
        NSWorkspace.shared.frontmostApplication = Application(200)
        c.engine.focused[200] = 3
        c.engine.main[200] = 3
        c.syncPanelZOrderWithFrontmostGroup()
        check(c.frontmostGroup() === oldGroup, "main preference remains bound to its original PID")
    }
    do {
        let (c, g) = fixture()
        let other = TabGroup([ManagedWindow(44, 100), ManagedWindow(45, 100)])
        c.groups.append(other)
        c.engine.focused[100] = 44
        c.engine.main[100] = 2
        c.applicationFocusDidChange(pid: 100, mainWindowChanged: true)
        check(c.selections == [2] && g.activeWindow?.id == 2,
              "main transition is handled synchronously before queued bounce")
        c.engine.main[100] = 44
        c.applicationFocusDidChange(pid: 100, mainWindowChanged: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        check(c.selections == [2] && other.activeWindow?.id == 44,
              "bounce to another group's already active window cannot lose revealed target")
    }
    do {
        let (c, g) = fixture()
        c.engine.focused[100] = 44
        c.engine.main[100] = 44
        c.applicationFocusDidChange(pid: 100, mainWindowChanged: true)
        check(c.selections.isEmpty && g.activeIndex == 0,
              "already stale main transition never replays a notification target")
        c.engine.main[100] = 2
        c.applicationFocusDidChange(pid: 100, mainWindowChanged: false)
        check(c.selections.isEmpty, "ordinary focus observation remains deferred")
        c.isStopping = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        check(c.selections.isEmpty, "shutdown cancels pending application focus work")
    }
    for scenario in 0..<5 {
        let (c, g) = fixture()
        c.engine.main[100] = 2
        switch scenario {
        case 0: c.isApplyingLayout = true
        case 1: c.draggedWindow = g.windows[0]
        case 2: g.moveAnchorFrame = g.contentFrame
        case 3: g.onActiveSpace = false
        default: NSWorkspace.shared.frontmostApplication = Application(200)
        }
        c.applicationFocusDidChange(pid: 100, mainWindowChanged: true)
        check(c.selections.isEmpty, "immediate focus respects existing safety guard \(scenario)")
        c.isStopping = true
    }
    do {
        let (c, g) = fixture()
        let other = TabGroup([ManagedWindow(44, 100), ManagedWindow(45, 100)])
        c.groups.append(other)
        // Captured Chrome sequence: the callback concerns 2, but both live AX
        // attributes already point back to the other group's active window 44.
        c.engine.focused[100] = 44
        c.engine.main[100] = 44
        c.activeMoveGroup = g
        c.applicationFocusDidChange(pid: 100, mainWindowChanged: true,
                                    element: axElement("window-100-2"))
        check(c.selections == [2] && g.activeWindow?.id == 2,
              "exact main transition survives already-stale live attributes")
        check(c.selectedFrames == [g.contentFrame] && c.trackingEnds == 1,
              "notification selection preserves geometry and ends stale tracking")
        c.applicationFocusDidChange(pid: 100, mainWindowChanged: true,
                                    element: other.windows[0].element)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        check(c.selections == [2] && other.activeWindow?.id == 44,
              "bounce to already-active other group and settled checks do not undo selection")
        g.focusSettlementUntil = 0 // The subsequent activation is after settlement.
        c.engine.main[100] = 1
        c.syncPanelZOrderWithFrontmostGroup()
        check(c.selections == [2, 1], "later live state is honored without replaying the event target")
    }
    for scenario in 0..<13 {
        let (c, g) = fixture()
        c.engine.focused[100] = 44
        c.engine.main[100] = 44
        var element = g.windows[1].element
        var pid: Int32 = 100
        switch scenario {
        case 0: c.isStopping = true
        case 1: c.isApplyingLayout = true
        case 2: c.draggedWindow = g.windows[0]
        case 3: g.moveAnchorFrame = g.contentFrame
        case 4: g.onActiveSpace = false
        case 5: NSWorkspace.shared.frontmostApplication = Application(200)
        case 6: c.engine.deadIDs.insert(2)
        case 7: c.groups = []
        case 8: element = axElement("unrelated-element")
        case 9: pid = 200; NSWorkspace.shared.frontmostApplication = Application(200)
        case 10: element = g.windows[0].element
        case 11: NSWorkspace.shared.frontmostApplication = nil
        default: pid = c.ownPID; NSWorkspace.shared.frontmostApplication = Application(pid)
        }
        c.applicationFocusDidChange(pid: pid, mainWindowChanged: true, element: element)
        check(c.selections.isEmpty, "main notification identity/liveness/safety guard \(scenario)")
        c.isStopping = true
    }
    do {
        let (c, g) = fixture()
        c.engine.focused[100] = 44
        c.engine.main[100] = 44
        c.applicationFocusDidChange(pid: 100, mainWindowChanged: false, element: g.windows[1].element)
        check(c.selections.isEmpty, "ordinary focus element cannot trigger synchronous selection")
        c.isStopping = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        check(c.selections.isEmpty, "ordinary event target is never retained or replayed")
    }
    do {
        let (c, g) = fixture()
        c.engine.focused[100] = 44
        c.engine.main[100] = 44
        c.duringSelection = {
            c.applicationFocusDidChange(pid: 100, mainWindowChanged: true, element: g.windows[0].element)
        }
        c.applicationFocusDidChange(pid: 100, mainWindowChanged: true, element: g.windows[1].element)
        check(c.selections == [2], "layout-generated main transitions cannot recursively change selection")
        c.isStopping = true
    }
    do {
        let (c, g) = fixture()
        c.engine.focused[100] = 1
        c.engine.main[100] = 1
        c.selectTab(2, in: g)
        // Recorded sequence: +0.18s focus event says 2, but live AX still says 1.
        c.applicationFocusDidChange(pid: 100, mainWindowChanged: false, element: g.windows[1].element)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        check(c.selections == [2] && g.activeWindow?.id == 2,
              "delayed stale live AX cannot undo explicit selection")
        // A queued main echo can disagree with the latest explicit choice too.
        c.selectTab(1, in: g)
        c.applicationFocusDidChange(pid: 100, mainWindowChanged: true, element: g.windows[1].element)
        check(c.selections == [2, 1] && g.activeWindow?.id == 1,
              "queued main echo cannot override a second explicit tab selection")
        c.engine.main[100] = 1
        c.engine.focused[100] = 1
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        check(c.selections == [2, 1], "settled checks do not sustain a feedback loop")
        c.applicationFocusDidChange(pid: 100, mainWindowChanged: true, element: g.windows[1].element)
        check(c.selections == [2, 1, 2], "external main notification works after settlement even with stale AX")
        c.isStopping = true
    }
    do {
        let (c, g) = fixture()
        c.engine.focused[100] = 1
        c.engine.main[100] = 1
        c.selectTab(2, in: g)
        // A genuine external activation during settlement is reconciled from
        // live state by the final check, rather than replaying the event target.
        c.applicationFocusDidChange(pid: 100, mainWindowChanged: true, element: g.windows[0].element)
        check(c.selections == [2], "same-app external activation waits for native settlement")
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        check(c.selections == [2, 1], "genuine external activation during settlement is eventually honored")
        c.isStopping = true
    }
    do {
        let (c, g) = fixture()
        c.engine.focused[100] = 1
        c.engine.main[100] = 1
        c.selectTab(2, in: g)
        c.applicationFocusDidChange(pid: 100, mainWindowChanged: false, element: g.windows[1].element)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            c.engine.main[100] = 2
            // Focus can remain stale longer than main (existing Calendar case).
            c.applicationFocusDidChange(pid: 100, mainWindowChanged: true, element: g.windows[1].element)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(1.9))
        check(c.selections == [2], "recorded stale-query then delayed main sequence never reverses selection")
        c.isStopping = true
    }
    do {
        let (c, g) = fixture()
        c.engine.focused[100] = 1
        c.engine.main[100] = 1
        c.selectTab(2, in: g)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            c.engine.main[100] = 2 // AX settled; main notification is absent.
        }
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        check(c.selections == [2], "final settlement check uses main even without a main-window notification")
        c.isStopping = true
    }
    do {
        let (c, g) = fixture()
        g.windows.removeLast() // Both members are Chrome windows.
        c.engine.focused[100] = 1
        c.engine.main[100] = 1
        for _ in 0..<101 { check(c.keyboardShortcutCycleTab(forward: true), "burst key accepted") }
        check(c.selections.isEmpty, "queued burst performs no synchronous native switches")
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        check(c.selections == [2], "101 queued keys commit one real selection")
        // Both AX attributes still point to the previous member. The next
        // burst must retain this group's shortcut ownership during settlement.
        for _ in 0..<101 { check(c.keyboardShortcutCycleTab(forward: true), "next burst key accepted with stale AX") }
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        check(c.selections == [2, 1], "next burst commits its final intent despite stale live AX")
        c.isStopping = true
    }
    print("PASS: \(checks) external-focus checks (real production methods; simulated AX/UI boundaries)")
}
MainActor.assumeIsolated { run() }
