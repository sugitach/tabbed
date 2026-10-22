import Foundation
import CoreGraphics

enum RegressionFailure: Error { case check(String) }
func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw RegressionFailure.check(message) }
}
@MainActor func setup(_ sizes: [Int] = [3]) -> (TabGroupController, [ManagedWindow]) {
    Trace.events = []; NSRunningApplication.terminated = [:]
    NSScreen.screens = [NSScreen(visibleFrame: CGRect(x: 0, y: 24, width: 1000, height: 700))]
    let c = TabGroupController()
    c.dragMonitor.delegate = c; c.keyboardMonitor.delegate = c
    var windows: [ManagedWindow] = []
    for (i, size) in sizes.enumerated() {
        let new = (0..<size).map { ManagedWindow(UInt32(windows.count + $0 + 1)) }
        let frame = CGRect(x: 40 + i * 100, y: 100, width: 400, height: 300)
        c.groups.append(TabGroup(new, frame)); windows += new
        for (offset, w) in new.enumerated() {
            c.engine.frames[w.id] = offset == 0 ? frame : CGRect(x: 999, y: -299, width: 400, height: 300)
        }
    }
    c.mostRecentGroup = c.groups.last
    return (c, windows)
}
@MainActor func transientAXErrorMustKeepRestorationTarget() throws {
    let (c, w) = setup()
    let destination = c.groups[0].contentFrame
    w[1].element.errors = [.cannotComplete]
    c.pruneDeadWindows()
    try check(c.groups.flatMap(\.windows).map(\.id) == [1, 2, 3], "Transient AX error dropped the parked window")
    try check(c.observer.unobserved.isEmpty, "Unknown liveness must keep observation")
    try check(requestNormalQuit(c) == .terminateNow, "Recovered AX query must allow restore")
    try check(c.engine.attempts == [1, 2, 3], "Quit must attempt every original window")
    try check(c.engine.frames[2] == destination, "Parked window must receive the group destination")
}
@MainActor func permissionAndOtherErrorsMustKeepTargets() throws {
    for error: SimulatedAXError in [.apiDisabled, .failure, .notImplemented] {
        let (c, w) = setup(); w[1].element.errors = [error]
        c.pruneDeadWindows()
        try check(c.groups[0].windows.count == 3, "AX error is not positive closure evidence")
    }
}
@MainActor func knownClosureClassification() throws {
    for error: SimulatedAXError in [.cannotComplete, .apiDisabled, .failure, .notImplemented] {
        let (c, w) = setup(); w[0].element.errors = [error]
        c.pruneDeadWindows()
        try check(c.groups.flatMap(\.windows).map(\.id) == [1, 2, 3], "Unknown AX error must retain the window")
    }
    for changed in [false, true] {
        let (c, w) = setup()
        if changed { w[0].element.resolved = 99 } else { w[0].element.errors = [.invalidUIElement] }
        c.pruneDeadWindows()
        try check(c.groups[0].windows.map(\.id) == [2, 3], "Confirmed identity loss must prune the window")
    }
    for terminated: Bool? in [true, nil] {
        let (c, w) = setup(); NSRunningApplication.terminated[w[0].pid] = terminated
        c.pruneDeadWindows()
        try check(c.groups[0].windows.map(\.id) == [2, 3], "Terminated or absent app must be pruned")
    }
}
@MainActor func closedWindowsPrunedAcrossGroups() throws {
    let (c, w) = setup([3, 3])
    w[0].element.errors = [.invalidUIElement]
    NSRunningApplication.terminated[w[3].pid] = nil
    c.pruneDeadWindows()
    try check(c.groups.flatMap(\.windows).map(\.id) == [2, 3, 5, 6], "Prune only confirmed closures across groups")
    try check(requestNormalQuit(c) == .terminateNow, "Survivors must restore")
    try check(c.engine.attempts == [2, 3, 5, 6], "Closed windows must not be restored")
}
@MainActor func quitAttemptsAllGroupsAndRetriesFailure() throws {
    let (c, _) = setup([2, 3])
    c.engine.onRestore = { w, _ in w.id != 2 }
    let reply = requestNormalQuit(c)
    try check(reply == .terminateCancel, "Failure must be returned")
    try check(c.engine.attempts == [1, 2, 3, 4, 5], "One failure cannot stop later groups")
    try check(c.groups.count == 2 && c.isStopping, "Failed Quit must preserve targets while stopped")
    c.engine.onRestore = { _, _ in true }; c.engine.attempts = []
    try check(requestNormalQuit(c) == .terminateNow, "Retry must succeed after boundary recovers")
    try check(c.engine.attempts == [1, 2, 3, 4, 5], "Retry must recheck all surviving targets")
    try check(c.groups.isEmpty && c.mostRecentGroup == nil, "Successful Quit clears management")
    c.engine.attempts = []
    try check(requestNormalQuit(c) == .terminateNow && c.engine.attempts.isEmpty, "Repeated termination is idempotent")
}
@MainActor func unknownLivenessAndFailedRestoreMustReportFailure() throws {
    let (c, w) = setup()
    w[1].element.errors = [.cannotComplete, .cannotComplete]
    c.engine.onRestore = { w, _ in w.id != 2 }
    try check(requestNormalQuit(c) == .terminateCancel, "Unknown liveness must not hide a failed restoration")
    try check(c.groups.flatMap(\.windows).map(\.id) == [1, 2, 3], "Unknown failed window remains retryable")
}
@MainActor func closedDuringRestoreIsNotAFailure() throws {
    let (c, w) = setup()
    c.engine.onRestore = { window, _ in
        if window.id == 2 { NSRunningApplication.terminated[w[1].pid] = true; return false }
        return true
    }
    try check(requestNormalQuit(c) == .terminateNow, "A window actually closed during restore is not pending")
    try check(c.engine.attempts == [1, 2, 3], "Later windows must still be processed")
}
@MainActor func monitorsStopBeforeAnyRestore() throws {
    let (c, _) = setup()
    var safe = true
    c.engine.onRestore = { _, _ in
        safe = safe && c.isStopping && c.dragMonitor.delegate == nil && c.keyboardMonitor.delegate == nil &&
            c.observer.onEvent == nil && c.appFocusObserver.onEvent == nil && c.windowCreationObserver.onEvent == nil
        return true
    }
    _ = requestNormalQuit(c)
    try check(safe, "Input and observers must stop before restoration")
    let prefix = Array(Trace.events.prefix(8))
    try check(prefix == ["drag.stop", "key.stop", "tracking.stop", "drag.reset", "workspace.removeObserver",
        "window.unobserveAll", "focus.unobserveAll", "creation.unobserveAll"], "Shutdown call order changed")
}
@MainActor func stoppedCallbacksCannotDropOrRelayoutWindows() throws {
    let (c, w) = setup()
    c.engine.onRestore = { _, _ in false }
    _ = requestNormalQuit(c)
    Trace.events = []
    w[1].element.errors = [.invalidUIElement]
    c.handleWindowNotification(id: 2, notification: kAXUIElementDestroyedNotification)
    c.applicationDidActivate(Notification(name: Notification.Name("test")))
    c.activeSpaceChanged()
    c.pruneDeadWindows()
    try check(c.groups.flatMap(\.windows).map(\.id) == [1, 2, 3], "Stopped callbacks changed retained targets")
    try check(Trace.events.isEmpty, "Stopped callbacks scheduled layout or focus work")
    try check(w[1].element.errors.count == 1, "Stopped prune must not perform AX lookup")
}
@MainActor func explicitUntabKeepsExistingOffset() throws {
    let (c, w) = setup()
    let group = c.groups[0], base = group.contentFrame
    c.untab(2, from: group)
    try check(group.windows.map(\.id) == [1, 3], "Untab removes only selected member")
    try check(c.engine.frames[2] == base.offsetBy(dx: 32, dy: -32), "Untab must preserve its existing 32-point offset")
    try check(c.observer.unobserved == [2] && Trace.events.contains("activate.2"), "Untab unobserves and activates the selected window")
    try check(w[0].id == 1, "Fixture identities remain fixed")
}
@MainActor func oneRemainingWindowDissolvesSafely() throws {
    let (c, _) = setup([2])
    let group = c.groups[0], base = group.contentFrame
    c.remove(1, from: group, keepWindowObserved: false)
    try check(c.groups.isEmpty, "Single remaining window dissolves group")
    try check(c.engine.frames[2] == base && c.observer.unobserved == [1, 2], "Dissolve restores/unobserves the survivor")
}

