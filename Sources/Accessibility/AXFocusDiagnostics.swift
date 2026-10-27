import AppKit
import ApplicationServices

/// Opt-in, read-only samples. Never changes focus or collects content/title/URL.
@MainActor
enum AXFocusDiagnostics {
    static func record(pid: pid_t, notification: String, delay: Double) {
        guard WindowDiagnostics.isRecording else { return }
        let app = AXUIElementCreateApplication(pid)
        // Give attribute reads an 80 ms budget, with at most 20 ms per read.
        let deadline = ProcessInfo.processInfo.systemUptime + 0.08
        func element(_ attribute: String, of owner: AXUIElement) -> (AXUIElement?, AXError) {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { return (nil, .cannotComplete) }
            AXUIElementSetMessagingTimeout(owner, Float(min(0.02, remaining)))
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(owner, attribute as CFString, &value)
            guard error == .success, let value else { return (nil, error) }
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return (nil, .failure) }
            return (unsafeBitCast(value, to: AXUIElement.self), .success)
        }
        func windowID(_ attribute: String, containing: Bool = false) -> (UInt32?, Int32) {
            let (value, status) = element(attribute, of: app)
            guard let value else { return (nil, status.rawValue) }
            var id = CGWindowID(0)
            var error = _AXUIElementGetWindow(value, &id)
            if containing && (error != .success || id == 0) {
                let (window, status) = element(kAXWindowAttribute, of: value)
                guard let window else { return (nil, status.rawValue) }
                error = _AXUIElementGetWindow(window, &id)
            }
            return (error == .success && id != 0 ? id : nil, error.rawValue)
        }
        let focused = windowID(kAXFocusedWindowAttribute)
        let main = windowID(kAXMainWindowAttribute)
        let content = windowID(kAXFocusedUIElementAttribute, containing: true)
        WindowDiagnostics.record(.init(event: .focusSnapshot, pid: pid,
            notification: WindowDiagnostics.notification(notification),
            focusedWindowID: focused.0, mainWindowID: main.0, focusedElementWindowID: content.0,
            focusedWindowStatus: focused.1, mainWindowStatus: main.1,
            focusedElementWindowStatus: content.1,
            frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            frontmostWindowID: WindowServerSnapshot.frontmostVisibleWindow(
                excludingOwnPID: ProcessInfo.processInfo.processIdentifier)?.id,
            sampleDelay: delay))
    }
}
