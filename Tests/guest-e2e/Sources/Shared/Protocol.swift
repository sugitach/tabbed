import Foundation
import CoreGraphics

enum HarnessConstants {
    static let fixtureID = "dev.local.TabbedGuestFixture"
    static let driverID = "dev.local.TabbedGuestHarness"
    static let targetID = "dev.local.TabbedReviewed"
    static let targetSHA256 = PinnedTarget.sha256
    static let eventTag: Int64 = 0x54474248524E
    static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TabbedGuestHarness", isDirectory: true)
    }
    static var target: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Tabbed-Quit-Fix-Test/Tabbed Quit Fix.app", isDirectory: true)
    }
}

struct RectRecord: Codable {
    let x: Double, y: Double, width: Double, height: Double
    init(_ r: CGRect) { x = r.minX; y = r.minY; width = r.width; height = r.height }
    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct WindowRecord: Codable {
    let id: UInt32
    let identifier: String
    let title: String
    let initial: RectRecord // CG/AX top-left points, not physical pixels.
    let contentOffset: RectRecord // Actual blank content in top-left window-relative points.
}

struct FixtureRecord: Codable {
    let runID: String
    let pid: Int32
    let windows: [WindowRecord]
    let processProbe: Bool
    var deliveryTraceReady = false
}

struct InputReceipt: Codable {
    let type: String
    let windowID: UInt32
    let command: Bool
    let tag: Int64
    let time: Double
    var contentX: Double? = nil
    var contentY: Double? = nil
    var receiverBounds: RectRecord? = nil
    var blankHit: Bool? = nil
    var flags: UInt64? = nil
}

enum HarnessPolicy {
    static func validRunID(_ s: String) -> Bool { UUID(uuidString: s)?.uuidString == s }
    static func validInputDestination(pid: Int32?, windowID: UInt32?) -> Bool {
        switch (pid, windowID) {
        case (nil, nil): return true // Explicit legacy session path.
        case let (pid?, windowID?): return pid > 0 && windowID > 0
        default: return false // Never downgrade a partial process destination to session.
        }
    }
    static func close(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 3) -> Bool {
        abs(a.minX-b.minX) <= tolerance && abs(a.minY-b.minY) <= tolerance &&
        abs(a.width-b.width) <= tolerance && abs(a.height-b.height) <= tolerance
    }
    static func visible(_ frame: CGRect, in screen: CGRect) -> Bool {
        frame.width > 0 && frame.height > 0 && screen.insetBy(dx: -3, dy: -3).contains(frame)
    }
    static func smokePassed(_ rows: [InputReceipt], windowID: UInt32) -> Bool {
        let r = rows.filter { $0.windowID == windowID && $0.tag == HarnessConstants.eventTag }
        guard let down = r.firstIndex(where: { $0.type == "down" && $0.command }),
              let drag = r.indices.first(where: { $0 > down && r[$0].type == "drag" && r[$0].command }),
              r.indices.contains(where: { $0 > drag && r[$0].type == "up" && r[$0].command }) else { return false }
        return true
    }
    static func probePassed(_ rows: [InputReceipt], scenario: InputProbe, windowID: UInt32,
                            fixtureIDs: Set<UInt32>) -> Bool {
        let tagged = rows.filter { $0.tag == HarnessConstants.eventTag }
        let mouse = tagged.filter { $0.type != "flags" }
        let expectedMouse = scenario == .commandDrag ? ["down", "drag", "up"] : ["down", "up"]
        let expected = scenario.command ? ["flags"] + expectedMouse + ["flags"] : expectedMouse
        guard tagged.map(\.type) == expected,
              mouse.allSatisfy({ $0.windowID == windowID && $0.command == scenario.command }),
              tagged.allSatisfy({ $0.time.isFinite && fixtureIDs.contains($0.windowID) }),
              zip(tagged, tagged.dropFirst()).allSatisfy({ $0.time < $1.time }),
              tagged.enumerated().allSatisfy({ index, row in
                  let expectedCommand = scenario.command && index < tagged.count - 1
                  guard let flags = row.flags else { return false }
                  let relevant: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
                  return row.command == expectedCommand && CGEventFlags(rawValue: flags).intersection(relevant) ==
                      (expectedCommand ? .maskCommand : [])
              }) else { return false }
        // Confirm the release in our own fixture event stream, not a global state claim.
        if scenario.command {
            return tagged.contains { $0.type == "flags" && !$0.command &&
                fixtureIDs.contains($0.windowID) && $0.time >= mouse.last!.time }
        }
        return tagged.allSatisfy { !$0.command }
    }
    static func probeCoordinatesPassed(_ rows: [InputReceipt], scenario: InputProbe,
                                       start: CGPoint, end: CGPoint) -> Bool {
        let mouse = rows.filter { $0.tag == HarnessConstants.eventTag && $0.type != "flags" }
        let points = scenario == .commandDrag ? [start, end, end] : [start, start]
        guard mouse.count == points.count else { return false }
        return zip(mouse, points).allSatisfy { row, point in
            guard let x = row.contentX, let y = row.contentY, let bounds = row.receiverBounds?.rect,
                  row.blankHit == true, x.isFinite, y.isFinite,
                  point.x.isFinite, point.y.isFinite, GeometryPolicy.valid(bounds),
                  GeometryPolicy.valid(bounds.insetBy(dx: 12, dy: 12)),
                  bounds.insetBy(dx: 12, dy: 12).contains(CGPoint(x: x, y: y)) else { return false }
            return abs(x - point.x) <= 0.5 && abs(y - point.y) <= 0.5
        }
    }
    static func acceptProcessMouse(tag: Int64, windowID: UInt32, expectedWindowID: UInt32,
                                   pointInContent: CGPoint, bounds: CGRect, hitIsBlank: Bool) -> Bool {
        tag == HarnessConstants.eventTag && expectedWindowID > 0 && windowID == expectedWindowID &&
            pointInContent.x.isFinite && pointInContent.y.isFinite && GeometryPolicy.valid(bounds) &&
            GeometryPolicy.valid(bounds.insetBy(dx: 12, dy: 12)) &&
            bounds.insetBy(dx: 12, dy: 12).contains(pointInContent) && hitIsBlank
    }
}

enum InputProbe: String, CaseIterable {
    case plainClick = "plain-click", commandClick = "command-click", commandDrag = "command-drag"
    var command: Bool { self != .plainClick }
    // 0.10 extends the proven session route to the two explicit modifier probes.
    var usesSession: Bool { true }
    var resultMode: String { (usesSession ? "SESSION_INPUT_PROBE_" : "PROCESS_INPUT_PROBE_") + rawValue }
}

struct FixtureInvocation: Equatable {
    let runID: String
    let processProbe: Bool
    static func parse(_ args: [String]) -> FixtureInvocation? {
        guard (args.count == 2 || args.count == 3), args[0] == "--run-id",
              HarnessPolicy.validRunID(args[1]),
              args.count == 2 || args[2] == "--process-probe" else { return nil }
        return FixtureInvocation(runID: args[1], processProbe: args.count == 3)
    }
}

enum GuestInvocation: Equatable {
    case manual
    case smoke(String)
    case e2e(String)
    case probe(InputProbe, String)
    case pointDiagnostic(String)
    case invalid
    static func parse(_ arguments: [String]) -> GuestInvocation {
        if arguments.isEmpty { return .manual }
        guard arguments.count == 6,
              arguments[0] == "--scenario",
              Array(arguments[2...4]) == ["--execute", "--confirm-isolated-guest", "--run-id"],
              HarnessPolicy.validRunID(arguments[5]) else { return .invalid }
        if arguments[1] == "smoke" { return .smoke(arguments[5]) }
        if arguments[1] == "e2e" { return .e2e(arguments[5]) }
        if arguments[1] == "diagnose-point" { return .pointDiagnostic(arguments[5]) }
        if let scenario = InputProbe(rawValue: arguments[1]) { return .probe(scenario, arguments[5]) }
        return .invalid
    }
}

enum HarnessError: Error, CustomStringConvertible {
    case stop(String)
    var description: String { switch self { case .stop(let s): return s } }
}
