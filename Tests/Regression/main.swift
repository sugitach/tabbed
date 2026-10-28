import Foundation
import CoreGraphics

enum RegressionFailure: Error { case check(String) }
func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw RegressionFailure.check(message) }
}
@MainActor func setup(_ sizes: [Int] = [3]) -> (TabGroupController, [ManagedWindow]) {
    Trace.events = []; NSRunningApplication.terminated = [:]
    AXUIElement.applications = [:]; NSEvent.pressedMouseButtons = 0
    DispatchQueue.main.pending = []
    NSAlert.presentations = []
    NSAlert.responses = []
    NSApplication.shared.presentationActions = []
    NSWorkspace.shared.shownApps = []
    NSWorkspace.shared.openedURLs = []
    AccessibilityPermission.trusted = false
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
    try check(c.engine.frames[2] == destination.offsetBy(dx: 32, dy: -32), "Parked window must receive the group destination")
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
    try check([1, 2, 3].allSatisfy { c.engine.frames[UInt32($0)] == frame.offsetBy(dx: CGFloat($0 - 1) * 32, dy: -CGFloat($0 - 1) * 32) }, "Existing negative-coordinate display must be preserved")
}

@MainActor func appLaunchDuringDisplayTransitionInstallsCreationObserver() throws {
    let (c, w) = setup()
    c.displayTransitionPending = true
    let app = NSRunningApplication(processIdentifier: w[0].pid)!
    let launch = Notification(name: Notification.Name("launch"),
        userInfo: [NSWorkspace.applicationUserInfoKey: app])
    c.applicationDidLaunch(launch)
    try check(c.windowCreationObserver.observedPIDs == [w[0].pid],
        "Display settlement must not lose the app launch observer registration")
    try check(c.engine.writes.isEmpty, "Observer registration does not move a window")
    c.autoAddNewWindowsToStack = false;c.applicationDidLaunch(launch)
    c.autoAddNewWindowsToStack = true;c.isStopping = true;c.applicationDidLaunch(launch)
    try check(c.windowCreationObserver.observedPIDs.count == 1,
        "Disabled auto-add and shutdown still prevent registration")
}

@MainActor func windowCreationDoesNotAdoptUnrelatedFocusedWindow() throws {
    let (c, _) = setup([2])
    let destination = ManagedWindow(90)
    let app = AXUIElementCreateApplication(destination.pid)
    app.attributes[kAXFocusedWindowAttribute] = destination.element
    app.attributes[kAXMainWindowAttribute] = destination.element
    c.engine.availableWindows = [destination]; c.engine.visibleWindows = [destination.id]
    let invalidNotification = AXUIElement(91); invalidNotification.standardWindow = false
    c.resolveAndAutoAddWindow(pid: destination.pid, element: invalidNotification, attemptsRemaining: 0)
    try check(c.addedWindows.isEmpty, "Unresolved creation must not enroll the unrelated focused/main Chrome window")
}

@MainActor func closedCreationDoesNotAdoptFocusedDestination() throws {
    let (c, _) = setup([2])
    let temporary = ManagedWindow(90), destination = ManagedWindow(91, pid: 190)
    let app = AXUIElementCreateApplication(temporary.pid)
    app.attributes[kAXFocusedWindowAttribute] = destination.element
    app.attributes[kAXMainWindowAttribute] = destination.element
    // The transient notification no longer resolves; a different window in the
    // same Chrome process is now focused and still visible.
    c.engine.availableWindows = [destination]; c.engine.visibleWindows = [destination.id]
    c.resolveAndAutoAddWindow(pid: temporary.pid, element: temporary.element, attemptsRemaining: 0)
    try check(c.addedWindows.isEmpty, "Destroyed transient must not be replaced by the focused destination")
}

@MainActor func directCreatedWindowStillAutoAdds() throws {
    let (c, _) = setup([2]); let created = ManagedWindow(90)
    c.engine.availableWindows = [created]; c.engine.visibleWindows = [created.id]
    c.resolveAndAutoAddWindow(pid: created.pid, element: created.element, attemptsRemaining: 0)
    try check(c.addedWindows == [90], "An ordinary visible created window must still auto-add")
}

@MainActor func notificationChildCannotEnrollItsContainingWindow() throws {
    let (c, _) = setup([2]); let created = ManagedWindow(90), unrelated = ManagedWindow(91, pid: 190)
    let child = AXUIElement(92); child.standardWindow = false
    child.attributes[kAXWindowAttribute] = created.element
    let app = AXUIElementCreateApplication(created.pid)
    app.attributes[kAXFocusedWindowAttribute] = unrelated.element
    c.engine.availableWindows = [created, unrelated]; c.engine.visibleWindows = [90, 91]
    c.resolveAndAutoAddWindow(pid: created.pid, element: child, attemptsRemaining: 0)
    try check(c.addedWindows.isEmpty, "Non-window notification cannot enroll a containing window that could change during tab reparenting")
}

