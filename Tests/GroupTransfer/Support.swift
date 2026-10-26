import Foundation
import CoreGraphics

typealias WindowID = UInt32
typealias TabGroup = Group
typealias ManagedWindow = Window
let kAXUIElementDestroyedNotification = "destroyed"
let kAXWindowMiniaturizedNotification = "miniaturized"
let kAXMovedNotification = "moved"
let kAXResizedNotification = "resized"
@MainActor final class Window {
    let id: WindowID
    let pid: Int32
    var element: WindowID { id }
    init(_ id: WindowID, _ pid: Int32) { self.id = id; self.pid = pid }
}
@MainActor final class Panel {
    final class Model { var hovered = false }
    let model = Model()
    var onFrameChanged: (() -> Void)?
    var waitForPointerExit = false
    var isCompact = false
    var restingFrame = CGRect.zero
    var expandedFrame = CGRect.zero
    let collapseSafeZoneX: CGFloat = 28
    let collapseSafeZoneY: CGFloat = 72
    var collapseWatcher: Timer?
    var windowNumber = 900
    var isVisible: Bool { visible }
    var forcedFront = 0
    func orderFrontRegardless() { forcedFront += 1 }
    var frame = CGRect.zero
    func setFrame(_ frame: CGRect, display: Bool) { self.frame = frame; relativeTo = nil }
    enum Ordering { case above, below }
    var relativeTo: Int?
    var visible = false
    func hide(animated: Bool = true) { visible = false }
    func show() { visible = true; relativeTo = nil }
    func order(_ mode: Ordering, relativeTo id: Int) { relativeTo = id; visible = true }
    func orderOut(_ sender: Any?) { visible = false }
}
@MainActor final class Group {
    var windows: [Window]
    let id = UUID()
    var activeIndex = 0
    var spaceID: UInt64?
    var isPanelHiddenForMove = false
    final class ViewModel { var compact = false }
    let viewModel = ViewModel()
    var useCompact = false
    var stripFrame: CGRect { contentFrame.offsetBy(dx: 0, dy: contentFrame.height) }
    var compactExpandedFrame: CGRect { stripFrame }
    var stripFrameAbove: CGRect { stripFrame }
    func contains(_ id: WindowID) -> Bool { windows.contains { $0.id == id } }
    convenience init(windows: [Window], activeIndex: Int, contentFrame: CGRect, spaceID: UInt64?) {
        self.init(windows, contentFrame); self.activeIndex=activeIndex; self.spaceID=spaceID
    }
    var contentFrame: CGRect
    let panel = Panel()
    init(_ windows: [Window], _ frame: CGRect) { self.windows = windows; contentFrame = frame }
    var activeWindow: Window? { windows.indices.contains(activeIndex) ? windows[activeIndex] : nil }
    func syncViewModel() {}
}
@MainActor struct NSScreen {
    let frame: CGRect
    let visibleFrame: CGRect
    static var screens = [NSScreen(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 40, width: 1440, height: 835))]
    static var main: NSScreen? { screens.first }
}
// Do not schedule a real timer. Its callback is invoked explicitly in main.swift.
@MainActor final class Timer {
    var valid = true
    init(timeInterval: TimeInterval = 0, repeats: Bool = false, block: @escaping (Timer) -> Void = { _ in }) {}
    static func scheduledTimer(withTimeInterval: TimeInterval, repeats: Bool, block: @escaping (Timer) -> Void) -> Timer { Timer() }
    func invalidate() { valid = false }
}
@MainActor final class RunLoop {
    static let main = RunLoop()
    enum Mode { case common }
    func add(_ timer: Timer, forMode: Mode) {}
}
@MainActor final class Engine {
    var frames: [WindowID: CGRect] = [:]
    var cgFrames: [WindowID: CGRect] = [:]
    var rejectSize: Set<WindowID> = []
    var rejectPosition: Set<WindowID> = []
    var closed: Set<WindowID> = []
    var spaces: [WindowID: UInt64] = [:]
    func activeSpaceID() -> UInt64? { activeSpaces?.first }
    var activeSpaces: Set<UInt64>?
    func activeSpaceIDs() -> Set<UInt64>? { activeSpaces }
    var spaceMoves: [WindowID] = []
    func spaceID(of window: Window) -> UInt64? { spaces[window.id] }
    func move(_ window: Window, toSpaceOf reference: Window) { spaceMoves.append(window.id); spaces[window.id]=spaces[reference.id] }
    var frontmost: WindowID?
    func frontmostWindowID() -> WindowID? { frontmost }
    var onActivate: (() -> Void)?
    var reads: [WindowID] = []
    var cgReads: [WindowID] = []
    var writes: [(WindowID, CGRect)] = []
    func frame(of window: Window) -> CGRect? { reads.append(window.id); return closed.contains(window.id) ? nil : frames[window.id] }
    func windowServerFrame(of id: WindowID) -> CGRect? { cgReads.append(id); return cgFrames[id] }
    func setFrame(_ frame: CGRect, of window: Window) {
        writes.append((window.id, frame))
        guard !closed.contains(window.id) else { return }
        let previous = frames[window.id] ?? frame
        frames[window.id] = CGRect(origin: rejectPosition.contains(window.id) ? previous.origin : frame.origin,
                                  size: rejectSize.contains(window.id) ? previous.size : frame.size)
    }
    func refreshTitle(_ window: Window) -> String { "Fixture" }
    func raise(_ window: Window) {}
    func activate(_ window: Window) { onActivate?() }
    func isKnownClosed(_ window: Window) -> Bool { closed.contains(window.id) }
    func isAlive(_ window: Window) -> Bool { !closed.contains(window.id) }
}
@MainActor final class Controller {
    final class Observer { func unobserve(_ id: WindowID) {} }
    let observer = Observer()
    weak var mostRecentGroup: Group?
    let engine = Engine()
    var panelZOrderSyncGeneration = 0
    func endTrackingActiveMove(restorePanel: Bool = true) {}
    func wire(_ group: Group) {}
    func applyLayout(for group: Group) {}
    func observeWindows(in group: Group) {}
    func markRecentlyUsed(_ group: Group) {}
    func updateFocusObservers() {}
    func updateWindowLifecycleMonitoring() {} // Covered by standalone WindowLifecycle tests.
    func frontmostGroup() -> Group? { groups.first { $0.activeWindow?.id == engine.frontmost } }
    var syncCount = 0
    func syncPanelZOrderWithFrontmostGroup() { syncCount += 1; groups.forEach { _ in } }
    var isStopping = false
    var isApplyingLayout = false
    var draggedWindow: Window?
    var groups: [Group] = []
    var activeMoveGroup: Group?
    var activeMoveOriginWindowID: WindowID?
    var activeMoveDeadline = Date.distantPast
    var activeMoveTimer: Timer?
    func group(containing id: WindowID) -> Group? { groups.first { $0.windows.contains { $0.id == id } } }
    func remove(_ id: WindowID, from group: Group, keepWindowObserved: Bool) { group.windows.removeAll { $0.id == id }; group.activeIndex = min(group.activeIndex, max(0, group.windows.count - 1)) }
}

