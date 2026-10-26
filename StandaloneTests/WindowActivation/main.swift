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
        c.syncPanelZOrderWithFrontmostGroup(preferMainWindowForPID: 100)
        check(g.activeWindow?.id == 3, "background main hint cannot override current frontmost app")
        NSWorkspace.shared.frontmostApplication = Application(100)
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
        check(c.frontmostGroup() == nil, "missing main cannot dispatch to stale focused group")
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
        c.syncPanelZOrderWithFrontmostGroup()
        check(c.frontmostGroup() === oldGroup, "main preference remains bound to its original PID")
    }
    print("PASS: \(checks) external-focus checks (real production methods; simulated AX/UI boundaries)")
}
MainActor.assumeIsolated { run() }