@MainActor func creationDuringDragDoesNotAutoAdd() throws {
    let (c, _) = setup([2]); let transient = ManagedWindow(90)
    c.engine.availableWindows = [transient]; c.engine.visibleWindows = [transient.id]
    NSEvent.pressedMouseButtons = 1
    c.resolveAndAutoAddWindow(pid: transient.pid, element: transient.element, attemptsRemaining: 0)
    try check(c.addedWindows.isEmpty, "Auto-add must not take over a window during an app's own mouse drag")
}

@MainActor func releasedDragRechecksOriginalElement() throws {
    let (c, _) = setup([2]); let transient = ManagedWindow(90)
    c.engine.availableWindows = [transient]; c.engine.visibleWindows = [transient.id]
    NSEvent.pressedMouseButtons = 1
    c.handleWindowCreated(pid: transient.pid, element: transient.element)
    let premature = c.addedWindows
    NSEvent.pressedMouseButtons = 0
    c.engine.visibleWindows = []
    DispatchQueue.main.runNext()
    try check(premature.isEmpty && c.addedWindows.isEmpty, "Drag release must not auto-add a vanished/offscreen transient")
    c.engine.visibleWindows = [transient.id]
    DispatchQueue.main.runNext()
    try check(c.addedWindows == [90], "A surviving visible new window can auto-add after drag release")
}

@MainActor func dragRetriesAreBounded() throws {
    let (c, _) = setup([2]); let transient = ManagedWindow(90)
    c.engine.availableWindows = [transient]; c.engine.visibleWindows = [90]
    NSEvent.pressedMouseButtons = 1
    c.handleWindowCreated(pid: transient.pid, element: transient.element)
    for _ in 0..<3 {
        try check(DispatchQueue.main.pending.count == 1, "Only one bounded retry should be pending")
        DispatchQueue.main.runNext()
    }
    try check(DispatchQueue.main.pending.isEmpty && c.addedWindows.isEmpty, "Long drag must exhaust retries without taking over its window")
}

@MainActor func delayedCreationHonorsDisabledAutoAdd() throws {
    let (c, _) = setup([2]); let transient = ManagedWindow(90)
    c.engine.availableWindows = [transient]; c.engine.visibleWindows = [90]
    NSEvent.pressedMouseButtons = 1
    c.handleWindowCreated(pid: transient.pid, element: transient.element)
    c.autoAddNewWindowsToStack = false; NSEvent.pressedMouseButtons = 0
    DispatchQueue.main.runNext()
    try check(c.addedWindows.isEmpty && DispatchQueue.main.pending.isEmpty, "Disabling auto-add must cancel already queued adoption")
}

@MainActor func creationWaitsForDisplaySettlement() throws {
    let (c, _) = setup([2]); let created = ManagedWindow(90)
    c.engine.availableWindows = [created]; c.engine.visibleWindows = [90]
    c.displayTransitionPending = true
    c.resolveAndAutoAddWindow(pid: created.pid, element: created.element, attemptsRemaining: 0)
    for _ in 0..<8 {
        try check(c.addedWindows.isEmpty && DispatchQueue.main.pending.count == 1,
                  "Display settlement must postpone adoption without exhausting transient retries")
        DispatchQueue.main.runNext()
    }
    c.displayTransitionPending = false
    DispatchQueue.main.runNext()
    try check(c.addedWindows == [90] && DispatchQueue.main.pending.isEmpty,
              "Original created window must auto-add once after the display settles")
}

@MainActor func deferredCreationRevalidatesState() throws {
    for cancellation in 0..<4 {
        let (c, _) = setup([2]); let created = ManagedWindow(90)
        c.engine.availableWindows = [created]; c.engine.visibleWindows = [90]
        c.displayTransitionPending = true
        c.handleWindowCreated(pid: created.pid, element: created.element)
        if cancellation == 0 { c.autoAddNewWindowsToStack = false }
        if cancellation == 1 { c.isStopping = true }
        if cancellation == 2 { c.groups.removeAll() }
        if cancellation == 3 { c.engine.availableWindows = []; c.engine.visibleWindows = [] }
        c.displayTransitionPending = false
        while !DispatchQueue.main.pending.isEmpty { DispatchQueue.main.runNext() }
        try check(c.addedWindows.isEmpty, "Deferred adoption must revalidate setting, shutdown, group and window lifetime")
    }
}

