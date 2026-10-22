import AppKit
import ApplicationServices
import CryptoKit

enum Observation {
    static func vmFlag() -> String {
        var value: Int32 = 0; var size = MemoryLayout<Int32>.size
        let status = sysctlbyname("kern.hv_vmm_present", &value, &size, nil, 0)
        return status == 0 ? String(value) : "unknown"
    }
    static func hash(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }
    static func targetDragTapReady(pid: pid_t) -> Bool {
        var count: UInt32 = 0
        guard CGGetEventTapList(0, nil, &count) == .success, count > 0, count <= 256 else { return false }
        var taps = Array(repeating: CGEventTapInformation(), count: Int(count))
        let capacity = count
        let result = taps.withUnsafeMutableBufferPointer { CGGetEventTapList(capacity, $0.baseAddress, &count) }
        guard result == .success, count <= capacity else { return false }
        let mask = [CGEventType.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]
            .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        return taps.prefix(Int(count)).contains {
            $0.tappingProcess == pid && $0.enabled && $0.tapPoint == .cgSessionEventTap &&
            $0.options == .defaultTap && ($0.eventsOfInterest & mask) == mask
        }
    }
    static func targetPanels(pid:pid_t) throws -> [E2EPanel] {
        guard let rows=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],0) as? [[String:Any]] else {
            throw HarnessError.stop("Target panel observation unavailable")
        }
        return try rows.filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid &&
            ($0[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0 }.map { row in
            guard let id=(row[kCGWindowNumber as String] as? NSNumber)?.uint32Value,id>0,
                  let bounds=row[kCGWindowBounds as String] as? NSDictionary,
                  let frame=CGRect(dictionaryRepresentation:bounds),GeometryPolicy.valid(frame) else {
                throw HarnessError.stop("Invalid owned target panel metadata")
            }
            return E2EPanel(id:id,frame:RectRecord(frame))
        }
    }
    static func requireNoTargetTaps(pid: pid_t) throws {
        var count:UInt32=0
        guard CGGetEventTapList(0,nil,&count) == .success,count<=256 else { throw HarnessError.stop("Cannot inspect remaining target taps") }
        if count==0 { return }
        let capacity=count
        var taps=Array(repeating:CGEventTapInformation(),count:Int(capacity))
        let result=taps.withUnsafeMutableBufferPointer { CGGetEventTapList(capacity,$0.baseAddress,&count) }
        guard result == .success,count<=capacity,!taps.prefix(Int(count)).contains(where:{$0.tappingProcess==pid}) else {
            throw HarnessError.stop("Target event tap remains or inspection failed")
        }
    }
    static func canonical(_ url: URL) -> URL { url.resolvingSymlinksInPath().standardizedFileURL }
    static func attribute(_ element: AXUIElement, _ name: String) throws -> CFTypeRef {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard result == .success, let value else { throw HarnessError.stop("AX \(name): \(result.rawValue)") }
        return value
    }
    static func text(_ element: AXUIElement, _ name: String) -> String? {
        (try? attribute(element, name)) as? String
    }
    static func children(_ element: AXUIElement, _ name: String = kAXChildrenAttribute) -> [AXUIElement] {
        guard let array = try? attribute(element, name) as? [AnyObject] else { return [] }
        return array.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    }
    static func element(_ parent: AXUIElement, _ name: String) -> AXUIElement? {
        guard let v = try? attribute(parent, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }
    static func pid(_ element: AXUIElement) throws -> pid_t {
        var p: pid_t = 0
        guard AXUIElementGetPid(element, &p) == .success else { throw HarnessError.stop("AX PID unavailable") }
        return p
    }
    static func frame(_ e: AXUIElement) throws -> CGRect {
        let p = try attribute(e, kAXPositionAttribute), s = try attribute(e, kAXSizeAttribute)
        guard CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else {
            throw HarnessError.stop("Unexpected AX geometry type")
        }
        var point = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point),
              AXValueGetValue(s as! AXValue, .cgSize, &size),
              point.x.isFinite, point.y.isFinite, size.width.isFinite, size.height.isFinite else {
            throw HarnessError.stop("Invalid AX geometry")
        }
        return CGRect(origin: point, size: size)
    }
    static func windowServer(_ id: UInt32, pid: pid_t) throws -> CGRect {
        guard let rows = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]],
              let r = rows.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id }),
              (r[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
              let bounds = r[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds) else {
            throw HarnessError.stop("WindowServer ID/PID missing or changed")
        }
        return frame
    }
    static func requireFixtureHit(at point: CGPoint, window: AXUIElement, pid expected: pid_t) throws {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let hit, try pid(hit) == expected else {
            throw HarnessError.stop("AX hit test did not identify the fixture PID")
        }
        AXUIElementSetMessagingTimeout(hit, 0.15)
        let hitWindow = text(hit, kAXRoleAttribute) == kAXWindowRole ? hit : element(hit, kAXWindowAttribute)
        guard let hitWindow, try pid(hitWindow) == expected, CFEqual(hitWindow, window) else {
            throw HarnessError.stop("AX hit test did not identify the expected fixture window")
        }
    }
    static func isOnscreen(_ id: UInt32, pid: pid_t) -> Bool {
        guard let rows = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]],
              let row = rows.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id }),
              (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid else { return false }
        return (row[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true
    }
    static func topWindow(at point: CGPoint, allowed: Set<UInt32>, pid: pid_t,
                          overlayPID: pid_t? = nil, overlayFrame: CGRect? = nil) throws -> UInt32 {
        guard let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0) as? [[String: Any]] else {
            throw HarnessError.stop("WindowServer snapshot unavailable")
        }
        for r in rows {
            guard (r[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1 >= 0,
                  (r[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let bounds = r[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds), frame.contains(point) else { continue }
            // During an already captured E2E drag only, Tabbed's drop-indicator panel
            // may cover the fixture. Never exempt another application's floating panel.
            if let overlayPID, let overlayFrame,
               (r[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == overlayPID,
               (r[kCGWindowLayer as String] as? NSNumber)?.intValue == NSWindow.Level.statusBar.rawValue,
               HarnessPolicy.close(frame, overlayFrame.insetBy(dx: -16, dy: -16)) { continue }
            guard let id = (r[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  allowed.contains(id), (r[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid else {
                throw HarnessError.stop("Unexpected foreground window at event point; no further input")
            }
            return id
        }
        throw HarnessError.stop("No fixture window at event point")
    }
    static func find(_ app: AXUIElement, pid expected: pid_t, title: String, role: String? = nil) -> AXUIElement? {
        var pending = [app]
        for name in [kAXMenuBarAttribute, "AXExtrasMenuBar"] {
            if let e = element(app, name) { pending.append(e) }
        }
        var visited = 0
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while !pending.isEmpty && visited < 60 && ProcessInfo.processInfo.systemUptime < deadline {
            let e = pending.removeFirst(); visited += 1
            guard (try? pid(e)) == expected else { continue }
            AXUIElementSetMessagingTimeout(e, 0.2)
            if (text(e, kAXTitleAttribute) == title || text(e, kAXDescriptionAttribute) == title),
               role == nil || text(e, kAXRoleAttribute) == role { return e }
            pending += children(e)
        }
        return nil
    }
}
