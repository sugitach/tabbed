import AppKit
import ApplicationServices

// Observation only. No event creation/posting, AX writes, permission requests,
// screenshots, shell commands or Tabbed launch. Preserve raw candidate order.
@MainActor
enum PointDiagnostic {
    static func rect(_ frame: CGRect) -> [String: Double] {
        ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
    }
    private static func app(_ value: NSRunningApplication?) -> [String: Any] {
        guard let value else { return ["available": false] }
        return ["pid": value.processIdentifier, "bundleID": value.bundleIdentifier ?? "unavailable"]
    }
    private static func hit(_ point: CGPoint, fixturePID: pid_t) -> [String: Any] {
        let start = ProcessInfo.processInfo.systemUptime
        guard AXIsProcessTrusted() else {
            return ["startUptime": start, "status": "AX_NOT_TRUSTED_NO_REQUEST"]
        }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        var element: AXUIElement?
        let status = AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &element)
        var result: [String: Any] = ["startUptime": start, "AXError": status.rawValue]
        if status == .success, let element {
            AXUIElementSetMessagingTimeout(element, 0.15)
            if let pid = try? Observation.pid(element) { result["pid"] = pid }
            result["role"] = Observation.text(element, kAXRoleAttribute) ?? "unavailable"
            result["subrole"] = Observation.text(element, kAXSubroleAttribute) ?? "unavailable"
            let window = Observation.text(element, kAXRoleAttribute) == kAXWindowRole ? element :
                Observation.element(element, kAXWindowAttribute)
            if let window {
                AXUIElementSetMessagingTimeout(window, 0.15)
                let pid = try? Observation.pid(window)
                if let pid { result["windowPID"] = pid }
                result["windowRole"] = Observation.text(window, kAXRoleAttribute) ?? "unavailable"
                if let frame = try? Observation.frame(window) { result["windowFrame"] = rect(frame) }
                // Do not collect unrelated window titles or document contents.
                if pid == fixturePID {
                    result["fixtureWindowIdentifier"] = Observation.text(window, kAXIdentifierAttribute) ?? "unavailable"
                    result["fixtureWindowTitle"] = Observation.text(window, kAXTitleAttribute) ?? "unavailable"
                }
            }
        }
        result["endUptime"] = ProcessInfo.processInfo.systemUptime
        return result
    }
    static func capture(point: CGPoint, expected: WindowRecord, fixturePID: pid_t,
                        activation: [String: Any]) throws -> [String: Any] {
        guard let screen = NSScreen.main else { throw HarnessError.stop("No guest display") }
        var result: [String: Any] = [
            "schema": 1, "startUptime": ProcessInfo.processInfo.systemUptime,
            "mode": "POINT_DIAGNOSTIC_NO_INPUT", "inputEventsCreated": false,
            "point": ["x": point.x, "y": point.y],
            "previousRunReferencePoint": ["x": 210, "y": 618],
            "expectedWindowID": expected.id, "expectedPID": fixturePID,
            "fixtureInitialFrame": rect(expected.initial.rect),
            "fixtureContentOffset": rect(expected.contentOffset.rect),
            "activation": activation,
            "frontmostBefore": app(NSWorkspace.shared.frontmostApplication),
            "screenFrameAppKit": rect(screen.frame), "visibleFrameAppKit": rect(screen.visibleFrame),
            "screenFrameCG": rect(CGDisplayBounds(CGMainDisplayID())),
            "backingScale": screen.backingScaleFactor,
            "displayPixelsWide": CGDisplayPixelsWide(CGMainDisplayID()),
            "displayPixelsHigh": CGDisplayPixelsHigh(CGMainDisplayID()),
            "coordinateConvention": "Guest top-left points. Fixture AppKit y is flipped using screenTop. No host CUA coordinates or pixel multiplication.",
            "limitations": "CG and AX are sequential observations with uptime brackets, not an atomic hit test. No screenshot is captured by this app. Candidate rectangle membership does not prove mouse hit routing."
        ]
        let top = screen.frame.maxY
        result["harnessWindows"] = NSApp.windows.map { window -> [String: Any] in
            let r = window.frame
            return ["id": window.windowNumber, "level": window.level.rawValue,
                    "visible": window.isVisible, "key": window.isKeyWindow,
                    "frameCGConverted": rect(CGRect(x: r.minX, y: top-r.maxY, width: r.width, height: r.height))]
        }
        if let frame = try? Observation.windowServer(expected.id, pid: fixturePID) {
            result["expectedCGFrameBeforeSnapshot"] = rect(frame)
        }
        result["cgSnapshotStartUptime"] = ProcessInfo.processInfo.systemUptime
        guard let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0) as? [[String: Any]] else {
            throw HarnessError.stop("WindowServer diagnostic snapshot unavailable")
        }
        result["cgSnapshotEndUptime"] = ProcessInfo.processInfo.systemUptime
        result["cgSnapshotRowCount"] = rows.count
        var candidates: [[String: Any]] = []
        var first: [String: Any]?
        for (index, row) in rows.enumerated() {
            guard let bounds = row[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds), frame.contains(point) else { continue }
            let layer = (row[kCGWindowLayer as String] as? NSNumber)?.intValue
            let alpha = (row[kCGWindowAlpha as String] as? NSNumber)?.doubleValue
            let id = (row[kCGWindowNumber as String] as? NSNumber)?.uint32Value
            let pid = (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            let eligible = (layer ?? -1) >= 0 && (alpha ?? 1) > 0
            var candidate: [String: Any] = ["index": index, "bounds": rect(frame), "eligibleByV04Filter": eligible,
                "effectiveLayer": layer ?? -1, "effectiveAlpha": alpha ?? 1,
                "layerPresent": layer != nil, "alphaPresent": alpha != nil,
                "ownerName": row[kCGWindowOwnerName as String] as? String ?? "unavailable",
                "matchesExpected": id == expected.id && pid == fixturePID]
            if let id { candidate["windowID"] = id }
            if let pid { candidate["pid"] = pid }
            candidate["onScreen"] = (row[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
            candidates.append(candidate)
            if eligible && first == nil { first = candidate }
        }
        result["candidatesAtPointInReturnedOrder"] = candidates
        if let first { result["firstEligibleCandidate"] = first }
        result["v04TopWindowDecision"] = first.map { ($0["matchesExpected"] as? Bool) == true ? "ACCEPT" : "REJECT_UNEXPECTED_FOREGROUND" } ?? "REJECT_NO_FIXTURE"
        result["axHit"] = hit(point, fixturePID: fixturePID)
        result["frontmostAfter"] = app(NSWorkspace.shared.frontmostApplication)
        result["endUptime"] = ProcessInfo.processInfo.systemUptime
        return result
    }
}