@MainActor func autoAddOffAndShutdownIgnoreCreation() throws {
    for stopping in [false, true] {
        let (c, _) = setup([2]); let created = ManagedWindow(90)
        c.engine.availableWindows = [created]; c.engine.visibleWindows = [created.id]
        c.autoAddNewWindowsToStack = stopping; c.isStopping = stopping
        c.handleWindowCreated(pid: created.pid, element: created.element)
        try check(c.addedWindows.isEmpty, "Auto-add off or stopped must leave unrelated new windows alone")
    }
}

@MainActor func failedQuitExplainsThatManagementRemainsStopped() throws {
    let (c, _) = setup([2])
    c.engine.onRestore = { window, _ in window.id != 2 }
    try check(requestNormalQuit(c) == .terminateCancel, "Failed restoration must keep the application open")
    let alerts = NSAlert.presentations
    try check(alerts.count == 2, "Keep Open must be followed by an explicit stopped-state notice")
    try check(alerts[0].buttons == ["Keep Open", "Quit Without Restoring…"], "Keeping open must be the default, with an explicit escape path")
    try check(alerts[1].message == "Tabbed is still running" && alerts[1].information.contains("⌘-drag are stopped") && alerts[1].information.contains("Some windows may still need restoration") && alerts[1].information.contains("Quit Tabbed"), "Follow-up must explain running/stopped state, pending restoration, and how to exit")
    try check(c.isStopping && c.groups.count == 1 && c.engine.attempts == [1, 2], "Acknowledging the notice must not resume management, clear targets, or repeat restoration")
    c.engine.onRestore = { _, _ in true }; NSAlert.presentations = []
    try check(requestNormalQuit(c) == .terminateNow && NSAlert.presentations.isEmpty, "A later successful Quit must exit without another stopped-state notice")
}

@MainActor func successfulQuitDoesNotShowStoppedNotice() throws {
    let (c, _) = setup([2])
    NSAlert.responses = [.alertSecondButtonReturn, .alertSecondButtonReturn]
    try check(requestNormalQuit(c) == .terminateNow && NSAlert.presentations.isEmpty, "Successful restoration must quit without Keep Open or a misleading running notice")
    try check(NSAlert.responses.count == 2, "Successful restoration must not ask for a bypass decision")
}

@MainActor func confirmedQuitDoesNotRestoreAgainDuringTermination() throws {
    let (c, _) = setup([2]); let delegate = AppDelegate(controller: c)
    c.engine.onRestore = { _, _ in false }
    NSAlert.responses = [.alertSecondButtonReturn, .alertSecondButtonReturn]
    try check(requestNormalQuit(c, delegate: delegate) == .terminateNow, "An explicitly confirmed bypass must allow exit despite failed restoration")
    try check(NSAlert.presentations.count == 2, "Bypass must show a separate confirmation and no Keep Open notice")
    let confirmation = NSAlert.presentations[1]
    try check(confirmation.buttons == ["Cancel", "Quit Without Restoring"] && confirmation.information.contains("offscreen"), "Confirmation must default to Cancel and disclose unrecovered windows")
    try check(c.engine.attempts == [1, 2] && c.engine.writes.isEmpty, "The termination fallback must not retry writes after bypass confirmation")
    try check(c.isStopping && c.groups.count == 1 && c.dragMonitor.delegate == nil, "Explicit exit must not reactivate management or fake a successful restoration")
    NSAlert.presentations = []
    try check(requestNormalQuit(c, delegate: delegate) == .terminateNow && c.engine.attempts == [1, 2] && NSAlert.presentations.isEmpty, "Repeated termination callbacks after confirmation must not move windows or prompt again")
}

@MainActor func cancelledBypassKeepsRecoveryTargets() throws {
    let (c, _) = setup([2]); let delegate = AppDelegate(controller: c)
    c.engine.onRestore = { _, _ in false }
    NSAlert.responses = [.alertSecondButtonReturn, .alertFirstButtonReturn, .alertFirstButtonReturn]
    try check(requestNormalQuit(c, delegate: delegate) == .terminateCancel, "Cancelling bypass confirmation must keep the app open")
    try check(NSAlert.presentations.count == 3 && c.isStopping && c.groups.count == 1 && c.engine.attempts == [1, 2], "Cancel must retain targets, explain stopped state, and perform no extra restoration")
    c.engine.onRestore = { _, _ in true }; c.engine.attempts = []; NSAlert.presentations = []
    try check(requestNormalQuit(c, delegate: delegate) == .terminateNow && c.engine.attempts == [1, 2] && NSAlert.presentations.isEmpty, "A cancelled bypass must not disable later normal restoration")
}

