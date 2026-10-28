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
    let id = UUID()
    final class Panel { func collapseAfterSelection() {} }
    let panel = Panel()
    var windows: [ManagedWindow]
    var focusSettlementUntil: TimeInterval = 0
    var activeIndex = 0
    var onActiveSpace = true
    var moveAnchorFrame: CGRect?
    let contentFrame = CGRect(x: 100, y: 200, width: 800, height: 600)
    init(_ windows: [ManagedWindow]) { self.windows = windows }
    func contains(_ id: WindowID) -> Bool { windows.contains { $0.id == id } }
    var activeWindow: ManagedWindow? { windows[activeIndex] }
}
@MainActor final class Engine {
    var activations: [WindowID] = []
    func activate(_ window: ManagedWindow) { activations.append(window.id) }
    var deadIDs: Set<WindowID> = []
    func isAlive(_ window: ManagedWindow) -> Bool { !deadIDs.contains(window.id) }
    var focused: [Int32: WindowID] = [:]
    var main: [Int32: WindowID] = [:]
    func mainWindowID(for pid: Int32) -> WindowID? { main[pid] }
    func focusedOrMainWindowID(for pid: Int32) -> WindowID? { focused[pid] }
}
@MainActor final class TabGroupController {
    var pendingShortcutSelection: PendingShortcutSelection?
    var shortcutSelectionInProgress = false
    let ownPID: Int32 = 999
    let engine = Engine()
    var groups: [TabGroup] = []
    var panelZOrderSyncGeneration = 0
    var preferredMainWindowPID: pid_t?
    var mainWindowPreferenceDeadline = Date.distantPast
    var isStopping = false, isApplyingLayout = false
    var draggedWindow: ManagedWindow?
    var activeMoveGroup: TabGroup?
    var selections: [WindowID] { engine.activations }
    var activeMoveOriginWindowID: WindowID?
    var trackingEnds = 0, panelPositions = 0, panelOrders = 0
    var selectedFrames: [CGRect] = []
    var duringSelection: (() -> Void)?
    func isGroupOnActiveSpace(_ group: TabGroup) -> Bool { group.onActiveSpace }
    func endTrackingActiveMove() { if activeMoveGroup != nil { trackingEnds += 1 }; activeMoveGroup = nil }
    // Real selectTab calls this simulated AX/layout boundary.
    func applyLayout(for group: TabGroup) {
        selectedFrames.append(group.contentFrame)
        isApplyingLayout = true
        duringSelection?()
        isApplyingLayout = false
    }
    func markRecentlyUsed(_ group: TabGroup) {}
    func positionPanel(for group: TabGroup) { panelPositions += 1 }
    func reassertPanelZOrder(for group: TabGroup) { panelOrders += 1 }
}

struct DiagnosticEntry {
    enum Event { case selection, focusSelectionDeferred }
    enum Reason { case activationSettling }
    var event: Event
    var windowID: WindowID? = nil
    var pid: Int32? = nil
    var groupID: UUID? = nil
    var activeWindowID: WindowID? = nil
    var trackingWindowID: WindowID? = nil
    var groupFrame: [Double]? = nil
    var reason: Reason? = nil
}
enum WindowDiagnostics {
    static func record(_ entry: DiagnosticEntry) {}
    static func frame(_ frame: CGRect) -> [Double] { [] }
}
