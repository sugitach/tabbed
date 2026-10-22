import AppKit

// One bounded, process-local diagnostic file. No global monitor, event posting,
// input modification, key characters, external window titles or permission requests.
@MainActor
final class DeliveryTrace {
    private let url: URL
    private var rows: [[String: String]] = []
    private var monitor: Any?
    private(set) var failed = false
    var ready: Bool { monitor != nil && !failed }
    init(directory: URL) throws {
        url = directory.appendingPathComponent("fixture-delivery.json")
        rows = [["stage": "output-ready", "pid": String(getpid()),
                 "uptime": String(ProcessInfo.processInfo.systemUptime)]]
        try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])
            .write(to: url, options: .withoutOverwriting)
    }
    @discardableResult func record(_ stage: String, _ fields: [String: String] = [:]) -> Bool {
        guard !failed else { return false }
        do {
            guard rows.count < 128 else { throw HarnessError.stop("Fixture trace limit reached") }
            var row = fields
            row["stage"] = stage; row["pid"] = String(getpid())
            row["uptime"] = String(ProcessInfo.processInfo.systemUptime)
            rows.append(row)
            try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])
                .write(to: url, options: .atomic)
            return true
        } catch {
            failed = true
            NSApp.terminate(nil) // Missing audit must not allow a diagnostic PASS.
            return false
        }
    }
    @discardableResult func event(_ stage: String, _ e: NSEvent, receiver: Int? = nil) -> Bool {
        var fields: [String: String] = [:]
        fields["nsType"] = String(e.type.rawValue)
        fields["nsWindowNumber"] = String(e.windowNumber)
        fields["nsEventWindow"] = e.window.map { String($0.windowNumber) } ?? "nil"
        fields["nsFlags"] = String(e.modifierFlags.rawValue)
        fields["nsLocationX"] = String(describing: e.locationInWindow.x)
        fields["nsLocationY"] = String(describing: e.locationInWindow.y)
        if let receiver { fields["receiverWindow"] = String(receiver) }
        if let cg = e.cgEvent {
            fields["cgType"] = String(cg.type.rawValue)
            fields["cgLocationX"] = String(describing: cg.location.x)
            fields["cgLocationY"] = String(describing: cg.location.y)
            fields["tag"] = String(cg.getIntegerValueField(.eventSourceUserData))
            fields["cgWindowUnderPointer"] = String(cg.getIntegerValueField(.mouseEventWindowUnderMousePointer))
            fields["cgWindowCanHandle"] = String(cg.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent))
            fields["cgTargetPID"] = String(cg.getIntegerValueField(.eventTargetUnixProcessID))
        } else { fields["cgEvent"] = "nil" }
        // Number strings preserve invalid/NaN coordinates without breaking JSON logging.
        return record(stage, fields)
    }
    func install() -> Bool {
        guard monitor == nil else { return false }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .any) { [weak self] event in
            MainActor.assumeIsolated { _ = self?.event("app-local-monitor", event) }
            return event // Observe only; do not rewrite or consume any event.
        }
        guard monitor != nil else { return false }
        return record("local-monitor-installed")
    }
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }
}