@MainActor func abortedConfirmationCannotApproveBypass() throws {
    let (c, _) = setup([2]); c.engine.onRestore = { _, _ in false }
    NSAlert.responses = [.alertSecondButtonReturn, .abort, .alertFirstButtonReturn]
    try check(requestNormalQuit(c) == .terminateCancel && NSAlert.presentations.count == 3, "An unexpected confirmation response must never authorize bypass")
    try check(c.engine.attempts == [1, 2] && c.groups.count == 1, "Aborted confirmation must retain the recovery targets without retrying writes")
}

@MainActor func dismissedWarningCannotApproveBypass() throws {
    let (c, _) = setup([2]); c.engine.onRestore = { _, _ in false }
    NSAlert.responses = [.abort, .alertFirstButtonReturn]
    try check(requestNormalQuit(c) == .terminateCancel && NSAlert.presentations.count == 2, "Dismissing the initial warning must keep the app stopped and open")
    try check(c.engine.attempts == [1, 2] && c.groups.count == 1, "Dismissal must not discard restoration targets")
}

@MainActor func restorationWaitsForPublishedFrame() throws {
    let target = CGRect(x: 100, y: 200, width: 800, height: 600)
    var reads = 0, waits = 0
    let result = WindowRestoration.verify(frame: target, read: {
        reads += 1
        return reads < 4 ? CGRect(x: -1000, y: 200, width: 800, height: 600) : target
    }, wait: { waits += 1 })
    try check(result && waits == 3, "Delayed publication must settle without repeated writes")
    waits = 0
    try check(!WindowRestoration.verify(frame: target, read: { nil }, wait: { waits += 1 }) && waits == 10,
              "Unknown geometry must remain a bounded failure")
    try check(!WindowRestoration.verify(frame: target, read: { CGRect(x: 100, y: 200, width: 900, height: 600) }, wait: {}),
              "A real size mismatch cannot be hidden")
}

@MainActor func grantedPermissionClosesGuidance() throws {
    let (c, _) = setup([2]); let app = AppDelegate(controller: c)
    let alert = AccessibilityHelpPanel(information: "Fixture guidance", onResponse: { _ in }); app.accessibilityHelpPanel = alert
    AccessibilityPermission.trusted = true
    c.dragMonitor.startResult = false
    let now = Date()
    app.refreshStartup(now: now)
    try check(app.accessibilityHelpPanel != nil && !alert.window.hidden && !app.monitoringActive,
              "Guidance must stay visible until monitoring and icon become active")
    c.dragMonitor.startResult = true
    app.refreshStartup(now: now.addingTimeInterval(6))
    try check(app.accessibilityHelpPanel == nil && alert.window.hidden && app.monitoringActive,
              "Active monitoring must dismiss our guidance")
}

@MainActor func normalQuitCascadesGroupWindows() throws {
    let (c, windows) = setup([3, 2])
    let bases = c.groups.map(\.contentFrame)
    try check(requestNormalQuit(c) == .terminateNow, "Grouped Quit should restore successfully")
    for (groupIndex, members) in [Array(windows[0..<3]), Array(windows[3..<5])].enumerated() {
        for (index, window) in members.enumerated() {
            let expected = bases[groupIndex].offsetBy(dx: CGFloat(index) * 32, dy: -CGFloat(index) * 32)
            let clamped = WindowRestoration.destination(for: expected, screens: NSScreen.screens.map(\.visibleFrame))
            try check(c.engine.frames[window.id] == clamped, "Quit must cascade each group in 32-point steps")
        }
    }
}

@MainActor func permissionGrantStartsWithoutRelaunch() throws {
    let (c, _) = setup([]); let app = AppDelegate(controller: c)
    let now = Date(timeIntervalSince1970: 100)
    app.permissionTimer = Timer(timeInterval: 1, repeats: true) { _ in }
    let timer = app.permissionTimer!
    app.refreshStartup(now: now)
    try check(c.dragMonitor.startCalls == 0 && !app.monitoringActive, "Denied access must not attempt monitoring")
    AccessibilityPermission.trusted = true
    app.refreshStartup(now: now.addingTimeInterval(1))
    try check(app.monitoringStarted && app.monitoringActive && c.isStarted, "A new grant must start the same process")
    try check(app.permissionTimer == nil && !timer.isValid, "Success must stop permission polling")
    app.refreshStartup(now: now.addingTimeInterval(2))
    try check(c.dragMonitor.startCalls == 1 && c.startupObservers.count == 3, "Repeated checks must not duplicate taps or observers")
}