@MainActor func everyGroupIsAttemptedDespiteFailure() throws {
    let (c, w) = setup([2, 3])
    NSRunningApplication.terminated[w[2].pid] = nil
    c.engine.onRestore = { window, _ in window.id != 2 }
    try check(requestNormalQuit(c) == .terminateCancel, "Failed restoration must cancel Quit")
    try check(c.engine.attempts == [1, 2, 4, 5], "One failure must not stop later groups")
}
@MainActor func windowClosedDuringQuitIsNotFailure() throws {
    let (c, w) = setup()
    c.engine.onRestore = { window, _ in
        if window.id == 2 { NSRunningApplication.terminated[w[1].pid] = true; return false }
        return true
    }
    try check(requestNormalQuit(c) == .terminateNow, "Closed window must not prevent Quit")
    try check(c.engine.attempts == [1, 2, 3], "Quit must attempt every still-live window")
}
@MainActor func missingScreensCancelQuitWithoutMoving() throws {
    let (c, _) = setup(); NSScreen.screens = []
    try check(requestNormalQuit(c) == .terminateCancel, "Missing screen must cancel Quit")
    try check(c.engine.attempts.isEmpty && c.groups.count == 1, "No destination must preserve pending targets")
}
@MainActor func oversizedOffscreenGroupRestoresInsideScreen() throws {
    let (c, _) = setup()
    c.groups[0].contentFrame = CGRect(x: 3000, y: -2000, width: 1800, height: 1200)
    try check(requestNormalQuit(c) == .terminateNow, "Clamped restoration should permit Quit")
    let screen = NSScreen.screens[0].visibleFrame
    try check([1, 2, 3].allSatisfy { c.engine.frames[UInt32($0)] == screen }, "Every window must receive the clamped visible frame")
}
@MainActor func invalidGroupFrameCancelsQuitWithoutWriting() throws {
    let (c, _) = setup(); c.groups[0].contentFrame = .null
    try check(requestNormalQuit(c) == .terminateCancel, "Invalid group frame must cancel Quit")
    try check(c.engine.attempts.isEmpty, "Invalid frame must not be written")
}
@MainActor func normalQuitRetryRechecksAllWindows() throws {
    let (c, _) = setup([2])
    c.engine.onRestore = { window, _ in window.id == 1 }
    try check(requestNormalQuit(c) == .terminateCancel, "Failure must keep application open")
    c.engine.onRestore = { _, _ in true }; c.engine.attempts = []
    try check(requestNormalQuit(c) == .terminateNow, "Recovered boundary should permit retry")
    try check(c.engine.attempts == [1, 2], "Retry must recheck both windows")
}
@MainActor func negativeCoordinateDisplayIsPreserved() throws {
    let (c, _) = setup()
    let left = CGRect(x: -1000, y: 24, width: 1000, height: 700)
    NSScreen.screens.append(NSScreen(visibleFrame: left))
    let frame = CGRect(x: -800, y: 100, width: 400, height: 300)
    c.groups[0].contentFrame = frame
    try check(requestNormalQuit(c) == .terminateNow, "Existing left display should permit Quit")
    try check([1, 2, 3].allSatisfy { c.engine.frames[UInt32($0)] == frame }, "Existing negative-coordinate display must be preserved")
}

