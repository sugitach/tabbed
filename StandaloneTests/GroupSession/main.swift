import Foundation
import CoreGraphics

@MainActor func run() throws {
    var checks = 0
    func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message); checks += 1
    }
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = GroupSessionStore(url: dir.appendingPathComponent("state/groups.json"))
    let frame = CGRect(x: 50, y: 100, width: 800, height: 600)
    let a = SavedWindowIdentity(id: 1, pid: 100, processLaunchTime: 12345, bundleID: "test.app")
    let b = SavedWindowIdentity(id: 2, pid: 100, processLaunchTime: 12345, bundleID: "test.app")
    let d = SavedWindowIdentity(id: 3, pid: 200, processLaunchTime: 23456, bundleID: "test.app")
    let saved = SavedWindowGroup(windows: [a, b, d], selectedID: 2, frame: frame)
    let session = GroupSession(groups: [saved])
    func fixture() -> TabGroupController {
        NSRunningApplication.apps = [100: NSRunningApplication(12345), 200: NSRunningApplication(23456)]
        let c = TabGroupController(store)
        c.engine.windows = [1: ManagedWindow(1), 2: ManagedWindow(2), 3: ManagedWindow(3, 200)]
        return c
    }
    check(store.load() == nil, "missing state is harmless")
    try store.save(session)
    check(store.load()?.groups[0].windows == [a,b,d], "roundtrip preserves member order")
    let mode = try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as! NSNumber
    check(mode.intValue == 0o600, "state is private")
    do {
        let c = fixture(); c.restoreSavedGroups()
        check(c.groups.count == 1 && c.groups[0].activeWindow?.id == 2, "selected member restored")
        check(c.groups[0].contentFrame == frame && c.wired == 1 && c.observed == 1 && c.layouts == 1, "real group integration entry points used")
        c.restoreSavedGroups(); check(c.groups.count == 1, "startup restore is one-shot")
        c.captureSessionForTermination(); c.groups.removeAll(); c.captureSessionForTermination()
        c.persistSessionForTermination()
        check(store.load()?.groups[0].windows == [a,b,d], "quit retry after clearing retains original snapshot")
        let empty = fixture(); empty.persistSessionForTermination()
        check(store.load()?.groups.isEmpty == true, "explicit ungroup then Quit saves empty session")
        try store.save(session)
    }
    do {
        let c = fixture(); c.engine.windows[2] = nil
        c.restoreSessionGroups([saved], attemptsRemaining: 0)
        check(c.groups.first?.windows.map(\.id) == [1,3], "missing selected window skipped; survivors retain order")
        check(c.groups.first?.activeWindow?.id == 1, "missing selection falls back to first survivor")
        let only = fixture(); only.engine.windows = [1: ManagedWindow(1)]
        only.restoreSessionGroups([saved], attemptsRemaining: 0)
        check(only.groups.isEmpty, "one survivor stays ungrouped")
        let reused = fixture(); NSRunningApplication.apps[100] = NSRunningApplication(99999)
        reused.restoreSessionGroups([saved], attemptsRemaining: 0)
        check(reused.groups.isEmpty, "reused PID cannot match old windows")
        let bundle = fixture(); NSRunningApplication.apps[100] = NSRunningApplication(12345, "other.app")
        bundle.restoreSessionGroups([saved], attemptsRemaining: 0)
        check(bundle.groups.isEmpty, "changed owner bundle cannot match")
        let owner = fixture(); owner.engine.windows[1] = ManagedWindow(1, 999); owner.engine.windows[2] = nil
        owner.restoreSessionGroups([saved], attemptsRemaining: 0)
        check(owner.groups.isEmpty, "reused window ID under other PID cannot match")
        let spaces = fixture(); spaces.engine.spaces[2] = 2
        spaces.restoreSessionGroups([saved], attemptsRemaining: 0)
        check(spaces.groups.isEmpty, "changed Spaces are not merged or moved")
    }
    do {
        let c = fixture(); c.isStarted = false
        c.restoreSavedGroups(); c.persistSessionForTermination()
        check(!c.didRestoreSession && store.load()?.groups.count == 1, "permission waiting does not load or overwrite")
        c.isStarted = true; c.isStopping = true; c.restoreSavedGroups()
        check(c.groups.isEmpty, "Quit cancels startup restoration")
    }
    do {
        let c = fixture(); c.engine.windows[2] = nil
        c.restoreSavedGroups()
        check(c.groups.isEmpty, "AX unavailable defers whole group")
        c.engine.windows[2] = ManagedWindow(2)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        check(c.groups.first?.windows.count == 3, "bounded retry restores transiently unavailable member")
        let cancel = fixture(); cancel.engine.windows[2] = nil; cancel.restoreSavedGroups()
        cancel.sessionInteractionGeneration += 1
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        check(cancel.groups.isEmpty, "user interaction cancels delayed restore")
    }
    do {
        let early = fixture(); early.engine.windows[2] = nil
        early.restoreSavedGroups(); early.isStopping = true
        early.persistSessionForTermination()
        check(store.load()?.groups.first?.windows == [a,b,d], "early Quit preserves unresolved startup group")

        let partial = fixture()
        let first = SavedWindowGroup(windows: [a,b], selectedID: 2, frame: frame)
        let e = SavedWindowIdentity(id: 4, pid: 200, processLaunchTime: 23456, bundleID: "test.app")
        let second = SavedWindowGroup(windows: [d,e], selectedID: 3, frame: frame)
        partial.restoreSessionGroups([first, second], attemptsRemaining: 3)
        partial.isStopping = true; partial.persistSessionForTermination()
        check(store.load()?.groups.map { $0.windows.map(\.id) } == [[1,2],[3,4]], "partial restore Quit preserves restored and pending groups")

        try store.save(session)
        let cancel = fixture(); cancel.engine.windows[2] = nil; cancel.restoreSavedGroups()
        cancel.sessionInteractionGeneration += 1; cancel.isStopping = true
        cancel.persistSessionForTermination()
        check(store.load()?.groups.isEmpty == true, "user cancellation excludes pending groups from Quit snapshot")

        try store.save(session)
        let completed = fixture(); completed.engine.windows[2] = nil; completed.restoreSavedGroups()
        completed.engine.windows[2] = ManagedWindow(2)
        completed.restoreSessionGroups([saved], attemptsRemaining: 0)
        check(completed.pendingSessionGroups.isEmpty, "successful retry clears pending state")
        completed.groups.removeAll(); completed.persistSessionForTermination()
        check(store.load()?.groups.isEmpty == true, "completed startup state cannot resurrect an ungrouped group")
        try store.save(session)
    }
    do {
        var history = DisplayLayoutHistory()
        history.remember(frame, for: "A")
        let remembered = SavedWindowGroup(windows: [a,b,d], selectedID: 2, frame: frame,
            displayConfiguration: "A", displayLayouts: history)
        let original = GroupSession(groups: [remembered])
        try store.save(original)
        let early = fixture(); early.displayTransitionPending = true
        early.restoreSavedGroups()
        check(early.groups.isEmpty && early.pendingSessionGroups.count == 1,
            "topology transition defers and retains startup restoration")
        early.isStopping = true; early.persistSessionForTermination()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let persisted = try store.load().map { try encoder.encode($0) }
        let expected = try encoder.encode(original)
        check(persisted == expected,
            "Quit during topology transition preserves startup members, selection and layout history")
        let cancel = fixture(); cancel.displayTransitionPending = true
        cancel.restoreSavedGroups(); cancel.sessionInteractionGeneration += 1
        cancel.persistSessionForTermination()
        check(store.load()?.groups.isEmpty == true,
            "explicit interaction discards topology-deferred startup state on Quit")
        cancel.displayTransitionPending = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        check(cancel.groups.isEmpty && early.groups.isEmpty,
            "cancelled and stopped topology-deferred callbacks cannot restore groups")
        try store.save(session)
    }
    do {
        let bad = GroupSession(version: 2, groups: [saved])
        check(!bad.isValid, "unknown version rejected")
        let duplicate = GroupSession(groups: [SavedWindowGroup(windows: [a,a], selectedID: 1, frame: frame)])
        check(!duplicate.isValid, "duplicate IDs rejected")
        let badFrame = GroupSession(groups: [SavedWindowGroup(windows: [a,b], selectedID: 1, frame: .zero)])
        check(!badFrame.isValid, "invalid geometry rejected")
        try Data("{broken".utf8).write(to: store.url)
        check(store.load() == nil, "corrupt JSON ignored")
        try JSONEncoder().encode(bad).write(to: store.url)
        check(store.load() == nil, "incompatible file ignored")
        try Data(repeating: 32, count: 1_048_577).write(to: store.url)
        check(store.load() == nil, "oversized file ignored")
        try FileManager.default.removeItem(at: store.url)
        try FileManager.default.createSymbolicLink(at: store.url, withDestinationURL: dir.appendingPathComponent("target"))
        check(store.load() == nil, "symlink not loaded")
        try store.save(session)
        check(store.load()?.groups.count == 1, "atomic save replaces link, not its target")
        check(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("target").path), "symlink target untouched")
    }
    do {
        // Old version-1 state has no display metadata and remains readable.
        let old = try JSONDecoder().decode(GroupSession.self, from: JSONEncoder().encode(session))
        check(old.isValid && old.groups[0].displayLayouts == nil, "legacy state remains valid")
        var history = DisplayLayoutHistory()
        let other = CGRect(x: 200, y: 150, width: 900, height: 650)
        history.remember(frame, for: "A"); history.remember(other, for: "B")
        let withHistory = SavedWindowGroup(windows: [a,b], selectedID: 1, frame: frame,
            displayConfiguration: "A", displayLayouts: history)
        try store.save(GroupSession(groups: [withHistory]))
        check(store.load()?.groups[0].displayLayouts?.frame(for: "B") == other, "configuration history stored privately with session")
        let returning = fixture(); returning.currentDisplayConfiguration = "B"
        returning.restoreSessionGroups([withHistory], attemptsRemaining: 0)
        check(returning.groups.first?.contentFrame == other, "startup uses remembered current-configuration frame")
        let unseen = fixture(); unseen.currentDisplayConfiguration = "C"; unseen.engine.frames[1] = other
        unseen.restoreSessionGroups([withHistory], attemptsRemaining: 0)
        check(unseen.groups.first?.contentFrame == other, "startup in unseen configuration adopts OS frame")
        let same = fixture(); same.currentDisplayConfiguration = "A"
        same.restoreSessionGroups([withHistory], attemptsRemaining: 0)
        check(same.groups.first?.contentFrame == frame, "startup in original configuration preserves original frame")
    }
    print("PASS: \(checks) group-session checks (production store/controller methods; simulated AX/process/UI)")
}
try MainActor.assumeIsolated { try run() }
