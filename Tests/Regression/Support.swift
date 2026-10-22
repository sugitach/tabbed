import Foundation
import CoreGraphics

// Deliberate test doubles. No AppKit/ApplicationServices import or OS window access.
typealias WindowID = UInt32
enum SimulatedAXError { case success, invalidUIElement, cannotComplete, apiDisabled, failure, notImplemented }
@MainActor enum Trace {
    static var events: [String] = []
    static func add(_ event: String) { events.append(event) }
}
@MainActor final class AXUIElement {
    let id: UInt32
    var resolved: UInt32
    var errors: [SimulatedAXError] = []
    var queries = 0
    init(_ id: UInt32) { self.id = id; self.resolved = id }
}
@MainActor func _AXUIElementGetWindow(_ element: AXUIElement, _ id: inout UInt32) -> SimulatedAXError {
    element.queries += 1
    let error = element.errors.isEmpty ? .success : element.errors.removeFirst()
    if error == .success { id = element.resolved }
    return error
}
@MainActor func AXUIElementSetMessagingTimeout(_ element: AXUIElement, _ seconds: Float) {}
@MainActor final class NSRunningApplication {
    static var terminated: [Int32: Bool] = [:]
    let pid: Int32
    init?(processIdentifier: Int32) {
        guard Self.terminated[processIdentifier] != nil else { return nil }
        pid = processIdentifier
    }
    var isTerminated: Bool { Self.terminated[pid] ?? true }
}
@MainActor final class ManagedWindow {
    let id: UInt32
    let pid: Int32
    let element: AXUIElement
    var appName = "Regression fixture"
    var title = "Test window"
    init(_ id: UInt32) {
        self.id = id; pid = 100 + Int32(id); element = AXUIElement(id)
        NSRunningApplication.terminated[pid] = false
    }
}
@MainActor final class Probe {
    let name: String
    var delegate: AnyObject?
    var onEvent: (() -> Void)? = {}
    var unobserved: [UInt32] = []
    init(_ name: String) { self.name = name }
    func stop() { Trace.add(name + ".stop") }
    func unobserve(_ id: UInt32) { unobserved.append(id) }
    func unobserveAll() { Trace.add(name + ".unobserveAll") }
}
@MainActor final class Panel {
    func hide() { Trace.add("panel.hide") }
}
@MainActor final class TabGroup {
    var windows: [ManagedWindow]
    var activeIndex = 0
    var contentFrame: CGRect
    let panel = Panel()
    init(_ windows: [ManagedWindow], _ frame: CGRect) { self.windows = windows; contentFrame = frame }
    var activeWindow: ManagedWindow? { windows.indices.contains(activeIndex) ? windows[activeIndex] : nil }
}
@MainActor final class AXWindowEngine {
    // isKnownClosed/isAlive are extracted verbatim from production into an extension.
    var frames: [UInt32: CGRect] = [:]
    var attempts: [UInt32] = []
    var writes: [(UInt32, CGRect)] = []
    var onRestore: (ManagedWindow, CGRect) -> Bool = { _, _ in true }
    func frame(of window: ManagedWindow) -> CGRect? { frames[window.id] }
    func restoreFrame(_ frame: CGRect, of window: ManagedWindow) -> Bool {
        Trace.add("restore.\(window.id)"); attempts.append(window.id)
        guard onRestore(window, frame) else { return false }
        frames[window.id] = frame
        return true
    }
    func setFrame(_ frame: CGRect, of window: ManagedWindow) {
        writes.append((window.id, frame)); frames[window.id] = frame
    }
    func activate(_ window: ManagedWindow) { Trace.add("activate.\(window.id)") }
}
@MainActor struct NSScreen {
    let visibleFrame: CGRect
    static var screens = [NSScreen(visibleFrame: CGRect(x: 0, y: 24, width: 1000, height: 700))]
}
@MainActor final class NSWorkspace {
    static let shared = NSWorkspace()
    let notificationCenter = Center()
    @MainActor final class Center {
        func removeObserver(_ object: AnyObject) { Trace.add("workspace.removeObserver") }
    }
}
let kAXUIElementDestroyedNotification = "destroyed"
let kAXWindowMiniaturizedNotification = "minimized"
let kAXMovedNotification = "moved"
let kAXResizedNotification = "resized"

// Only the optional normal-termination callbacks are modeled. No real app or UI.
@MainActor final class NSApplication {
    enum TerminateReply { case terminateNow, terminateCancel }
}
@MainActor final class NSAlert {
    var messageText = ""
    var informativeText = ""
    func addButton(withTitle title: String) {}
    func runModal() {}
}
@MainActor final class AppDelegate {
    let controller: TabGroupController
    init(controller: TabGroupController) { self.controller = controller }
}
@MainActor func requestNormalQuit(_ controller: TabGroupController) -> NSApplication.TerminateReply {
    let delegate = AppDelegate(controller: controller)
    // An absent optional callback does nothing; never supply restoration in a double.
    var reply = NSApplication.TerminateReply.terminateNow
#if HAS_SHOULD_TERMINATE
    reply = delegate.applicationShouldTerminate(NSApplication())
#endif
    if reply == .terminateNow {
#if HAS_WILL_TERMINATE
        delegate.applicationWillTerminate(Notification(name: Notification.Name("termination")))
#endif
    }
    return reply
}
@MainActor final class TabGroupController {
    // The tested methods are extracted unchanged; only external dependencies are doubles.
    let engine = AXWindowEngine()
    let dragMonitor = Probe("drag"), keyboardMonitor = Probe("key")
    let observer = Probe("window"), appFocusObserver = Probe("focus"), windowCreationObserver = Probe("creation")
    var isStopping = false
    var isApplyingLayout = false
    var groups: [TabGroup] = []
    weak var mostRecentGroup: TabGroup?
    var draggedWindow: ManagedWindow?
    func endTrackingActiveMove() { Trace.add("tracking.stop") }
    func resetDragState() { draggedWindow = nil; Trace.add("drag.reset") }
    func applyLayout(for group: TabGroup) { Trace.add("layout") }
    func updateFocusObservers() { Trace.add("focus.update") }
    func isGroupOnActiveSpace(_ group: TabGroup) -> Bool { true }
    func syncPanelZOrderWithFrontmostGroupSoon() { Trace.add("zorder") }
    func positionPanel(for group: TabGroup) { Trace.add("panel.position") }
    func beginTrackingActiveMove(for group: TabGroup) { Trace.add("tracking.start") }
    func group(containing id: UInt32) -> TabGroup? { groups.first { $0.windows.contains { $0.id == id } } }
}