MainActor.assumeIsolated {
    let cases: [(String, () throws -> Void)] = [
        ("Quit continues across groups after failure", everyGroupIsAttemptedDespiteFailure),
        ("window closed during normal Quit", windowClosedDuringQuitIsNotFailure),
        ("missing screen cancels normal Quit", missingScreensCancelQuitWithoutMoving),
        ("offscreen/oversized frame clamped on Quit", oversizedOffscreenGroupRestoresInsideScreen),
        ("invalid group frame cancels Quit", invalidGroupFrameCancelsQuitWithoutWriting),
        ("normal Quit retry checks every window", normalQuitRetryRechecksAllWindows),
        ("negative-coordinate display preserved", negativeCoordinateDisplayIsPreserved),
        ("transient AX error retains Quit target", transientAXErrorMustKeepRestorationTarget),
        ("permission/other AX errors retain targets", permissionAndOtherErrorsMustKeepTargets),
        ("known closure classification", knownClosureClassification),
        ("closed windows pruned across groups", closedWindowsPrunedAcrossGroups),
        ("Quit all groups / failure / retry / idempotence", quitAttemptsAllGroupsAndRetriesFailure),
        ("unknown liveness cannot hide failed restore", unknownLivenessAndFailedRestoreMustReportFailure),
        ("closed during restore", closedDuringRestoreIsNotAFailure),
        ("stop monitors before restoring", monitorsStopBeforeAnyRestore),
        ("stopped callbacks preserve targets", stoppedCallbacksCannotDropOrRelayoutWindows),
        ("explicit untab keeps offset", explicitUntabKeepsExistingOffset),
        ("single survivor dissolves", oneRemainingWindowDissolvesSafely),
    ]
    var failed = 0
    for (name, body) in cases {
        do { try body(); print("PASS: \(name)") }
        catch { failed += 1; print("FAIL: \(name): \(error)") }
    }
    print("INTERNAL_RESULT: \(cases.count - failed)/\(cases.count); simulated AX/UI boundaries, no OS events")
    if failed != 0 { exit(1) }
}
