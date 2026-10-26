import AppKit
import SwiftUI

/// Borderless non-activating panel for one group's tab strip.
final class TabBarPanel: NSPanel {
    let model: TabGroupViewModel

    var onFrameChanged: (() -> Void)?
    var onMouseUp: (() -> Void)?
    private var waitForPointerExit = false
    private var isCompact = false
    private var restingFrame: CGRect = .zero
    private var expandedFrame: CGRect = .zero

    /// Grace margin around the expanded bar before compact mode collapses.
    private let collapseSafeZoneX: CGFloat = 28
    private let collapseSafeZoneY: CGFloat = 72
    private var collapseWatcher: Timer?
    private var expansionTimer: Timer?
    private var hoverExpansionDelay: TimeInterval = 0
    private var isPointerHovering = false

    /// AppKit hover tracking for the non-activating panel.
    private let trackingContainer: HoverTrackingView

    init(model: TabGroupViewModel) {
        self.model = model
        self.trackingContainer = HoverTrackingView()
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: Theme.stripHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = false
        level = .normal
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]

        let host = NSHostingView(rootView: TabStripView(model: model)
            .environment(\.colorScheme, .dark))
        host.translatesAutoresizingMaskIntoConstraints = false
        trackingContainer.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: trackingContainer.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trackingContainer.trailingAnchor),
            host.topAnchor.constraint(equalTo: trackingContainer.topAnchor),
            host.bottomAnchor.constraint(equalTo: trackingContainer.bottomAnchor)
        ])
        contentView = trackingContainer

        trackingContainer.onHoverChange = { [weak self] hovering in
            self?.handleHover(hovering)
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        // Deliver tab clicks normally before notifying the gesture observer.
        super.sendEvent(event)
        if event.type == .leftMouseUp { onMouseUp?() }
    }

    func place(at frame: CGRect) {
        setFrame(frame, display: true)
    }

    /// Configure resting and expanded frames for the current layout.
    func applyLayout(compact: Bool, resting: CGRect, expanded: CGRect,
                     hoverExpansionDelay: TimeInterval = 0) {
        if isCompact != compact || self.hoverExpansionDelay != hoverExpansionDelay {
            cancelPendingExpansion()
            cancelCollapseWatch()
            isPointerHovering = false
            model.hovered = false
            waitForPointerExit = false
        }
        self.hoverExpansionDelay = hoverExpansionDelay
        isCompact = compact
        restingFrame = resting
        expandedFrame = expanded
        if !compact {
            cancelCollapseWatch()
            waitForPointerExit = false
            model.hovered = false
        }
        let target = (compact && model.hovered) ? expanded : resting
        setFrame(target, display: true)
        onFrameChanged?()
    }

    private func handleHover(_ hovering: Bool) {
        isPointerHovering = hovering
        cancelPendingExpansion()
        guard isCompact else { return }
        if hovering {
            guard !waitForPointerExit else { return }
            cancelCollapseWatch()
            guard !model.hovered else { return }
            if hoverExpansionDelay > 0 {
                let timer = Timer(timeInterval: hoverExpansionDelay, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.expandAfterHoverDelay() }
                }
                expansionTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            } else {
                setExpanded(true)
            }
        } else {
            waitForPointerExit = false
            beginCollapseWatch()
        }
    }

    private func expandAfterHoverDelay() {
        expansionTimer = nil
        guard isCompact, isPointerHovering, isVisible, !waitForPointerExit,
              restingFrame.contains(NSEvent.mouseLocation) else { return }
        setExpanded(true)
    }

    private func cancelPendingExpansion() {
        expansionTimer?.invalidate()
        expansionTimer = nil
    }

    private func setExpanded(_ expanded: Bool) {
        model.hovered = expanded
        let target = expanded ? expandedFrame : restingFrame
        // A delayed animation must not overwrite a newer selection/layout.
        setFrame(target, display: true)
        onFrameChanged?()
    }

    func collapseAfterSelection() {
        // Direct compact-icon selection keeps its current hover deadline.
        guard isCompact, model.hovered else { return }
        cancelPendingExpansion()
        cancelCollapseWatch()
        waitForPointerExit = true
        setExpanded(false)
        // Frame changes can suppress mouseExited; poll the resting frame too.
        beginCollapseWatch()
    }

    private func beginCollapseWatch() {
        cancelCollapseWatch()
        collapseWatcher = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickCollapseWatch() }
        }
    }

    private func tickCollapseWatch() {
        if waitForPointerExit {
            if !restingFrame.contains(NSEvent.mouseLocation) {
                waitForPointerExit = false
                cancelCollapseWatch()
            }
            return
        }
        let safe = expandedFrame.insetBy(dx: -collapseSafeZoneX, dy: -collapseSafeZoneY)
        if !safe.contains(NSEvent.mouseLocation) {
            cancelCollapseWatch()
            setExpanded(false)
        }
    }

    private func cancelCollapseWatch() {
        collapseWatcher?.invalidate()
        collapseWatcher = nil
    }

    func show() {
        appearance = NSAppearance(named: .darkAqua)
        if !isVisible {
            orderFront(nil)
        }
    }

    func hide(animated: Bool = true) {
        let previousAnimation = animationBehavior
        if !animated { animationBehavior = .none }
        defer { animationBehavior = previousAnimation }
        cancelCollapseWatch()
        cancelPendingExpansion()
        isPointerHovering = false
        orderOut(nil)
    }
}

/// NSView-backed hover reporting for non-activating panels.
final class HoverTrackingView: NSView {
    var onHoverChange: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
    }
}