@MainActor func tapFailureDoesNotClaimReadyAndCanRecover() throws {
    let (c, _) = setup([]); let app = AppDelegate(controller: c)
    let now = Date(timeIntervalSince1970: 100)
    AccessibilityPermission.trusted = true
    c.keyboardMonitor.startResult = false
    app.permissionTimer = Timer(timeInterval: 1, repeats: true) { _ in }
    app.refreshStartup(now: now)
    try check(!app.monitoringStarted && !app.monitoringActive && !c.isStarted, "Trust alone must not claim working input monitoring")
    try check(c.startupObservers.isEmpty && Trace.events == ["drag.stop", "key.stop"], "Failure must roll back both taps before observer setup")
    try check(app.permissionTimer != nil && app.monitoringStatus.contains("retrying"), "Failure must keep polling and show retry status")
    c.keyboardMonitor.startResult = true
    app.refreshStartup(now: now.addingTimeInterval(1))
    try check(c.dragMonitor.startCalls == 1, "Retry must be throttled")
    app.refreshStartup(now: now.addingTimeInterval(5))
    try check(app.monitoringActive && c.dragMonitor.startCalls == 2 && c.startupObservers.count == 3, "Transient tap failure must recover without relaunch")
}

@MainActor func deniedPermissionKeepsWaiting() throws {
    let (c, _) = setup([]); let app = AppDelegate(controller: c)
    for tick in 0..<10 { app.refreshStartup(now: Date(timeIntervalSince1970: Double(tick))) }
    try check(c.dragMonitor.startCalls == 0 && !app.monitoringStarted && app.monitoringStatus.contains("Waiting"), "A stale/ungranted entry must never start or claim readiness")
}

@MainActor func firstTapFailurePreventsPartialStartup() throws {
    let (c, _) = setup([]); c.dragMonitor.startResult = false
    try check(!c.startForTest(), "Drag tap failure must be returned")
    try check(c.keyboardMonitor.startCalls == 0 && c.startupObservers.isEmpty && Trace.events == ["drag.stop", "key.stop"], "First failure must stop both taps without registering observers")
}

@MainActor func controllerStartupIsIdempotent() throws {
    let (c, _) = setup([]); c.autoAddNewWindowsToStack = false
    try check(c.startForTest() && c.startForTest(), "A started controller must report ready")
    try check(c.dragMonitor.startCalls == 1 && c.keyboardMonitor.startCalls == 1 && c.startupObservers == ["space", "application"], "Repeated start must not duplicate monitoring or enable disabled auto-add")
}

@MainActor func quittingWhileWaitingCancelsPolling() throws {
    let (c, _) = setup([]); let app = AppDelegate(controller: c)
    app.permissionTimer = Timer(timeInterval: 1, repeats: true) { _ in }
    let timer = app.permissionTimer!
    try check(requestNormalQuit(c, delegate: app) == .terminateNow, "Waiting app must still quit normally")
    AccessibilityPermission.trusted = true
    app.refreshStartup(now: Date())
    try check(app.permissionTimer == nil && !timer.isValid && c.dragMonitor.startCalls == 0, "Queued check after Quit must not start monitoring")
}

@MainActor func cancelledQuitCannotResumePermissionStartup() throws {
    let (c, _) = setup([2]); let app = AppDelegate(controller: c)
    app.permissionTimer = Timer(timeInterval: 1, repeats: true) { _ in }
    c.engine.onRestore = { _, _ in false }
    try check(requestNormalQuit(c, delegate: app) == .terminateCancel, "Failed restoration must stay open")
    AccessibilityPermission.trusted = true
    app.refreshStartup(now: Date())
    try check(app.permissionTimer == nil && !app.monitoringActive && c.dragMonitor.startCalls == 0 && !c.startForTest(), "Keep Open and late grants must not restart the stopped controller")
}

@MainActor func adHocGuidanceDoesNotClaimAnOldEntryIsProven() throws {
#if HAS_PERMISSION_HELP
    let message = AppCodeSignature(isAdHoc: true, validationSucceeded: true)
        .accessibilityRecoveryMessage(appPath: "/Fixture/Tabbed Dev.app")
    try check(message.contains("local ad-hoc signature") && message.contains("can still refer") && message.contains("cannot confirm"), "Signature diagnosis must distinguish an update possibility from a proven TCC entry")
    try check(message.contains("already ON") && message.contains("press −") && message.contains("press +") && message.contains("Remove only Tabbed") && message.contains("/Fixture/Tabbed Dev.app"), "Recovery must identify the current app and conditionally explain removing/re-adding only Tabbed")
#else
    try check(false, "Production permission guidance is missing")
#endif
}

