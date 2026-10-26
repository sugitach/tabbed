import AppKit
import ApplicationServices

/// Coordinates drag gestures, real windows, and floating tab strips.
@MainActor
final class TabGroupController: NSObject, DragMonitorDelegate {
    let engine: WindowEngine
    private lazy var dragMonitor: DragMonitor = {
        let m = DragMonitor(engine: engine)
        m.delegate = self
        m.onMouseInteraction = { [weak self] in self?.mouseInteractionDidOccur() }
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

    let sessionStore: GroupSessionStore
    var sessionForTermination: GroupSession?
    var didRestoreSession = false
    var sessionInteractionGeneration = 0
    var pendingSessionGroups: [SavedWindowGroup] = []
    var pendingSessionGeneration = 0

    var panelZOrderSyncGeneration = 0

    var activeMoveTimer: Timer?
    weak var activeMoveGroup: TabGroup?
    // Diagnostic origin only; does not change which window the existing tracker reads.
    var activeMoveOriginWindowID: WindowID?
    var activeMoveDeadline: Date = .distantPast
    var windowLifecycleTimer: Timer?

    init(engine: WindowEngine, sessionStore: GroupSessionStore = .standard) {
        self.engine = engine
        self.sessionStore = sessionStore
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
        restoreSavedGroups()
        return true
    }

    func recordInputMonitoringDiagnostics() {
        dragMonitor.recordMonitoringDiagnostics()
    }

    /// Re-read `~/.config/tabbed.toml` and apply any keyboard-shortcut changes.
    func reloadConfig() {
        guard !isStopping else { return }
        config = TabbedConfig.load()
        keyboardMonitor.apply(settings: config.shortcuts)
    }

    /// Idempotent: a cancelled Quit stays stopped; the next Quit retries restoration.
    func restoreWindowsForTermination() -> [ManagedWindow] {
        captureSessionForTermination()
        isStopping = true
        stopWindowLifecycleMonitoring()
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
            group.windows.enumerated().map { index, window in
                (window, WindowRestoration.ungroupedFrame(group.contentFrame, index: index))
            }
        }
        WindowDiagnostics.record(.init(event: .terminationRestoreBegin,
            memberIDs: entries.map { $0.0.id }))
        let failures = WindowRestoration.restore(
            entries, screens: NSScreen.screens.map(\.visibleFrame),
            isAlive: { !self.engine.isKnownClosed($0) },
            move: { self.engine.restoreFrame($1, of: $0) }
        )
        WindowDiagnostics.record(.init(event: .terminationRestoreResult,
            memberIDs: failures.map(\.id)))
        if failures.isEmpty {
            groups.removeAll()
            mostRecentGroup = nil
        }
        return failures
    }

    // MARK: - DragMonitorDelegate

    func dragDidBegin(window: ManagedWindow?, at point: CGPoint) {
        sessionInteractionGeneration &+= 1
        guard !isStopping else { return }
        guard let window else { return }
        draggedWindow = window
        if let group = group(containing: window.id), group.activeWindow?.id == window.id {
            beginTrackingActiveMove(for: group)
            if let frame = engine.windowServerFrame(of: window.id) {
                adoptTrackedFrame(frame, for: group)
            }
        }
        if let frame = engine.frame(of: window) {
            draggedSize = frame.size
            dragGrabOffset = CGSize(width: point.x - frame.minX, height: point.y - frame.minY)
        } else {
            draggedSize = nil
            dragGrabOffset = .zero
        }
        dragTargets = engine.onScreenWindowFrames(excluding: [window.id])
    }

    func dragDidMove(to point: CGPoint) {
        guard !isStopping else { return }
        guard draggedWindow != nil else { return }
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
                // A native drag moves the whole stack; ungrouping remains an
                // explicit tab action, including a drop outside any target.
                if let frame = self.engine.windowServerFrame(of: dragged.id) {
                    sourceGroup.contentFrame = frame
                    self.positionPanel(for: sourceGroup)
                }
            }
        }
    }

    func dragDidCancel() {
        resetDragState()
    }

    func dragDidEndWithoutGrouping(at point: CGPoint) {
        guard !isStopping else { return }
        resetDragState()
    }

    func dragGroupingDidCancel() {
        // Continue moving the dragged window, but never offer a drop target
        // again during this gesture, even if Command is pressed again.
        dragTargets = []
        dropIndicator.dismiss()
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

        let source = group(containing: dragged.id)
        let existing = group(containing: target.id)
        // Dropping onto another member of the same group changes nothing.
        if let source, source === existing { return }
        let incoming = source?.windows ?? [dragged]
        let targetSpace = engine.spaceID(of: target)
        for window in incoming {
            if let windowSpace = engine.spaceID(of: window),
               let targetSpace, windowSpace != targetSpace {
                engine.move(window, toSpaceOf: target)
            }
        }

        // Transfer the group atomically. remove()/dissolve() would restore or
        // re-layout its remaining windows midway through the transfer.
        if let source {
            if activeMoveGroup === source { endTrackingActiveMove(restorePanel: false) }
            source.panel.hide()
            groups.removeAll { $0 === source }
            source.windows = []
        }

        let destination: TabGroup
        if let existing {
            destination = existing
            destination.contentFrame = targetFrame
            destination.spaceID = targetSpace
            for window in incoming where !destination.contains(window.id) {
                destination.windows.append(window)
            }
            destination.activeIndex = destination.windows.firstIndex { $0.id == dragged.id } ?? destination.activeIndex
        } else {
            destination = TabGroup(
                windows: [target] + incoming,
                activeIndex: 1 + (incoming.firstIndex { $0.id == dragged.id } ?? 0),
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

    func wire(_ group: TabGroup) {
        group.panel.onMouseUp = { [weak self] in
            self?.dragMonitor.ownPanelMouseUp()
        }
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
