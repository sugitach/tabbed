import AppKit
import ApplicationServices

/// Accessibility-backed implementation of `WindowEngine`.
@MainActor
final class AXWindowEngine: WindowEngine {
    private let spaces = SpacesService()
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    func window(at point: CGPoint, excluding: Set<WindowID>) -> ManagedWindow? {
        for window in WindowServerSnapshot.onScreenWindows(excludingOwnPID: ownPID, excluding: excluding) {
            guard window.frame.contains(point),
                  let managed = managedWindow(id: window.id, pid: window.pid, ownerInfo: window.ownerInfo) else {
                continue
            }
            return managed
        }

        return nil
    }

    func onScreenWindowFrames(excluding: Set<WindowID>) -> [WindowFrame] {
        WindowServerSnapshot.onScreenWindows(excludingOwnPID: ownPID, excluding: excluding).compactMap { window in
            // Skip tiny utility/overlay windows that aren't meaningful drop targets.
            guard window.frame.width >= 80, window.frame.height >= 80 else { return nil }
            return WindowFrame(id: window.id, pid: window.pid, frame: window.frame)
        }
    }


    func managedWindow(from element: AXUIElement, pid: pid_t) -> ManagedWindow? {
        guard pid != ownPID, isStandardWindow(element) else { return nil }

        var resolved = CGWindowID(0)
        guard _AXUIElementGetWindow(element, &resolved) == .success,
              resolved != 0 else {
            return nil
        }

        let runningApp = NSRunningApplication(processIdentifier: pid)
        let title = copyStringAttribute(kAXTitleAttribute, from: element) ?? "Untitled"
        return ManagedWindow(
            id: resolved,
            pid: pid,
            element: element,
            title: title.isEmpty ? "Untitled" : title,
            appName: runningApp?.localizedName ?? "Unknown",
            appBundleID: runningApp?.bundleIdentifier
        )
    }

    func frame(of window: ManagedWindow) -> CGRect? {
        guard let position = copyCGPointAttribute(kAXPositionAttribute, from: window.element),
              let size = copyCGSizeAttribute(kAXSizeAttribute, from: window.element) else {
            WindowDiagnostics.record(.init(event: .frameRead, windowID: window.id, pid: window.pid,
                reason: .unavailable, source: .accessibility))
            return nil
        }

        let frame = CoordinateConverter.appKitFrame(fromCG: CGRect(origin: position, size: size))
        WindowDiagnostics.record(.init(event: .frameRead, windowID: window.id, pid: window.pid,
            axFrame: WindowDiagnostics.frame(frame), source: .accessibility))
        return frame
    }

    func windowServerFrame(of id: WindowID) -> CGRect? {
        let snapshot = WindowServerSnapshot.window(id: id)
        WindowDiagnostics.record(.init(event: .frameRead, windowID: id, pid: snapshot?.pid,
            resolvedWindowID: snapshot?.id, cgFrame: WindowDiagnostics.frame(snapshot?.frame),
            source: .windowServer))
        return snapshot?.frame
    }

    func focusedOrMainWindowID(for pid: pid_t) -> WindowID? {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 1.0)

