import Foundation
import CoreGraphics

typealias WindowID = UInt32
@MainActor final class NSRunningApplication {
    static var apps: [Int32: NSRunningApplication] = [:]
    let launchDate: Date?
    let bundleIdentifier: String?
    var isTerminated = false
    init(_ time: Double, _ bundle: String = "test.app") {
        launchDate = Date(timeIntervalSince1970: time); bundleIdentifier = bundle
    }
    convenience init?(processIdentifier: Int32) {
        guard let app = Self.apps[processIdentifier], !app.isTerminated else { return nil }
        self.init(app.launchDate!.timeIntervalSince1970, app.bundleIdentifier!)
    }
}
struct Screen { let visibleFrame = CGRect(x: 0, y: 0, width: 2000, height: 1200) }
enum NSScreen { static let screens = [Screen()] }
@MainActor final class ManagedWindow {
    let id: WindowID; let pid: Int32
    init(_ id: WindowID, _ pid: Int32 = 100) { self.id = id; self.pid = pid }
}
@MainActor final class TabGroup {
    var displayLayouts = DisplayLayoutHistory()
    var windows: [ManagedWindow]; var activeIndex: Int; var contentFrame: CGRect; var spaceID: UInt64?
    init(windows: [ManagedWindow], activeIndex: Int, contentFrame: CGRect, spaceID: UInt64?) {
        self.windows = windows; self.activeIndex = activeIndex; self.contentFrame = contentFrame; self.spaceID = spaceID
    }
    var activeWindow: ManagedWindow? { windows.indices.contains(activeIndex) ? windows[activeIndex] : nil }
}
@MainActor final class Engine {
    var windows: [WindowID: ManagedWindow] = [:]
    var spaces: [WindowID: UInt64] = [:]
    var frames: [WindowID: CGRect] = [:]
    func frame(of window: ManagedWindow) -> CGRect? { frames[window.id] }
    func windowServerFrame(of id: WindowID) -> CGRect? { nil }
    func existingWindow(id: WindowID, pid: Int32) -> ManagedWindow? {
        guard let w = windows[id], w.pid == pid else { return nil }; return w
    }
    func spaceID(of window: ManagedWindow) -> UInt64? { spaces[window.id] ?? 1 }
}
@MainActor final class TabGroupController {
    let engine = Engine()
    let sessionStore: GroupSessionStore
    var sessionForTermination: GroupSession?
    var didRestoreSession = false, isStopping = false, isStarted = true
    var sessionInteractionGeneration = 0
    var pendingSessionGroups: [SavedWindowGroup] = []
    var pendingSessionGeneration = 0
    var displayTransitionPending = false
    var currentDisplayConfiguration: String?
    var groups: [TabGroup] = []
    var wired = 0, observed = 0, layouts = 0
    init(_ store: GroupSessionStore) { sessionStore = store }
    func group(containing id: WindowID) -> TabGroup? { groups.first { $0.windows.contains { $0.id == id } } }
    func wire(_ group: TabGroup) { wired += 1 }
    func observeWindows(in group: TabGroup) { observed += 1 }
    func updateFocusObservers() {}
    func applyLayout(for group: TabGroup) { layouts += 1 }
}

extension TabGroupController {
    func deferDisplayLayout() -> Bool { displayTransitionPending }
    func rememberDisplayLayouts() {}
}
