import AppKit
import CoreGraphics

/// Reports a Command-drag window gesture.
@MainActor
protocol DragMonitorDelegate: AnyObject {
    func dragDidBegin(window: ManagedWindow?, at point: CGPoint)
    func dragDidMove(to point: CGPoint)
    func dragDidEnd(at point: CGPoint)
    func dragDidCancel()
    func dragGroupingDidCancel()
    func dragDidEndWithoutGrouping(at point: CGPoint)
}

/// Observes asynchronous copies of other apps' mouse/modifier events.
/// The handler cannot change, suppress, or repost the original input.
@MainActor
final class DragMonitor {
    weak var delegate: DragMonitorDelegate?
    var onMouseInteraction: (() -> Void)?
    private let engine: WindowEngine
    private var eventMonitor: Any?
    private var observerGeneration: UInt64 = 0
    private var startupDeliveryTimer: Timer?
    private var startupChecks = 0
    private var startupReinstallCount = 0
    private var hasReceivedMouseEvent = false
    private var candidateWindow: ManagedWindow?
    private var initialFrame: CGRect?
    private var isObservingDrag = false
    private var commandIsHeld = false
    private var hasDragged = false
    private var downPoint: CGPoint = .zero
    private static let dragThreshold: CGFloat = 6

    init(engine: WindowEngine) {
        self.engine = engine
    }

    @discardableResult
    func start() -> Bool {
        guard eventMonitor == nil else { return true }
        startupChecks = 0
        startupReinstallCount = 0
        hasReceivedMouseEvent = false
        guard installObserver() else { return false }
        // A non-nil monitor token does not prove delivery after a fresh grant.
        // Retry twice while idle, without requiring a menu or diagnostic action.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkInitialEventDelivery() }
        }
        startupDeliveryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .modalPanel)
        recordMonitoringDiagnostics()
        return true
    }

    private func installObserver() -> Bool {
        let generation = observerGeneration &+ 1
        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged
        ]
        guard let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.observerGeneration == generation, self.eventMonitor != nil else { return }
                if event.type != .flagsChanged {
                    self.hasReceivedMouseEvent = true
                    self.startupDeliveryTimer?.invalidate()
                    self.startupDeliveryTimer = nil
                }
                let point = event.cgEvent.map { CoordinateConverter.appKitPoint(fromCG: $0.location) }
                    ?? NSEvent.mouseLocation
                self.handle(type: event.type, point: point,
                    commandIsDown: event.modifierFlags.contains(.command),
                    leftButtonIsDown: NSEvent.pressedMouseButtons & 1 != 0)
            }
        }) else {
            NSLog("[DragMonitor] failed to install global event observer")
            return false
        }
        let previous = eventMonitor
        observerGeneration = generation
        eventMonitor = monitor
        if let previous { NSEvent.removeMonitor(previous) }
        return true
    }

    private func checkInitialEventDelivery() {
        guard startupDeliveryTimer != nil, !hasReceivedMouseEvent else { return }
        // Never replace an observer in the middle of a physical mouse gesture.
        guard NSEvent.pressedMouseButtons == 0 else { return }
        startupChecks += 1
        guard startupChecks >= 2 else { return }
        startupChecks = 0
        startupReinstallCount += 1
        _ = installObserver()
        if startupReinstallCount >= 2 {
            startupDeliveryTimer?.invalidate()
            startupDeliveryTimer = nil
        }
        recordMonitoringDiagnostics()
    }

    func recordMonitoringDiagnostics() {
        WindowDiagnostics.record(.init(event: .inputMonitoringState,
            observerInstalled: eventMonitor != nil, receivedMouseEvent: hasReceivedMouseEvent,
            startupReinstallCount: startupReinstallCount,
            gestureCandidateFound: candidateWindow != nil))
    }

    func stop() {
        startupDeliveryTimer?.invalidate()
        startupDeliveryTimer = nil
        observerGeneration &+= 1
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        resetGesture()
    }

    /// Own panels receive normal AppKit input, outside the global observer.
    /// A mouse release there ends any pending gesture without creating a group.
    func ownPanelMouseUp() {
        if isObservingDrag { delegate?.dragDidCancel() }
        resetGesture()
        onMouseInteraction?()
    }

    private func resetGesture() {
        candidateWindow = nil
        initialFrame = nil
        isObservingDrag = false
        commandIsHeld = false
        hasDragged = false
    }

    // Observe native movement only. Every physical event remains with the app;
    // neither a guessed title-bar rectangle nor synthetic input is needed.
    private func handle(type: NSEvent.EventType, point: CGPoint,
                        commandIsDown: Bool, leftButtonIsDown: Bool) {
        switch type {
        case .leftMouseDown:
            onMouseInteraction?()
            if isObservingDrag { delegate?.dragDidCancel() }
            resetGesture()
            downPoint = point
            commandIsHeld = commandIsDown
            // Capture native movement even if Command arrives after mouse-down.
            // This remains observation only; the app owns every input event.
            if let window = engine.window(at: point, excluding: []) {
                candidateWindow = window
                initialFrame = engine.windowServerFrame(of: window.id)
            }
            recordMonitoringDiagnostics()
        case .leftMouseDragged:
            hasDragged = true
            updateCommandState(commandIsDown)
            observeMovement(at: point)
        case .leftMouseUp:
            onMouseInteraction?()
            updateCommandState(commandIsDown)
            observeMovement(at: point)
            if isObservingDrag { delegate?.dragDidEnd(at: point) }
            resetGesture()
        case .flagsChanged:
            // Modifier events can carry stale/non-pointer coordinates. They
            // never establish a drag or select a window under the pointer.
            guard leftButtonIsDown else {
                if isObservingDrag { delegate?.dragDidCancel() }
                resetGesture()
                return
            }
            updateCommandState(commandIsDown)
        default:
            break
        }
    }

    private func updateCommandState(_ held: Bool) {
        commandIsHeld = held
        if !held, isObservingDrag {
            delegate?.dragDidCancel()
            isObservingDrag = false
        }
    }

    private func observeMovement(at point: CGPoint) {
        guard hasDragged, commandIsHeld,
              let window = candidateWindow, let initialFrame,
              hypot(point.x - downPoint.x, point.y - downPoint.y) > Self.dragThreshold,
              let frame = engine.windowServerFrame(of: window.id) else { return }
        // Resizing is not positive evidence of a native window move. Invalidate
        // this candidate until the next mouse-down; pass all input through.
        guard abs(frame.width - initialFrame.width) < 1,
              abs(frame.height - initialFrame.height) < 1 else {
            updateCommandState(false)
            candidateWindow = nil
            return
        }
        guard hypot(frame.minX - initialFrame.minX, frame.minY - initialFrame.minY) > 3 else { return }
        if !isObservingDrag {
            isObservingDrag = true
            delegate?.dragDidBegin(window: window, at: point)
        }
        delegate?.dragDidMove(to: point)
    }

}
