import Foundation
import CoreGraphics

// Deliberate test doubles. No AppKit/ApplicationServices import or OS window access.
typealias WindowID = UInt32
enum SimulatedAXError: Int32 { case success, invalidUIElement, cannotComplete, apiDisabled, failure, notImplemented }
@MainActor enum Trace {
    static var events: [String] = []
    static func add(_ event: String) { events.append(event) }
}
@MainActor final class AXUIElement {
    let id: UInt32
    var resolved: UInt32
    var errors: [SimulatedAXError] = []
    var queries = 0
    var standardWindow = true
    var attributes: [String: AXUIElement] = [:]
    static var applications: [Int32: AXUIElement] = [:]
    init(_ id: UInt32) { self.id = id; self.resolved = id }
}
@MainActor func AXUIElementCreateApplication(_ pid: Int32) -> AXUIElement {
    if let existing = AXUIElement.applications[pid] { return existing }
    let app = AXUIElement(0); app.standardWindow = false
    AXUIElement.applications[pid] = app
    return app
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
    init(_ id: UInt32, pid: Int32? = nil) {
        self.id = id; self.pid = pid ?? 100 + Int32(id); element = AXUIElement(id)
        NSRunningApplication.terminated[self.pid] = false
    }
}
@MainActor final class Probe {
    let name: String
    var delegate: AnyObject?
    var onEvent: (() -> Void)? = {}
    var unobserved: [UInt32] = []
    var startResult = true
    var startCalls = 0
    init(_ name: String) { self.name = name }
    func start() -> Bool { startCalls += 1; return startResult }
    func stop() { Trace.add(name + ".stop") }
    func unobserve(_ id: UInt32) { unobserved.append(id) }
    func unobserveAll() { Trace.add(name + ".unobserveAll") }
}
@MainActor final class Panel {
    func hide() { Trace.add("panel.hide") }
}
@MainActor final class TabGroup {
    let id = UUID()
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
    let ownPID: Int32 = 999
    var availableWindows: [ManagedWindow] = []
    var visibleWindows: Set<WindowID> = []
    func copyAXElementAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        element.attributes[attribute]
    }
    func isStandardWindow(_ element: AXUIElement) -> Bool { element.standardWindow }
    func managedWindow(from element: AXUIElement, pid: Int32) -> ManagedWindow? {
        availableWindows.first { $0.pid == pid && $0.element === element && element.standardWindow }
    }
    func onScreenWindowFrames(excluding: Set<WindowID>) -> [WindowFrame] {
        availableWindows.filter { visibleWindows.contains($0.id) && !excluding.contains($0.id) }
            .map { WindowFrame(id: $0.id) }
    }
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
struct WindowFrame { let id: WindowID }
@MainActor enum NSEvent { static var pressedMouseButtons = 0 }
// Run the production retry callbacks deterministically, without a GUI run loop.
@MainActor enum DispatchQueue {
    static let main = ScheduledCallbacks()
    @MainActor final class ScheduledCallbacks {
        var pending: [() -> Void] = []
        func asyncAfter(deadline: DispatchTime, execute: @escaping () -> Void) { pending.append(execute) }
        func runNext() { if !pending.isEmpty { pending.removeFirst()() } }
    }
}
@MainActor struct NSScreen {
    let visibleFrame: CGRect
    static var screens = [NSScreen(visibleFrame: CGRect(x: 0, y: 24, width: 1000, height: 700))]
}
@MainActor final class NSWorkspace {
    static let shared = NSWorkspace()
    let notificationCenter = Center()
    var shownApps: [URL] = []
    func activateFileViewerSelecting(_ urls: [URL]) { shownApps += urls }
    @MainActor final class Center {
        func removeObserver(_ object: AnyObject) { Trace.add("workspace.removeObserver") }
    }
}
let kAXUIElementDestroyedNotification = "destroyed"
let kAXWindowMiniaturizedNotification = "minimized"
let kAXMovedNotification = "moved"
let kAXResizedNotification = "resized"
let kAXFocusedWindowAttribute = "focusedWindow"
let kAXMainWindowAttribute = "mainWindow"
let kAXWindowAttribute = "window"

// Only the optional normal-termination callbacks are modeled. No real app or UI.
@MainActor final class NSApplication {
    enum TerminateReply { case terminateNow, terminateCancel }
    enum ModalResponse { case alertFirstButtonReturn, alertSecondButtonReturn, alertThirdButtonReturn, abort }
}
@MainActor final class NSAlert {
    struct Presentation {
        let message: String
        let information: String
        let buttons: [String]
    }
    static var presentations: [Presentation] = []
    static var responses: [NSApplication.ModalResponse] = []
    var messageText = ""
    var informativeText = ""
    var buttons: [String] = []
    func addButton(withTitle title: String) { buttons.append(title) }
    @discardableResult func runModal() -> NSApplication.ModalResponse {
        Self.presentations.append(Presentation(message: messageText, information: informativeText, buttons: buttons))
        return Self.responses.isEmpty ? .alertFirstButtonReturn : Self.responses.removeFirst()
    }
}
@MainActor final class AppDelegate {
    let controller: TabGroupController
    var quitWithoutRestoring = false
    var monitoringStarted = false
    var nextMonitoringAttempt = Date.distantPast
    var permissionTimer: Timer?
    var monitoringStatus = ""
    var monitoringActive = false
    var appBundleURL = URL(fileURLWithPath: "/Regression Fixture/Tabbed Dev.app")
    var settingsRequests = 0
#if HAS_PERMISSION_HELP
    var codeSignature = AppCodeSignature(isAdHoc: true, validationSucceeded: true)
#endif
    init(controller: TabGroupController) { self.controller = controller }
    // UI presentation is a boundary double; startup decisions come from source.
    func showMonitoringStatus(_ title: String, active: Bool) {
        monitoringStatus = title; monitoringActive = active
    }
    func refreshStartup(now: Date) {
#if HAS_PERMISSION_STARTUP
        refreshAccessibilityStartup(now: now)
#endif
    }
    func openAXSettings() { settingsRequests += 1 }
    func presentPermissionHelp() {
#if HAS_PERMISSION_HELP
        showAccessibilityHelp()
#endif
    }
}
@MainActor enum AccessibilityPermission { static var trusted = false }
@MainActor func AXIsProcessTrusted() -> Bool { AccessibilityPermission.trusted }
@MainActor func requestNormalQuit(_ controller: TabGroupController, delegate supplied: AppDelegate? = nil) -> NSApplication.TerminateReply {
    let delegate = supplied ?? AppDelegate(controller: controller)
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
    var isStarted = false
    var startupObservers: [String] = []
    func observeSpaceChanges() { startupObservers.append("space") }
    func observeApplicationChanges() { startupObservers.append("application") }
    func observeRunningAppsForWindowCreation() { startupObservers.append("creation") }
    func startForTest() -> Bool {
#if HAS_MONITORING_START_RESULT
        return start()
#else
        start()
        return false // Missing readiness contract must fail, not fake success.
#endif
    }
    var isApplyingLayout = false
    var groups: [TabGroup] = []
    weak var mostRecentGroup: TabGroup?
    var draggedWindow: ManagedWindow?
    let ownPID: Int32 = 999
    var autoAddNewWindowsToStack = true
    var addedWindows: [WindowID] = []
    func frontmostGroup() -> TabGroup? { nil }
    func add(_ window: ManagedWindow, to group: TabGroup) {
        addedWindows.append(window.id); group.windows.append(window)
    }
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