let kAXPositionAttribute = "position"
let kAXSizeAttribute = "size"
enum CoordinateConverter {
    static func cgFrame(fromAppKit frame: CGRect) -> CGRect { frame }
}
struct AXStatus { let rawValue: Int32 = 0 }
@MainActor final class AXWindowEngine {
    var actual = CGRect(x:1439,y:-679,width:1100,height:720)
    var operations: [String] = []
    func copyCGSizeAttribute(_ attribute: String, from: WindowID) -> CGSize? { actual.size }
    func setCGPointAttribute(_ attribute: String, value: CGPoint, on: WindowID) -> AXStatus {
        operations.append("position"); actual.origin=value; return AXStatus()
    }
    func setCGSizeAttribute(_ attribute: String, value: CGSize, on: WindowID) -> AXStatus {
        operations.append("size")
        // Model an application that acknowledges but clamps resizing while parked.
        if actual.minX < 1400 && actual.minY >= 0 { actual.size=value }
        return AXStatus()
    }
}

@MainActor enum NSEvent { static var mouseLocation = CGPoint.zero }

@MainActor enum WindowServerSnapshot {
    static var ids: [WindowID] = []
    static func visibleWindowIDs() -> [WindowID] { ids }
}
@MainActor final class DispatchQueue {
    static let main = DispatchQueue()
    var pending: [() -> Void] = []
    func asyncAfter(deadline: DispatchTime, execute: @escaping () -> Void) { pending.append(execute) }
    func drain() { let work = pending; pending = []; work.forEach { $0() } }
}
