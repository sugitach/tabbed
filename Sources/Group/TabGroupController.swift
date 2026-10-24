import AppKit
import ApplicationServices

/// Coordinates drag gestures, real windows, and floating tab strips.
@MainActor
final class TabGroupController: NSObject, DragMonitorDelegate {
    let engine: WindowEngine
    private lazy var dragMonitor: DragMonitor = {
        let m = DragMonitor(engine: engine)
        m.delegate = self
        return m
    }()

    let observer = AXObserverBridge()
    let appFocusObserver = AXAppObserverBridge()
    let windowCreationObserver = AXAppObserverBridge()
    private let dropIndicator = DropIndicatorPanel()
    let ownPID = ProcessInfo.processInfo.processIdentifier

    var config = TabbedConfig.load()
    lazy var keyboardMonitor: KeyboardShortcutMonitor = {
        let monitor = KeyboardShortcutMonitor(settings: config.shortcuts)
        monitor.delegate = self
        return monitor
    }()

    private(set) var isStopping = false
    private(set) var isStarted = false
    var groups: [TabGroup] = []
    var autoAddNewWindowsToStack = AppSettings.autoAddNewWindowsToStack
    var alwaysUseCompactMode = AppSettings.alwaysUseCompactMode

    var draggedWindow: ManagedWindow?
    private var draggedSize: CGSize?
    private var dragGrabOffset: CGSize = .zero
    private var dragTargets: [WindowFrame] = []
    var isApplyingLayout = false
    weak var mostRecentGroup: TabGroup?

    var activeMoveTimer: Timer?
    weak var activeMoveGroup: TabGroup?
    // Diagnostic origin only; does not change which window the existing tracker reads.
    var activeMoveOriginWindowID: WindowID?
    var activeMoveDeadline: Date = .distantPast

    init(engine: WindowEngine) {
        self.engine = engine
        super.init()
        observer.onEvent = { [weak self] id, notification in
            self?.handleWindowNotification(id: id, notification: notification)
        }
        appFocusObserver.onEvent = { [weak self] _, _, _ in
            self?.syncPanelZOrderWithFrontmostGroupSoon()
        }
        windowCreationObserver.onEvent = { [weak self] pid, notification, element in
            guard notification == kAXWindowCreatedNotification else { return }
            self?.handleWindowCreated(pid: pid, element: element)
        }
    }

    @discardableResult
    func start() -> Bool {
        guard !isStopping else { return false }
        guard !isStarted else { return true }
        guard dragMonitor.start(), keyboardMonitor.start() else {
            // Do not leave a partially active controller while awaiting access.
            dragMonitor.stop()
            keyboardMonitor.stop()
            return false
        }
        observeSpaceChanges()
        observeApplicationChanges()
        if autoAddNewWindowsToStack {
            observeRunningAppsForWindowCreation()
        }
        isStarted = true
        return true
    }

    /// Re-read `~/.config/tabbed.toml` and apply any keyboard-shortcut changes.
    func reloadConfig() {
        guard !isStopping else { return }
        config = TabbedConfig.load()
        keyboardMonitor.apply(settings: config.shortcuts)
    }

    /// Idempotent: a cancelled Quit stays stopped; the next Quit retries restoration.
    func restoreWindowsForTermination() -> [ManagedWindow] {
        isStopping = true
        dragMonitor.stop()
        dragMonitor.delegate = nil
        keyboardMonitor.stop()
        keyboardMonitor.delegate = nil
        endTrackingActiveMove()
        resetDragState()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        observer.onEvent = nil
        appFocusObserver.onEvent = nil
        windowCreationObserver.onEvent = nil
        observer.unobserveAll()
        appFocusObserver.unobserveAll()
        windowCreationObserver.unobserveAll()

        // Snapshot all groups before any restoration; do not dissolve while iterating.
        let snapshot = groups
        for group in snapshot { group.panel.hide() }
        let entries = snapshot.flatMap { group in
            group.windows.map { ($0, group.contentFrame) }
        }
        let failures = WindowRestoration.restore(
            entries, screens: NSScreen.screens.map(\.visibleFrame),
            isAlive: { !self.engine.isKnownClosed($0) },
            move: { self.engine.restoreFrame($1, of: $0) }
        )
        if failures.isEmpty {
            groups.removeAll()
            mostRecentGroup = nil
        }
        return failures
    }

    // MARK: - DragMonitorDelegate