@MainActor func unknownSignatureDoesNotInventASigningCause() throws {
#if HAS_PERMISSION_HELP
    for adHoc: Bool? in [nil, true, false] {
        let message = AppCodeSignature(isAdHoc: adHoc, validationSucceeded: false)
            .accessibilityRecoveryMessage(appPath: "/Fixture.app")
        try check(message.contains("could not verify") && !message.contains("This build uses a local ad-hoc signature"), "Failed inspection must remain unknown even if metadata suggests ad-hoc signing")
    }
    let message = AppCodeSignature(isAdHoc: false, validationSucceeded: true)
        .accessibilityRecoveryMessage(appPath: "/Fixture.app")
    try check(!message.contains("ad-hoc") && message.contains("already ON"), "Other valid signatures still need generic recovery guidance without an ad-hoc claim")
#else
    try check(false, "Production signature diagnosis is missing")
#endif
}

@MainActor func guidanceOpensSettingsOnlyOnExplicitChoice() throws {
    let (c, _) = setup([]); let app = AppDelegate(controller: c)
    NSAlert.responses = [.alertFirstButtonReturn]
    app.presentPermissionHelp()
    try check(NSAlert.presentations.count == 1 && app.settingsRequests == 1 && NSWorkspace.shared.shownApps.isEmpty, "Only the Settings choice may open/request permission")
    try check(NSWorkspace.shared.openedURLs.isEmpty,
              "Requesting the OS prompt must not independently open Settings and bypass its response")
    let alert = NSAlert.presentations[0]
    try check(alert.buttons == ["Open Accessibility Settings…", "Show Current App in Finder", "Not Now"] && alert.information.contains(app.appBundleURL.path), "Guidance must provide the exact current bundle and explicit actions")
    try check(c.dragMonitor.startCalls == 0 && app.accessibilityHelpPanel != nil,
              "Opening Settings must keep guidance visible without granting permission")
}

@MainActor func guidanceActivatesOnceWithoutStealingFocusDuringPolling() throws {
    let (c, _) = setup([]); let app = AppDelegate(controller: c)
    app.presentPermissionHelp()
    try check(NSApplication.shared.presentationActions == ["activate", "key", "front"],
              "Initial guidance must activate the accessory app before fronting its panel")
    let panel = app.accessibilityHelpPanel
    for tick in 0..<4 { app.refreshStartup(now: Date(timeIntervalSince1970: Double(tick))) }
    try check(NSApplication.shared.presentationActions.count == 3,
              "Permission polling must not repeatedly steal focus from Settings")
    app.presentPermissionHelp()
    try check(app.accessibilityHelpPanel === panel && NSApplication.shared.presentationActions == ["activate", "key", "front", "activate", "key", "front"],
              "An explicit Help request must bring the existing panel to the front")
}

@MainActor func guidanceCanRevealTheCurrentApp() throws {
    let (c, _) = setup([]); let app = AppDelegate(controller: c)
    NSAlert.responses = [.alertSecondButtonReturn]
    app.presentPermissionHelp()
    try check(app.accessibilityHelpPanel != nil && NSWorkspace.shared.shownApps == [app.appBundleURL] && app.settingsRequests == 0, "Finder must reveal only the current app without requesting access")
}

@MainActor func dismissingGuidanceKeepsWaitingWithoutActions() throws {
    for response: NSApplication.ModalResponse in [.alertThirdButtonReturn, .abort] {
        let (c, _) = setup([]); let app = AppDelegate(controller: c)
        app.permissionTimer = Timer(timeInterval: 1, repeats: true) { _ in }
        NSAlert.responses = [response]
        app.presentPermissionHelp()
        for tick in 0..<3 { app.refreshStartup(now: Date(timeIntervalSince1970: Double(tick))) }
        try check(NSAlert.presentations.count == 1 && app.settingsRequests == 0 && NSWorkspace.shared.shownApps.isEmpty, "Dismissal and polling must not open settings, reveal files or repeat the modal")
        try check(app.accessibilityHelpPanel == nil && app.permissionTimer?.isValid == true && c.dragMonitor.startCalls == 0, "Dismissing help must preserve safe permission polling")
    }
}

@MainActor func grantedOrStoppedAppDoesNotShowStalePermissionGuidance() throws {
    let (c, _) = setup([]); let app = AppDelegate(controller: c)
    AccessibilityPermission.trusted = true
    app.presentPermissionHelp()
    try check(NSAlert.presentations.isEmpty && app.monitoringActive, "An already granted process must recheck startup rather than warn about stale entries")
    let (stopped, _) = setup([]); let stoppedApp = AppDelegate(controller: stopped)
    stopped.isStopping = true
    stoppedApp.presentPermissionHelp()
    try check(NSAlert.presentations.isEmpty && stoppedApp.settingsRequests == 0 && stopped.dragMonitor.startCalls == 0, "Stopped management must not prompt or resume via Help")
}

