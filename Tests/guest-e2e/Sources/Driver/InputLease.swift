import Foundation
import CoreGraphics

/// A bounded input lease. A background watchdog can release even if the UI/AX thread stalls.
/// All posting and release operations share one lock: no drag can be posted after release.
/// This cannot guarantee delivery after process/OS death or event-post permission revocation.
final class InputLease: @unchecked Sendable {
    private let lock = NSLock()
    private let source: CGEventSource
    private let mouseUp: CGEvent
    private let commandUp: CGEvent
    private var holds = InputHoldState()
    private var lastPoint = CGPoint.zero
    private let processPID: pid_t?
    private let processWindowID: CGWindowID?
    private let command: Bool
    private var audit: [[String: String]] = [] // Updated under the existing input lock; no I/O here.

    init(processPID: pid_t? = nil, processWindowID: CGWindowID? = nil, command: Bool = true) throws {
        guard HarnessPolicy.validInputDestination(pid: processPID, windowID: processWindowID) else {
            throw HarnessError.stop("Process input requires both a positive fixture PID and window ID")
        }
        guard let source = CGEventSource(stateID: .privateState),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: .zero, mouseButton: .left),
              let key = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false) else {
            throw HarnessError.stop("Unable to preallocate input-release events")
        }
        self.source = source; mouseUp = up; commandUp = key
        self.processPID = processPID; self.processWindowID = processWindowID; self.command = command
        mouseUp.flags = command ? .maskCommand : []; commandUp.type = .flagsChanged; commandUp.flags = []
        mouseUp.setIntegerValueField(.eventSourceUserData, value: HarnessConstants.eventTag)
        commandUp.setIntegerValueField(.eventSourceUserData, value: HarnessConstants.eventTag)
    }
    private func post(_ event: CGEvent) {
        if let processWindowID, [.leftMouseDown, .leftMouseDragged, .leftMouseUp].contains(event.type) {
            // Public SDK constants (made public in macOS 10.7). Carry the same
            // validated destination on down/drag AND every normal/watchdog up.
            // This is a routing hypothesis, not a delivery acknowledgement.
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(processWindowID))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(processWindowID))
        }
        capture(event, phase: "before-post")
        if let processPID { event.postToPid(processPID) }
        else { event.post(tap: .cgSessionEventTap) }
        capture(event, phase: "post-returned")
    }
    private func capture(_ event: CGEvent, phase: String) {
        guard audit.count < 64 else { return }
        audit.append(["phase": phase, "transport": processPID == nil ? "session" : "pid",
            "requestedPID": processPID.map { String($0) } ?? "none",
            "requestedWindowID": processWindowID.map { String($0) } ?? "none", "type": String(event.type.rawValue),
            "x": String(describing: event.location.x), "y": String(describing: event.location.y), "flags": String(event.flags.rawValue),
            "tag": String(event.getIntegerValueField(.eventSourceUserData)),
            "targetPIDField": String(event.getIntegerValueField(.eventTargetUnixProcessID)),
            "windowUnderPointer": String(event.getIntegerValueField(.mouseEventWindowUnderMousePointer)),
            "windowCanHandle": String(event.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent)),
            "clickState": String(event.getIntegerValueField(.mouseEventClickState)),
            "uptime": String(ProcessInfo.processInfo.systemUptime)])
    }
    func postAudit() -> [[String: String]] {
        lock.lock(); defer { lock.unlock() }
        return audit
    }
    func begin(at point: CGPoint) throws {
        lock.lock(); defer { lock.unlock() }
        let wasStarted = holds.started, hadModifier = holds.modifier
        guard let key = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true),
              let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left) else {
            throw HarnessError.stop("Cannot begin bounded gesture")
        }
        guard holds.startMouse(command: command) else { throw HarnessError.stop("Input already held or released") }
        key.type = .flagsChanged; key.flags = command ? .maskCommand : []; down.flags = key.flags
        for event in [key, down] { event.setIntegerValueField(.eventSourceUserData, value: HarnessConstants.eventTag) }
        lastPoint = point
        // Hold a strong reference until the watchdog completes, independent of the Runner.
        if !wasStarted { armWatchdog() }
        if command && !hadModifier { post(key) }; post(down)
    }
    func pressModifier(at point: CGPoint) throws {
        lock.lock(); defer { lock.unlock() }
        guard command, let key = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true),
              holds.pressModifier() else { throw HarnessError.stop("Cannot begin bounded modifier hold") }
        key.type = .flagsChanged; key.flags = .maskCommand
        key.setIntegerValueField(.eventSourceUserData, value: HarnessConstants.eventTag)
        lastPoint = point
        armWatchdog()
        post(key)
    }
    private func armWatchdog() {
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 3) { self.release() }
    }
    func finishMouse() throws {
        lock.lock(); defer { lock.unlock() }
        guard holds.endMouse() else { throw HarnessError.stop("Mouse already released by Stop/watchdog") }
        mouseUp.location = lastPoint
        post(mouseUp)
    }
    func drag(to point: CGPoint) throws {
        lock.lock(); defer { lock.unlock() }
        guard holds.mouse, !holds.finished,
              let event = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left) else {
            throw HarnessError.stop("Input lease expired/stopped; no more events")
        }
        event.flags = command ? .maskCommand : []
        event.setIntegerValueField(.eventSourceUserData, value: HarnessConstants.eventTag)
        lastPoint = point; post(event)
    }
    func finishNormally() throws {
        lock.lock(); defer { lock.unlock() }
        guard holds.started, !holds.finished else { throw HarnessError.stop("Watchdog/Stop released input before gesture completion") }
        releaseLocked()
    }
    func release() {
        lock.lock(); defer { lock.unlock() }
        releaseLocked()
    }
    private func releaseLocked() {
        // Preallocated events, so cleanup does not depend on allocation succeeding.
        for action in holds.release() {
            switch action {
            case .mouseUp: mouseUp.location = lastPoint; post(mouseUp)
            case .commandUp: post(commandUp)
            }
        }
    }
}
