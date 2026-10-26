import Foundation
import CoreGraphics

// Boundary doubles. The methods under test are copied verbatim from production.
typealias WindowID = UInt32
typealias CGWindowID = UInt32
enum CGWindowListOption { case optionAll }
let kCGWindowNumber = "id", kCGWindowOwnerPID = "pid"
var snapshot: Any? = []
var snapshotQueries = 0
func CGWindowListCopyWindowInfo(_ options: CGWindowListOption, _ relativeTo: UInt32) -> Any? {
    precondition(options == .optionAll && relativeTo == 0)
    snapshotQueries += 1
    return snapshot
}
enum WindowServerSnapshot {}

@MainActor final class ManagedWindow {
    let id: WindowID
    let pid: Int32
    init(_ id: WindowID) { self.id = id; pid = 100 }
}
@MainActor final class Panel {
    var hidden = false
    func hide() { hidden = true }
}
@MainActor final class TabGroup {
    let id = UUID()
    var windows: [ManagedWindow]
    var activeIndex = 0
    var contentFrame = CGRect(x: 10, y: 20, width: 800, height: 600)
    let panel = Panel()
    init(_ ids: [WindowID]) { windows = ids.map(ManagedWindow.init) }
    var activeWindow: ManagedWindow? { windows.indices.contains(activeIndex) ? windows[activeIndex] : nil }
}
@MainActor final class Observer {
    var observed: [WindowID] = [], unobserved: [WindowID] = []
    func observe(_ window: ManagedWindow) { observed.append(window.id) }
    func unobserve(_ id: WindowID) { unobserved.append(id) }
}
@MainActor final class Engine {
    var writes: [WindowID] = []
    func setFrame(_ frame: CGRect, of window: ManagedWindow) { writes.append(window.id) }
    func frame(of window: ManagedWindow) -> CGRect? { nil }
}
@MainActor final class TabGroupController {
    var isStopping = false, isApplyingLayout = false
    var groups: [TabGroup] = []
    var windowLifecycleTimer: Timer?
    var activeMoveGroup: TabGroup?
    weak var mostRecentGroup: TabGroup?
    var draggedWindow: ManagedWindow?
    let engine = Engine(), observer = Observer()
    var layouts: [[WindowID]] = []
    var trackingEnds = 0
    func group(containing id: WindowID) -> TabGroup? { groups.first { $0.windows.contains { $0.id == id } } }
    func applyLayout(for group: TabGroup) { layouts.append(group.windows.map(\.id)) }
    func updateFocusObservers() {}
    func endTrackingActiveMove(restorePanel: Bool = true) { activeMoveGroup = nil; trackingEnds += 1 }
    func isGroupOnActiveSpace(_ group: TabGroup) -> Bool { true }
    func positionPanel(for group: TabGroup) {}
    func beginTrackingActiveMove(for group: TabGroup) {}
    func adoptTrackedFrame(_ frame: CGRect, for group: TabGroup) {}
}
let kAXUIElementDestroyedNotification = "destroyed"
let kAXWindowMiniaturizedNotification = "minimized"
let kAXMovedNotification = "moved"
let kAXResizedNotification = "resized"
@MainActor enum DispatchQueue {
    static let main = Queue()
    final class Queue {
        var pending: [() -> Void] = []
        func asyncAfter(deadline: DispatchTime, execute: @escaping () -> Void) { pending.append(execute) }
        func runNext() { if !pending.isEmpty { pending.removeFirst()() } }
    }
}