    func dragDidBegin(window: ManagedWindow?, at point: CGPoint) {
        guard !isStopping else { return }
        guard let window else { return }
        draggedWindow = window
        if let frame = engine.frame(of: window) {
            draggedSize = frame.size
            dragGrabOffset = CGSize(width: point.x - frame.minX, height: point.y - frame.minY)
        } else {
            draggedSize = nil
            dragGrabOffset = .zero
        }
        dragTargets = engine.onScreenWindowFrames(excluding: [window.id])
        engine.raise(window)
    }

    func dragDidMove(to point: CGPoint) {
        guard !isStopping else { return }
        guard let dragged = draggedWindow else { return }
        if let size = draggedSize {
            let origin = CGPoint(x: point.x - dragGrabOffset.width,
                                 y: point.y - dragGrabOffset.height)
            engine.setFrame(CGRect(origin: origin, size: size), of: dragged)
        }
        if let hit = dragTargets.first(where: { $0.frame.contains(point) }) {
            dropIndicator.present(over: hit.frame)
        } else {
            dropIndicator.dismiss()
        }
    }

    func dragDidEnd(at point: CGPoint) {
        guard !isStopping else { return }
        let dragged = draggedWindow
        resetDragState()
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isStopping, let dragged else { return }
            if let target = self.engine.window(at: point, excluding: [dragged.id]) {
                self.formGroup(dragged: dragged, target: target)
            } else if let sourceGroup = self.group(containing: dragged.id) {
                self.remove(dragged.id, from: sourceGroup, keepWindowObserved: false)
                self.engine.activate(dragged)
            }
        }
    }

    func dragDidCancel() {
        resetDragState()
    }

    private func resetDragState() {
        draggedWindow = nil
        draggedSize = nil
        dragTargets = []
        dropIndicator.dismiss()
    }

    // MARK: - Core action

    /// Tab `dragged` onto `target`, preserving the target frame.
    func formGroup(dragged: ManagedWindow, target: ManagedWindow, knownFrame: CGRect? = nil) {
        guard !isStopping else { return }
        guard dragged.id != target.id,
              let targetFrame = knownFrame ?? engine.frame(of: target) else {
            return
        }

        let targetSpace = engine.spaceID(of: target)
        if let draggedSpace = engine.spaceID(of: dragged),
           let targetSpace,
           draggedSpace != targetSpace {
            engine.move(dragged, toSpaceOf: target)
        }

        if let sourceGroup = group(containing: dragged.id), !sourceGroup.contains(target.id) {
            remove(dragged.id, from: sourceGroup, keepWindowObserved: true)
        }

        engine.setFrame(targetFrame, of: dragged)

        let destination: TabGroup
        if let existing = group(containing: target.id) {
            destination = existing
            destination.contentFrame = targetFrame
            destination.spaceID = targetSpace
            if !destination.contains(dragged.id) {
                destination.windows.append(dragged)
            }
            destination.activeIndex = destination.windows.firstIndex { $0.id == dragged.id } ?? destination.activeIndex
        } else {
            destination = TabGroup(
                windows: [target, dragged],
                activeIndex: 1,
                contentFrame: targetFrame,
                spaceID: targetSpace
            )
            wire(destination)
            groups.append(destination)
        }

        observeWindows(in: destination)
        markRecentlyUsed(destination)
        updateFocusObservers()
        applyLayout(for: destination)
    }

    private func wire(_ group: TabGroup) {
        group.viewModel.onSelect = { [weak self, weak group] id in
            guard let self, !self.isStopping, let group else { return }
            self.selectTab(id, in: group)
        }
        group.viewModel.onClose = { [weak self, weak group] id in
            guard let self, !self.isStopping, let group else { return }
            self.untab(id, from: group)
        }
        group.viewModel.onActivateActive = { [weak self, weak group] in
            guard let self, !self.isStopping, let group, let active = group.activeWindow else { return }
            self.selectTab(active.id, in: group)
        }
        group.viewModel.onMoveBegan = { [weak group] in
            group?.moveAnchorFrame = group?.contentFrame
        }
        group.viewModel.onMoveChanged = { [weak self, weak group] translation in
            guard let self, !self.isStopping, let group, let anchor = group.moveAnchorFrame else { return }
            group.contentFrame = anchor.offsetBy(dx: translation.width, dy: translation.height)
            self.positionPanel(for: group)
            if let active = group.activeWindow {
                self.engine.setFrame(group.contentFrame, of: active)
            }
        }
        group.viewModel.onMoveEnded = { [weak self, weak group] in
            guard let self, !self.isStopping, let group else { return }
            group.moveAnchorFrame = nil
            self.applyLayout(for: group)
        }
    }

    func group(containing id: WindowID) -> TabGroup? {
        groups.first { $0.contains(id) }
    }
}
