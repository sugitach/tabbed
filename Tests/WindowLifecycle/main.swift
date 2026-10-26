import Foundation

var passed = 0
@MainActor func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    guard condition() else { fatalError("FAIL: " + name) }
    passed += 1
    print("PASS: " + name)
}
@MainActor func fixture(_ ids: [WindowID] = [1, 2, 3], active: Int = 0) -> (TabGroupController, TabGroup) {
    let controller = TabGroupController(), group = TabGroup(ids)
    group.activeIndex = active
    controller.groups = [group]
    controller.mostRecentGroup = group
    return (controller, group)
}
func owners(_ ids: [WindowID]) {
    snapshot = ids.map { ["id": NSNumber(value: $0), "pid": NSNumber(value: 100)] }
}
@MainActor func tests() {
    owners([1, 2, 3])
    check(WindowServerSnapshot.windowOwners() == [1: 100, 2: 100, 3: 100], "complete all-window snapshot maps IDs to owners")
    snapshot = [["id": NSNumber(value: 1)]]
    check(WindowServerSnapshot.windowOwners() == nil, "incomplete snapshot is unknown")
    snapshot = nil
    check(WindowServerSnapshot.windowOwners() == nil, "failed query is unknown")
    do {
        let (c, g) = fixture()
        owners([2, 3])
        c.reconcileWindowLifetimes()
        check(g.windows.map(\.id) == [2, 3] && g.activeWindow?.id == 2, "missed close notification removes selected tab")
        check(c.layouts == [[2, 3]] && c.observer.unobserved == [1], "remaining tabs relayout once and closed member is unobserved")
    }
    do {
        let (c, g) = fixture(active: 2)
        owners([2, 3])
        c.reconcileWindowLifetimes()
        check(g.activeWindow?.id == 3 && g.activeIndex == 1, "background close preserves selected window")
    }
    do {
        let (c, g) = fixture([1, 2], active: 1)
        c.observeWindows(in: g)
        let timer = c.windowLifecycleTimer!
        owners([1])
        timer.fire()
        check(c.groups.isEmpty && g.panel.hidden && c.engine.writes == [1], "two-to-one dissolves panel and restores remaining window")
        check(Set(c.observer.unobserved) == [1, 2], "dissolution releases all observers")
        check(c.windowLifecycleTimer == nil && !timer.isValid, "last group dissolution stops poll timer")
    }
    do {
        let (c, _) = fixture()
        owners([])
        c.reconcileWindowLifetimes()
        check(c.groups.isEmpty && c.engine.writes.isEmpty && c.layouts.isEmpty, "all windows close atomically without restoring dead members")
    }
    do {
        let (c, _) = fixture([1, 2, 3, 4])
        owners([4])
        c.reconcileWindowLifetimes()
        check(c.groups.isEmpty && c.engine.writes == [4] && c.layouts.isEmpty, "batch closure restores only the survivor")
    }
    do {
        let (c, g) = fixture()
        // No visibility, AX geometry, or alpha is supplied: parked windows remain.
        owners([1, 2, 3])
        c.reconcileWindowLifetimes()
        check(g.windows.count == 3 && c.layouts.isEmpty, "offscreen or minimized members remain when WindowServer still owns them")
        snapshot = nil
        c.reconcileWindowLifetimes()
        check(g.windows.count == 3, "snapshot failure retains every member")
        snapshot = [["id": 1, "pid": 100], ["id": 2]]
        c.reconcileWindowLifetimes()
        check(g.windows.count == 3, "partial snapshot never prunes a group")
        snapshot = [["id": 1, "pid": 999], ["id": 2, "pid": 100], ["id": 3, "pid": 100]]
        c.reconcileWindowLifetimes()
        check(g.windows.map(\.id) == [2, 3], "reused ID owned by another process is removed")
    }
    do {
        let (c, g) = fixture()
        c.isApplyingLayout = true
        owners([2, 3])
        let queries = snapshotQueries
        c.reconcileWindowLifetimes()
        check(g.windows.count == 3 && snapshotQueries == queries, "poll skips reentrant layout")
        c.handleWindowNotification(id: 1, notification: kAXUIElementDestroyedNotification)
        check(g.windows.count == 3 && DispatchQueue.main.pending.count == 1, "close notification during layout is deferred")
        c.isApplyingLayout = false
        DispatchQueue.main.runNext()
        check(g.windows.map(\.id) == [2, 3], "deferred close is processed after layout")
        c.handleWindowNotification(id: 1, notification: kAXUIElementDestroyedNotification)
        check(c.layouts.count == 1, "duplicate close notification is harmless")
    }
    do {
        let (c, g) = fixture()
        c.isStopping = true
        owners([])
        c.reconcileWindowLifetimes()
        c.handleWindowNotification(id: 1, notification: kAXUIElementDestroyedNotification)
        check(g.windows.count == 3, "termination blocks poll and notifications")
    }
    do {
        let (c, g) = fixture()
        c.observeWindows(in: g)
        let timer = c.windowLifecycleTimer!
        c.updateWindowLifecycleMonitoring()
        check(c.windowLifecycleTimer === timer && timer.timeInterval == 0.5, "observation starts exactly one half-second timer")
        c.isStopping = true
        c.updateWindowLifecycleMonitoring()
        check(c.windowLifecycleTimer == nil && !timer.isValid, "stopping invalidates timer")
    }
    do {
        let (c, g) = fixture()
        c.activeMoveGroup = g
        c.remove(2, from: g, keepWindowObserved: true)
        check(c.observer.unobserved.isEmpty && g.windows.map(\.id) == [1, 3], "transfer removal retains observation")
        check(c.activeMoveGroup == nil && c.trackingEnds == 1, "member change ends active movement tracking")
    }
    do {
        let (c, g) = fixture([1, 2], active: 1)
        let other = TabGroup([3, 4])
        c.groups.append(other)
        c.observeWindows(in: g)
        owners([2, 3, 4])
        c.reconcileWindowLifetimes()
        check(c.groups.count == 1 && c.groups[0] === other && c.windowLifecycleTimer != nil, "one group dissolving retains monitor for other groups")
        c.stopWindowLifecycleMonitoring()
    }
    print("LIFECYCLE_RESULT: \(passed)/\(passed); simulated OS/UI boundaries")
}
MainActor.assumeIsolated { tests() }