@MainActor func diagnosticRecorderIsExplicitAndPrivate() throws {
#if HAS_WINDOW_DIAGNOSTICS
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("tabbed-diag-test-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = WindowDiagnosticRecorder(directory: root)
    recorder.write(.init(event: .selection, windowID: 1))
    try check(!FileManager.default.fileExists(atPath: root.path), "Disabled recording must not create a directory or log")
    try recorder.start()
    recorder.write(.init(event: .frameResult, windowID: 8, pid: 123,
        requestedFrame: [10, 20, 640, 480], sizeStatus: -25204, positionStatus: 0))
    recorder.stop()
    let url = root.appendingPathComponent("window-events.jsonl")
    let records = try String(contentsOf: url).split(separator: "\n").map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
    try check(records.count == 3 && records.map { $0["sequence"] as! Int } == [1, 2, 3], "Records need one ordered session with explicit start/stop")
    let entry = records[1]["entry"] as! [String: Any]
    try check(entry["sizeStatus"] as? Int == -25204 && entry["positionStatus"] as? Int == 0, "AX result codes must survive serialization unchanged")
    try check(Set(entry.keys) == ["event", "windowID", "pid", "requestedFrame", "sizeStatus", "positionStatus"], "Diagnostic schema must not add content or free-form fields")
    let fileMode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber
    let dirMode = try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as! NSNumber
    try check(fileMode.intValue == 0o600 && dirMode.intValue == 0o700, "New logs and directory must be private to the user")
    let before = try Data(contentsOf: url)
    recorder.write(.init(event: .selection, windowID: 99))
    let after = try Data(contentsOf: url)
    try check(after == before, "Writes after Stop must have no effect")
#endif
}

@MainActor func diagnosticRotationAndSamplingAreBounded() throws {
#if HAS_WINDOW_DIAGNOSTICS
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("tabbed-diag-test-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = WindowDiagnosticRecorder(directory: root, maxBytes: 1024)
    try recorder.start()
    let sample = WindowDiagnosticEntry(event: .trackingSample, windowID: 1, cgFrame: [1, 2, 3, 4])
    recorder.write(sample); recorder.write(sample); recorder.write(sample)
    let rows = try String(contentsOf: root.appendingPathComponent("window-events.jsonl")).split(separator: "\n")
    try check(rows.count == 2, "Repeated identical tracking samples must be omitted")
    for id in 0..<100 { recorder.write(.init(event: .frameRequest, windowID: UInt32(id), requestedFrame: [1, 2, 3, 4])) }
    recorder.stop()
    let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
    try check(Set(files.map(\.lastPathComponent)) == ["window-events.jsonl", "window-events.previous.jsonl"], "Rotation must retain exactly two fixed log files")
    for file in files {
        let data = try Data(contentsOf: file)
        try check(data.count <= 1024, "Each file must stay within its byte limit")
        for row in data.split(separator: 0x0A) { _ = try JSONSerialization.jsonObject(with: Data(row)) }
    }
    try check(recorder.failure == nil, "Normal rotation must not stop with an IO error")
#endif
}

@MainActor func diagnosticPathsRejectLinksAndStopOnFailure() throws {
#if HAS_WINDOW_DIAGNOSTICS
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("tabbed-diag-test-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let target = root.appendingPathComponent("keep.txt")
    try Data("untouched".utf8).write(to: target)
    let logs = root.appendingPathComponent("logs")
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: logs.appendingPathComponent("window-events.jsonl"), withDestinationURL: target)
    let recorder = WindowDiagnosticRecorder(directory: logs)
    var refused = false
    do { try recorder.start() } catch { refused = true }
    try check(refused && !recorder.isRecording, "A symlink log must not be followed or replaced")
    let preserved = try String(contentsOf: target)
    try check(preserved == "untouched", "Refusing a log path must preserve its target")
    let tiny = WindowDiagnosticRecorder(directory: root.appendingPathComponent("tiny"), maxBytes: 1)
    refused = false
    do { try tiny.start() } catch { refused = true }
    try check(refused && !tiny.isRecording && tiny.failure != nil, "An oversized entry must stop recording without recursion")
    let linkDir = root.appendingPathComponent("linked-logs")
    try FileManager.default.createSymbolicLink(at: linkDir, withDestinationURL: logs)
    let unsafe = WindowDiagnosticRecorder(directory: linkDir)
    refused = false
    do { try unsafe.start() } catch { refused = true }
    try check(refused && !unsafe.isRecording, "A symlink diagnostic directory must be rejected")
#endif
}

@MainActor func diagnosticNormalizationDoesNotLeakUnknownValues() throws {
#if HAS_WINDOW_DIAGNOSTICS
    try check(WindowDiagnostics.frame(CGRect.null) == nil, "Nonfinite geometry must not break JSON encoding")
    try check(WindowDiagnostics.frame(CGRect(x: 1, y: 2, width: 3, height: 4)) == [1, 2, 3, 4], "Finite geometry must be retained")
    try check(WindowDiagnostics.notification("private-page-title https://example.invalid") == .other, "Unknown notification strings must be reduced to an enum")
#endif
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
        ("app launched during display transition stays observed", appLaunchDuringDisplayTransitionInstallsCreationObserver),
        ("creation cannot adopt unrelated focused/main window", windowCreationDoesNotAdoptUnrelatedFocusedWindow),
        ("closed transient cannot adopt focused destination", closedCreationDoesNotAdoptFocusedDestination),
        ("ordinary created window still auto-adds", directCreatedWindowStillAutoAdds),
        ("notification child cannot enroll its containing window", notificationChildCannotEnrollItsContainingWindow),
        ("creation during mouse drag cannot auto-add", creationDuringDragDoesNotAutoAdd),
        ("drag release rechecks original window", releasedDragRechecksOriginalElement),
        ("drag retries remain bounded", dragRetriesAreBounded),
        ("delayed creation honors disabled auto-add", delayedCreationHonorsDisabledAutoAdd),
        ("created window waits for display settlement", creationWaitsForDisplaySettlement),
        ("deferred creation revalidates current state", deferredCreationRevalidatesState),
        ("disabled/stopped auto-add ignores creation", autoAddOffAndShutdownIgnoreCreation),
        ("failed Quit explains running/stopped state", failedQuitExplainsThatManagementRemainsStopped),
        ("successful Quit has no stopped-state notice", successfulQuitDoesNotShowStoppedNotice),
        ("confirmed exit skips further restoration", confirmedQuitDoesNotRestoreAgainDuringTermination),
        ("cancelled bypass retains recovery targets", cancelledBypassKeepsRecoveryTargets),
        ("aborted confirmation cannot approve bypass", abortedConfirmationCannotApproveBypass),
        ("dismissed warning cannot approve bypass", dismissedWarningCannotApproveBypass),
        ("restoration waits for geometry publication", restorationWaitsForPublishedFrame),
        ("normal Quit cascades each group", normalQuitCascadesGroupWindows),
        ("granted permission closes guidance", grantedPermissionClosesGuidance),
        ("permission grant starts without relaunch", permissionGrantStartsWithoutRelaunch),
        ("tap failure stays inactive and recovers", tapFailureDoesNotClaimReadyAndCanRecover),
        ("denied permission keeps waiting", deniedPermissionKeepsWaiting),
        ("first tap failure prevents partial startup", firstTapFailurePreventsPartialStartup),
        ("controller startup is idempotent", controllerStartupIsIdempotent),
        ("Quit while waiting cancels polling", quittingWhileWaitingCancelsPolling),
        ("cancelled Quit cannot resume startup", cancelledQuitCannotResumePermissionStartup),
        ("ad-hoc guidance does not claim proven stale registration", adHocGuidanceDoesNotClaimAnOldEntryIsProven),
        ("unknown signature does not invent a cause", unknownSignatureDoesNotInventASigningCause),
        ("permission guidance explicitly opens Settings", guidanceOpensSettingsOnlyOnExplicitChoice),
        ("permission guidance activates without repeated focus stealing", guidanceActivatesOnceWithoutStealingFocusDuringPolling),
        ("permission guidance reveals current app", guidanceCanRevealTheCurrentApp),
        ("guidance dismissal keeps waiting without repetition", dismissingGuidanceKeepsWaitingWithoutActions),
        ("granted/stopped apps skip stale permission guidance", grantedOrStoppedAppDoesNotShowStalePermissionGuidance),
        ("diagnostics are opt-in and private", diagnosticRecorderIsExplicitAndPrivate),
        ("diagnostic rotation and sampling are bounded", diagnosticRotationAndSamplingAreBounded),
        ("diagnostic paths reject links and failures stop recording", diagnosticPathsRejectLinksAndStopOnFailure),
        ("diagnostic normalization does not leak unknown strings", diagnosticNormalizationDoesNotLeakUnknownValues),
    ]
    var failed = 0
    for (name, body) in cases {
        do { try body(); print("PASS: \(name)") }
        catch { failed += 1; print("FAIL: \(name): \(error)") }
    }
    print("INTERNAL_RESULT: \(cases.count - failed)/\(cases.count); simulated AX/UI boundaries, no OS events")
    if failed != 0 { exit(1) }
}
