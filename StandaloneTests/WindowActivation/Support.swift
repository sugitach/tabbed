import Foundation
import CoreFoundation
typealias AXUIElement = CFString
func axElement(_ token: String) -> AXUIElement {
    CFStringCreateWithCString(nil, token, CFStringBuiltInEncodings.UTF8.rawValue)!
}
import CoreGraphics

typealias WindowID = UInt32
@MainActor final class Application {
    var processIdentifier: Int32
    init(_ pid: Int32) { processIdentifier = pid }
}
@MainActor final class NSWorkspace {
    static let shared = NSWorkspace()
    var frontmostApplication: Application?
}
@MainActor final class ManagedWindow {
    let id: WindowID
    let pid: Int32
    let element: AXUIElement
    init(_ id: WindowID, _ pid: Int32) {
        self.id = id; self.pid = pid; self.element = axElement("window-\(pid)-\(id)")
    }
}
@MainActor final class TabGroup {
    var windows: [ManagedWindow]
    var activeIndex = 0
    var onActiveSpace = true
    var moveAnchorFrame: CGRect?
    let contentFrame = CGRect(x: 100, y: 200, width: 800, height: 600)
    init(_ windows: [ManagedWindow]) { self.windows = windows }
    var activeWindow: ManagedWindow? { windows[activeIndex] }
}
@MainActor final class Engine {
    var deadIDs: Set<WindowID> = []
    func isAlive(_ window: ManagedWindow) -> Bool { !deadIDs.contains(window.id) }
    var focused: [Int32: WindowID] = [:]
    var main: [Int32: WindowID] = [:]
    func mainWindowID(for pid: Int32) -> WindowID? { main[pid] }
    func focusedOrMainWindowID(for pid: Int32) -> WindowID? { focused[pid] }
}
@MainActor final class TabGroupController {
    let ownPID: Int32 = 999
    let engine = Engine()
    var groups: [TabGroup] = []
    var panelZOrderSyncGeneration = 0
    var preferredMainWindowPID: pid_t?
    var mainWindowPreferenceDeadline = Date.distantPast
    var isStopping = false, isApplyingLayout = false
    var draggedWindow: ManagedWindow?
    var activeMoveGroup: TabGroup?
    var selections: [WindowID] = []
    var trackingEnds = 0, panelPositions = 0, panelOrders = 0
    var selectedFrames: [CGRect] = []
    var duringSelection: (() -> Void)?
    func isGroupOnActiveSpace(_ group: TabGroup) -> Bool { group.onActiveSpace }
    func endTrackingActiveMove() { activeMoveGroup = nil; trackingEnds += 1 }
    // Layout/AX boundary: record the existing selection entry point and frame.
    func selectTab(_ id: WindowID, in group: TabGroup) {
        selections.append(id)
        group.activeIndex = group.windows.firstIndex { $0.id == id }!
        selectedFrames.append(group.contentFrame)
        isApplyingLayout = true
        duringSelection?()
        isApplyingLayout = false
    }
    func markRecentlyUsed(_ group: TabGroup) {}
    func positionPanel(for group: TabGroup) { panelPositions += 1 }
    func reassertPanelZOrder(for group: TabGroup) { panelOrders += 1 }
}