        if let focused = copyAXElementAttribute(kAXFocusedWindowAttribute, from: appElement),
           let id = windowID(for: focused) {
            return id
        }
        if let main = copyAXElementAttribute(kAXMainWindowAttribute, from: appElement),
           let id = windowID(for: main) {
            return id
        }
        return nil
    }

    func frontmostWindowID() -> WindowID? {
        WindowServerSnapshot.frontmostVisibleWindow(excludingOwnPID: ownPID)?.id
    }

    func candidateWindowElements(from element: AXUIElement, pid: pid_t) -> [AXUIElement] {
        // A creation notification must not enroll a different, already existing
        // focused/main window. Tab drags can invalidate the transient element
        // while focus moves to an unrelated destination in the same process.
        // Do not follow AXWindow either: a reparented tab's containing window
        // can also change while the deferred notification is being resolved.
        return [element]
    }

    func setFrame(_ frame: CGRect, of window: ManagedWindow) {
        WindowDiagnostics.record(.init(event: .frameRequest, windowID: window.id, pid: window.pid,
            requestedFrame: WindowDiagnostics.frame(frame)))
        let cgFrame = CoordinateConverter.cgFrame(fromAppKit: frame)
        // A parked window can still belong to a different display. Move it to
        // the destination before resizing, so the old display's constraints
        // do not clamp the requested size. Reapply position after resizing,
        // since the application may adjust the origin to keep the window visible.
        if copyCGSizeAttribute(kAXSizeAttribute, from: window.element) != cgFrame.size {
            _ = setCGPointAttribute(kAXPositionAttribute, value: cgFrame.origin, on: window.element)
        }
        let sizeStatus = setCGSizeAttribute(kAXSizeAttribute, value: cgFrame.size, on: window.element)
        let positionStatus = setCGPointAttribute(kAXPositionAttribute, value: cgFrame.origin, on: window.element)
        WindowDiagnostics.record(.init(event: .frameResult, windowID: window.id, pid: window.pid,
            requestedFrame: WindowDiagnostics.frame(frame), sizeStatus: sizeStatus.rawValue,
            positionStatus: positionStatus.rawValue))
    }

    func isKnownClosed(_ window: ManagedWindow) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: window.pid), !app.isTerminated else {
            WindowDiagnostics.record(.init(event: .closureCheck, windowID: window.id, pid: window.pid,
                reason: .applicationGone))
            return true
        }
        AXUIElementSetMessagingTimeout(window.element, 1.0)
        var resolved = CGWindowID(0)
        let error = _AXUIElementGetWindow(window.element, &resolved)
        WindowDiagnostics.record(.init(event: .closureCheck, windowID: window.id, pid: window.pid,
            resolvedWindowID: resolved, status: error.rawValue,
            reason: error == .invalidUIElement ? .invalidElement
                : (error == .success ? (resolved == window.id ? .identityMatches : .identityChanged) : .unknown)))
        // Timeout/permission errors are unknown, not evidence that the window closed.
        return error == .invalidUIElement || (error == .success && resolved != window.id)
    }

    func restoreFrame(_ frame: CGRect, of window: ManagedWindow) -> Bool {
        AXUIElementSetMessagingTimeout(window.element, 1.0)
        let cgFrame = CoordinateConverter.cgFrame(fromAppKit: frame)
        // Recover a parked window onto its destination display before resize.
        if copyCGSizeAttribute(kAXSizeAttribute, from: window.element) != cgFrame.size {
            _ = setCGPointAttribute(kAXPositionAttribute, value: cgFrame.origin, on: window.element)
        }
        let sizeStatus = setCGSizeAttribute(kAXSizeAttribute, value: cgFrame.size, on: window.element)
        let positionStatus = setCGPointAttribute(kAXPositionAttribute, value: cgFrame.origin, on: window.element)
        WindowDiagnostics.record(.init(event: .frameResult, windowID: window.id, pid: window.pid,
            requestedFrame: WindowDiagnostics.frame(frame), sizeStatus: sizeStatus.rawValue,
            positionStatus: positionStatus.rawValue))
        // A rejected no-op setter is not a failure if the frame is correct.
        // WindowServer geometry also avoids stale AX caches after a successful move.
        return WindowRestoration.verify(frame: frame,
            read: { self.windowServerFrame(of: window.id) ?? self.frame(of: window) },
            wait: { Thread.sleep(forTimeInterval: 0.02) })
    }

    func raise(_ window: ManagedWindow) {
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
    }

    func activate(_ window: ManagedWindow) {
        let appElement = AXUIElementCreateApplication(window.pid)
        AXUIElementSetMessagingTimeout(appElement, 1.0)
        recordActivationState(window, appElement: appElement, reason: .beforeActivation)
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, window.element)
        AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        raise(window)
        NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
        recordActivationState(window, appElement: appElement, reason: .afterActivation)
    }

    /// Extra reads happen only at explicit tab activation while recording.
    /// No Enhanced UI/minimized attribute is changed by diagnostics.
    private func recordActivationState(_ window: ManagedWindow, appElement: AXUIElement,
                                       reason: WindowDiagnosticEntry.Reason) {
        guard WindowDiagnostics.isRecording else { return }
        var resolved = CGWindowID(0)
        let identityStatus = _AXUIElementGetWindow(window.element, &resolved)
        let axFrame = frame(of: window)
        let cgFrame = WindowServerSnapshot.window(id: window.id)?.frame
        WindowDiagnostics.record(.init(event: .activationState, windowID: window.id, pid: window.pid,
            resolvedWindowID: resolved, axFrame: WindowDiagnostics.frame(axFrame),
            cgFrame: WindowDiagnostics.frame(cgFrame), status: identityStatus.rawValue,
            minimized: copyBoolAttribute(kAXMinimizedAttribute, from: window.element),
            enhancedUI: copyBoolAttribute("AXEnhancedUserInterface", from: appElement), reason: reason))
    }

    private func copyBoolAttribute(_ attribute: String, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? Bool
    }

    func isAlive(_ window: ManagedWindow) -> Bool {
        guard NSRunningApplication(processIdentifier: window.pid) != nil else { return false }
        var resolved = CGWindowID(0)
        return _AXUIElementGetWindow(window.element, &resolved) == .success && resolved == window.id
    }

    func refreshTitle(_ window: ManagedWindow) -> String {
        if let title = copyStringAttribute(kAXTitleAttribute, from: window.element), !title.isEmpty {
            window.title = title
        }
        return window.title
    }

    func spaceID(of window: ManagedWindow) -> UInt64? {
        return spaces.spaceID(forWindow: window.id)
    }

    func activeSpaceIDs() -> Set<UInt64>? { spaces.activeSpaceIDs() }

    func move(_ window: ManagedWindow, toSpaceOf reference: ManagedWindow) {
        spaces.move(window: window.id, toSpaceOf: reference.id)
    }

    private func managedWindow(id: WindowID, pid: pid_t, ownerInfo: [String: Any]) -> ManagedWindow? {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 1.0)

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement] else {
            return nil
        }

        for element in elements {
            var resolved = CGWindowID(0)
            guard _AXUIElementGetWindow(element, &resolved) == .success, resolved == id else {
                continue
            }
            guard isStandardWindow(element) else { return nil }

            let runningApp = NSRunningApplication(processIdentifier: pid)
            let title = copyStringAttribute(kAXTitleAttribute, from: element)
                ?? (ownerInfo[kCGWindowName as String] as? String)
                ?? "Untitled"
            let appName = runningApp?.localizedName
                ?? (ownerInfo[kCGWindowOwnerName as String] as? String)
                ?? "Unknown"

            return ManagedWindow(
                id: id,
                pid: pid,
                element: element,
                title: title.isEmpty ? "Untitled" : title,
                appName: appName,
                appBundleID: runningApp?.bundleIdentifier
            )
        }

        return nil
    }

    private func isStandardWindow(_ element: AXUIElement) -> Bool {
        guard copyStringAttribute(kAXRoleAttribute, from: element) == kAXWindowRole else {
            return false
        }
        return copyStringAttribute(kAXSubroleAttribute, from: element) == kAXStandardWindowSubrole
    }

    private func copyStringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func copyAXElementAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func windowID(for element: AXUIElement) -> WindowID? {
        var resolved = CGWindowID(0)
        guard _AXUIElementGetWindow(element, &resolved) == .success,
              resolved != 0 else {
            return nil
        }
        return resolved
    }

    private func copyCGPointAttribute(_ attribute: String, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = value as! AXValue
        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    private func copyCGSizeAttribute(_ attribute: String, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = value as! AXValue
        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }

    @discardableResult
    private func setCGPointAttribute(_ attribute: String, value: CGPoint, on element: AXUIElement) -> AXError {
        var mutableValue = value
        guard let axValue = AXValueCreate(.cgPoint, &mutableValue) else {
            WindowDiagnostics.record(.init(event: .frameResult, positionStatus: AXError.failure.rawValue,
                reason: .valueEncodingFailed))
            return .failure
        }
        return AXUIElementSetAttributeValue(element, attribute as CFString, axValue)
    }

    @discardableResult
    private func setCGSizeAttribute(_ attribute: String, value: CGSize, on element: AXUIElement) -> AXError {
        var mutableValue = value
        guard let axValue = AXValueCreate(.cgSize, &mutableValue) else {
            WindowDiagnostics.record(.init(event: .frameResult, sizeStatus: AXError.failure.rawValue,
                reason: .valueEncodingFailed))
            return .failure
        }
        return AXUIElementSetAttributeValue(element, attribute as CFString, axValue)
    }

}
