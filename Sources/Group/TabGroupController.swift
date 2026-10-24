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

    var groups: [TabGroup] = []
    var autoAddNewWindowsToStack = AppSettings.autoAddNewWindowsToStack
    var alwaysUseCompactMode = AppSettings.alwaysUseCompactMode

    var draggedWindow: ManagedWindow?
    private var draggedSize: CGSize?
    private var dragGrabOffset: CGSize = .zero
    private var dragTargets: [WindowFrame] = []
    var isApplyingLayout = false
    weak var mostRecentGroup: TabGroup?

    var panelZOrderSyncGeneration = 0

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
        guard dragMonitor.start() else { return false }
        keyboardMonitor.start()
        observeSpaceChanges()
        observeApplicationChanges()
        if autoAddNewWindowsToStack {
            observeRunningAppsForWindowCreation()
        }
        return true
    }

    func recordInputMonitoringDiagnostics() {
        dragMonitor.recordMonitoringDiagnostics()
    }

    /// Re-read `~/.config/tabbed.toml` and apply any keyboard-shortcut changes.
    func reloadConfig() {
        config = TabbedConfig.load()
        keyboardMonitor.apply(settings: config.shortcuts)
    }

    // MARK: - DragMonitorDelegate

    func dragDidBegin(window: ManagedWindow?, at point: CGPoint) {
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
        guard draggedWindow != nil else { return }
        if let hit = dragTargets.first(where: { $0.frame.contains(point) }) {
            dropIndicator.present(over: hit.frame)
        } else {
            dropIndicator.dismiss()
        }
    }

    func dragDidEnd(at point: CGPoint) {
        let dragged = draggedWindow
        resetDragState()
        DispatchQueue.main.async { [weak self] in
            guard let self, let dragged else { return }
            if let target = self.engine.window(at: point, excluding: [dragged.id]) {
                self.formGroup(dragged: dragged, target: target)
            } else if let sourceGroup = self.group(containing: dragged.id) {
                // A native drag moves the whole stack; an outside drop keeps it intact.
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

    func dragGroupingDidCancel() {
        // Continue moving the dragged window, but never offer a drop target
        // again during this gesture, even if Command is pressed again.
        dragTargets = []
        dropIndicator.dismiss()
    }

    func dragDidEndWithoutGrouping(at point: CGPoint) {
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

    private func wire(_ group: TabGroup) {
        group.panel.onMouseUp = { [weak self] in
            self?.dragMonitor.ownPanelMouseUp()
        }
        group.viewModel.onSelect = { [weak self, weak group] id in
            guard let self, let group else { return }
            self.selectTab(id, in: group)
        }
        group.viewModel.onClose = { [weak self, weak group] id in
            guard let self, let group else { return }
            self.untab(id, from: group)
        }
        group.viewModel.onActivateActive = { [weak self, weak group] in
            guard let self, let group, let active = group.activeWindow else { return }
            self.selectTab(active.id, in: group)
        }
        group.viewModel.onMoveBegan = { [weak group] in
            group?.moveAnchorFrame = group?.contentFrame
        }
        group.viewModel.onMoveChanged = { [weak self, weak group] translation in
            guard let self, let group, let anchor = group.moveAnchorFrame else { return }
            group.contentFrame = anchor.offsetBy(dx: translation.width, dy: translation.height)
            self.positionPanel(for: group)
            if let active = group.activeWindow {
                self.engine.setFrame(group.contentFrame, of: active)
            }
        }
        group.viewModel.onMoveEnded = { [weak self, weak group] in
            guard let self, let group else { return }
            group.moveAnchorFrame = nil
            self.applyLayout(for: group)
        }
    }

    func group(containing id: WindowID) -> TabGroup? {
        groups.first { $0.contains(id) }
    }
}
