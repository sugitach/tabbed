import Foundation
import CoreGraphics

// Pure policy tests: no AppKit, AX, CGEvent creation/posting, or run loop.
var assertions = 0
func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    precondition(value(), message); assertions += 1
}
let uuid = "01234567-89AB-CDEF-0123-456789ABCDEF"
expect(HarnessPolicy.validRunID(uuid), "Canonical UUID")
expect(!HarnessPolicy.validRunID("../../tmp"), "Reject path traversal")
expect(!HarnessPolicy.validRunID(uuid.lowercased()), "Canonical form required")
let screen = CGRect(x: 0, y: 24, width: 1100, height: 700)
expect(HarnessPolicy.visible(CGRect(x: 40, y: 80, width: 360, height: 270), in: screen), "Full frame inside")
expect(!HarnessPolicy.visible(CGRect(x: 1099, y: 723, width: 360, height: 270), in: screen), "One pixel of parked frame is not restored")
expect(!HarnessPolicy.visible(CGRect(x: 40, y: 80, width: 0, height: 270), in: screen), "Empty frame is not visible")
expect(!HarnessPolicy.close(CGRect.null, screen), "Invalid geometry is not close")
expect(HarnessPolicy.close(screen, screen.offsetBy(dx: 2, dy: -2)), "Small geometry tolerance")
expect(!HarnessPolicy.close(screen, screen.offsetBy(dx: 32, dy: 0)), "Untab offset differs from Quit contract")
func row(_ type: String, _ id: UInt32 = 42, _ command: Bool = true, _ tag: Int64 = HarnessConstants.eventTag) -> InputReceipt {
    InputReceipt(type: type, windowID: id, command: command, tag: tag, time: 1)
}
expect(HarnessPolicy.smokePassed([row("down"), row("drag"), row("up")], windowID: 42), "Correct input order")
expect(!HarnessPolicy.smokePassed([row("up"), row("drag"), row("down")], windowID: 42), "Wrong order")
expect(!HarnessPolicy.smokePassed([row("down"), row("drag", 42, false), row("up")], windowID: 42), "Missing modifier")
expect(!HarnessPolicy.smokePassed([row("down", 43), row("drag", 43), row("up", 43)], windowID: 42), "Wrong window")
expect(!HarnessPolicy.smokePassed([row("down", 42, true, 0), row("drag"), row("up")], windowID: 42), "Untagged down")
expect(!HarnessPolicy.smokePassed([row("down"), row("drag")], windowID: 42), "Missing up")
print("PASS: \(assertions) pure policy assertions; no GUI / AX / event posting executed")
let fixedID = "01234567-89AB-CDEF-0123-456789ABCDEF"
let invocation = ["--scenario", "smoke", "--execute", "--confirm-isolated-guest", "--run-id", fixedID]
expect(GuestInvocation.parse([]) == .manual, "Ordinary launch is manual")
expect(GuestInvocation.parse(invocation) == .smoke(fixedID), "Exact explicit smoke invocation")
expect(GuestInvocation.parse(Array(invocation.dropLast())) == .invalid, "Missing run ID must not run")
expect(GuestInvocation.parse(invocation + ["--e2e"]) == .invalid, "Extra arguments must not broaden scope")
expect(GuestInvocation.parse(invocation.map { $0 == "smoke" ? "e2e" : $0 }) == .e2e(fixedID), "Exact confirmed E2E invocation is a separate scenario")
expect(GuestInvocation.parse(invocation.filter { $0 != "--confirm-isolated-guest" }) == .invalid, "Explicit guest confirmation required")
expect(GuestInvocation.parse(invocation.map { $0 == fixedID ? "../old-result" : $0 }) == .invalid, "Run directory traversal forbidden")
let diagnosis = invocation.map { $0 == "smoke" ? "diagnose-point" : $0 }
expect(GuestInvocation.parse(diagnosis) == .pointDiagnostic(fixedID), "Exact diagnosis stays distinct from input probes")
expect(GuestInvocation.parse(diagnosis + ["--session"]) == .invalid, "Diagnosis cannot add an input transport")
expect(GuestInvocation.parse(diagnosis.filter { $0 != "--confirm-isolated-guest" }) == .invalid, "Diagnosis still needs explicit guest invocation")
print("PASS: \(assertions) total pure policy assertions including script-start scope")

// Recorded guest failure: a same-center scale is not accepted as agreement.
let full = CGRect(x: 30, y: 785, width: 360, height: 270)
let scaled = CGRect(x: 34, y: 788, width: 352, height: 264)
let window = WindowRecord(id: 42, identifier: "fixture-A", title: "Test A", initial: RectRecord(full),
    contentOffset: RectRecord(CGRect(x: 0, y: 28, width: 360, height: 242)))
let record = FixtureRecord(runID: uuid, pid: 100, windows: [window], processProbe: false)
func measurement(_ ax: CGRect = full, _ cg: CGRect = full, pid: Int32 = 100,
                 id: UInt32 = 42, identifier: String = "fixture-A", title: String = "Test A") -> [GeometrySample] {
    [GeometrySample(pid: pid, windowID: id, identifier: identifier, title: title,
        ax: RectRecord(ax), cg: RectRecord(cg))]
}
func rejects(_ message: String, _ body: () throws -> Void) {
    do { try body(); preconditionFailure(message) } catch { assertions += 1 }
}
func sample(_ gate: inout StableGeometryGate, _ values: [GeometrySample], _ time: Double) -> Bool {
    try! gate.record(values, at: time)
}
expect(!HarnessPolicy.close(full, scaled), "Recorded mismatch remains rejected")
var gate = StableGeometryGate(expected: record)
expect(!sample(&gate, measurement(full, scaled), 0), "Animation-like mismatch waits without acceptance")
expect(!sample(&gate, measurement(), 0.15), "First agreeing sample cannot pass")
expect(!sample(&gate, measurement(), 0.30), "Two samples cannot pass")
expect(sample(&gate, measurement(), 0.46), "Three agreeing stable samples over 0.3s pass")
var persistent = StableGeometryGate(expected: record)
for t in [0.0, 0.2, 0.4, 0.6] {
    expect(!sample(&persistent, measurement(full, scaled), t), "Persistent disagreement never passes")
}
var fast = StableGeometryGate(expected: record)
for t in [0.0, 0.01, 0.02] {
    expect(!sample(&fast, measurement(), t), "Rapid samples do not imply elapsed stability")
}
var drift = StableGeometryGate(expected: record)
for (i, dx) in [0.0, 0.4, 0.8, 1.2].enumerated() {
    let moved = full.offsetBy(dx: dx, dy: 0)
    expect(!sample(&drift, measurement(moved, moved), Double(i) * 0.2), "Anchor prevents cumulative drift")
}
var reset = StableGeometryGate(expected: record)
expect(!sample(&reset, measurement(), 0), "Reset case starts")
expect(!sample(&reset, measurement(), 0.2), "Reset case second sample")
expect(!sample(&reset, measurement(full, scaled), 0.4), "Mismatch clears accumulated stability")
expect(!sample(&reset, measurement(), 0.6), "Recovery starts new stability interval")
expect(!sample(&reset, measurement(), 0.8), "Recovery needs three samples")
expect(sample(&reset, measurement(), 1.0), "Recovery can pass only after fresh stable interval")
for bad in [measurement(pid: 101), measurement(id: 43), measurement(identifier: "other"),
            measurement(title: "other"), []] {
    var identity = StableGeometryGate(expected: record)
    rejects("Identity errors must stop, not wait") { _ = try identity.record(bad, at: 0) }
}
var invalid = StableGeometryGate(expected: record)
rejects("Invalid frame must stop") { _ = try invalid.record(measurement(.null), at: 0) }
rejects("Invalid time must stop") { _ = try invalid.record(measurement(), at: .nan) }
var clock = StableGeometryGate(expected: record)
_ = sample(&clock, measurement(), 1)
rejects("Nonmonotonic samples must stop") { _ = try clock.record(measurement(), at: 0.9) }
let safe = try! GeometryPolicy.contentRegion(window, frame: full)
expect(safe.contains(CGPoint(x: full.midX, y: full.midY)), "Blank content contains the start")
expect(!safe.contains(CGPoint(x: full.midX, y: full.minY + 10)), "Title bar excluded")
expect(!safe.contains(CGPoint(x: full.minX + 2, y: full.midY)), "Resize border excluded")
expect(try! GeometryPolicy.contentRegion(window, frame: full.offsetBy(dx: 440, dy: 0)) ==
    safe.offsetBy(dx: 440, dy: 0), "Content coordinates translate with same window")
rejects("Unexpected resize cannot reuse content region") {
    _ = try GeometryPolicy.contentRegion(window, frame: CGRect(x: 30, y: 785, width: 100, height: 100))
}
let b = full.offsetBy(dx: 440, dy: 0)
let second = WindowRecord(id: 43, identifier: "fixture-B", title: "Test B", initial: RectRecord(b),
    contentOffset: window.contentOffset)
let two = FixtureRecord(runID: uuid, pid: 100, windows: [window, second], processProbe: false)
let goodPair = measurement() + measurement(b, b, id: 43, identifier: "fixture-B", title: "Test B")
let badPair = measurement() + measurement(b, scaled.offsetBy(dx: 440, dy: 0),
    id: 43, identifier: "fixture-B", title: "Test B")
var pair = StableGeometryGate(expected: two)
expect(!sample(&pair, goodPair, 0), "Both windows need a stability interval")
expect(!sample(&pair, badPair, 0.2), "Second window disagreement resets the whole pair")
expect(!sample(&pair, goodPair, 0.4), "One window cannot carry stability over a pair reset")
expect(!sample(&pair, goodPair, 0.6), "Pair still needs three samples")
expect(sample(&pair, goodPair, 0.8), "Both windows stabilize together")
var swapped = StableGeometryGate(expected: two)
rejects("Swapped window identities must stop") { _ = try swapped.record(Array(goodPair.reversed()), at: 0) }
rejects("Missing one window must stop") { _ = try swapped.record(measurement(), at: 0) }
print("PASS: \(assertions) total pure assertions including startup stability and content targeting")

for scenario in InputProbe.allCases {
    let args = invocation.map { $0 == "smoke" ? scenario.rawValue : $0 }
    expect(GuestInvocation.parse(args) == .probe(scenario, fixedID), "Each process probe needs an exact explicit invocation")
    expect(GuestInvocation.parse(args + ["--session"]) == .invalid, "A process probe cannot switch transport with an extra flag")
}
func probeRow(_ type: String, _ command: Bool, _ time: Double, id: UInt32 = 42) -> InputReceipt {
    var receipt = InputReceipt(type: type, windowID: id, command: command, tag: HarnessConstants.eventTag, time: time)
    receipt.flags = command ? CGEventFlags.maskCommand.rawValue : 0
    return receipt
}
let click = [probeRow("down", false, 1), probeRow("up", false, 2)]
let cmdClick = [probeRow("flags", true, 0), probeRow("down", true, 1), probeRow("up", true, 2), probeRow("flags", false, 3)]
let cmdDrag = [probeRow("flags", true, 0), probeRow("down", true, 1), probeRow("drag", true, 2), probeRow("up", true, 3), probeRow("flags", false, 4)]
expect(HarnessPolicy.probePassed(click, scenario: .plainClick, windowID: 42, fixtureIDs: [42, 43]), "Plain click receipt")
expect(InputProbe.plainClick.usesSession && !InputProbe.plainClick.command, "Plain click stays unmodified on session route")
expect(InputProbe.plainClick.resultMode == "SESSION_INPUT_PROBE_plain-click", "Session result cannot be mistaken for a PID probe")
expect(InputProbe.commandClick.usesSession && InputProbe.commandClick.command, "Command click explicitly selects session")
expect(InputProbe.commandDrag.usesSession && InputProbe.commandDrag.command, "Command drag explicitly selects session")
expect(InputProbe.commandClick.resultMode == "SESSION_INPUT_PROBE_command-click", "Command click route is explicit")
expect(InputProbe.commandDrag.resultMode == "SESSION_INPUT_PROBE_command-drag", "Command drag route is explicit")
expect(HarnessPolicy.probePassed(cmdClick, scenario: .commandClick, windowID: 42, fixtureIDs: [42, 43]), "Command click including release")
expect(HarnessPolicy.probePassed(cmdDrag, scenario: .commandDrag, windowID: 42, fixtureIDs: [42, 43]), "Command drag including release")
expect(!HarnessPolicy.probePassed(cmdClick, scenario: .plainClick, windowID: 42, fixtureIDs: [42, 43]), "Plain click must not receive Command")
expect(!HarnessPolicy.probePassed(click, scenario: .commandClick, windowID: 42, fixtureIDs: [42, 43]), "Command click must receive Command")
expect(!HarnessPolicy.probePassed(Array(cmdDrag.dropLast()), scenario: .commandDrag, windowID: 42, fixtureIDs: [42, 43]), "No success without modifier release receipt")
expect(!HarnessPolicy.probePassed(cmdClick, scenario: .commandDrag, windowID: 42, fixtureIDs: [42, 43]), "Click is not a drag")
expect(!HarnessPolicy.probePassed(cmdDrag, scenario: .commandClick, windowID: 42, fixtureIDs: [42, 43]), "Drag is not a click")
expect(!HarnessPolicy.probePassed(click, scenario: .plainClick, windowID: 43, fixtureIDs: [42, 43]), "Wrong fixture window rejected")
expect(!HarnessPolicy.probePassed(Array(click.reversed()), scenario: .plainClick, windowID: 42, fixtureIDs: [42, 43]), "Reversed events rejected")
expect(!HarnessPolicy.probePassed(cmdClick + [probeRow("down", true, 4)], scenario: .commandClick,
    windowID: 42, fixtureIDs: [42, 43]), "Extra tagged mouse input rejected")
print("PASS: \(assertions) total pure assertions including separate process-directed probes")

expect(FixtureInvocation.parse(["--run-id", fixedID]) == FixtureInvocation(runID: fixedID, processProbe: false), "Legacy fixture remains separate")
expect(FixtureInvocation.parse(["--run-id", fixedID, "--process-probe"]) == FixtureInvocation(runID: fixedID, processProbe: true), "Exact receiver-gated process fixture")
expect(FixtureInvocation.parse(["--run-id", fixedID, "--session"]) == nil, "Unknown fixture mode rejected")
expect(FixtureInvocation.parse(["--run-id"]) == nil, "Missing fixture identity rejected")
expect(FixtureInvocation.parse(["--run-id", fixedID, "--process-probe", "--extra"]) == nil, "Extra fixture arguments rejected")
let blank = CGRect(x: 0, y: 0, width: 360, height: 238)
func receive(_ p: CGPoint = CGPoint(x: 180, y: 119), tag: Int64 = HarnessConstants.eventTag,
             id: UInt32 = 42, expected: UInt32 = 42, hit: Bool = true) -> Bool {
    HarnessPolicy.acceptProcessMouse(tag: tag, windowID: id, expectedWindowID: expected,
        pointInContent: p, bounds: blank, hitIsBlank: hit)
}
expect(receive(), "Own blank content accepted by receiver policy")
expect(!receive(tag: 0), "Lost event tag cannot reach standard fixture dispatch")
expect(!receive(id: 43), "Other fixture window cannot receive a process mouse action")
expect(!receive(expected: 0), "No target window cannot authorize dispatch")
expect(!receive(CGPoint(x: 180, y: 250)), "Titlebar / outside content cannot reach standard dispatch")
expect(!receive(CGPoint(x: 2, y: 119)), "Resize border excluded at receiver")
expect(!receive(CGPoint(x: CGFloat.nan, y: 119)), "Nonfinite received coordinates rejected")
expect(!receive(hit: false), "View hit must identify the blank content itself")
expect(!HarnessPolicy.probePassed([probeRow("rejected-down", false, 1), probeRow("up", false, 2)],
    scenario: .plainClick, windowID: 42, fixtureIDs: [42, 43]), "Rejected receiver input cannot become a PASS")
print("PASS: \(assertions) total pure assertions including receiver-side scope")

expect(HarnessPolicy.validInputDestination(pid: nil, windowID: nil), "Legacy session destination remains explicit")
expect(HarnessPolicy.validInputDestination(pid: 100, windowID: 42), "Process destination requires a concrete PID and window")
expect(!HarnessPolicy.validInputDestination(pid: 100, windowID: nil), "Missing window cannot silently become process or session input")
expect(!HarnessPolicy.validInputDestination(pid: nil, windowID: 42), "Window without PID cannot silently become session input")
expect(!HarnessPolicy.validInputDestination(pid: 0, windowID: 42), "Zero PID rejected")
expect(!HarnessPolicy.validInputDestination(pid: -1, windowID: 42), "Negative PID rejected")
expect(!HarnessPolicy.validInputDestination(pid: 100, windowID: 0), "Zero window rejected")
print("PASS: \(assertions) total pure assertions including PID/window destination pairing")

// Release obligations at each interruption boundary, without creating/posting CGEvents.
var idleHold = InputHoldState()
expect(idleHold.release().isEmpty, "Stopping before any hold must not generate input")
var modifierHold = InputHoldState()
expect(modifierHold.pressModifier(), "Modifier can begin the delayed sequence")
expect(!modifierHold.pressModifier(), "Duplicate modifier press rejected")
expect(modifierHold.release() == [.commandUp], "Stop during initial pause releases only Command")
expect(!modifierHold.startMouse(command: true), "No mouseDown after watchdog/Stop release")
expect(modifierHold.release().isEmpty, "Repeated release is idempotent")
var dragHold = InputHoldState()
expect(dragHold.pressModifier() && dragHold.startMouse(command: true), "Mouse can follow the held modifier")
expect(!dragHold.startMouse(command: true), "Duplicate mouseDown rejected")
expect(dragHold.release() == [.mouseUp, .commandUp], "Stop during gesture releases mouse before Command")
var afterMouse = InputHoldState()
expect(afterMouse.pressModifier() && afterMouse.startMouse(command: true) && afterMouse.endMouse(), "MouseUp can precede the release pause")
expect(!afterMouse.startMouse(command: true), "Cannot restart a second gesture in the same lease")
expect(afterMouse.release() == [.commandUp], "Stop after normal mouseUp releases only Command")
expect(afterMouse.release().isEmpty, "No duplicate mouseUp or CommandUp after completion")
var plainHold = InputHoldState()
expect(plainHold.startMouse(command: false), "Legacy unmodified begin remains valid")
expect(plainHold.release() == [.mouseUp], "Plain click cleanup never emits a modifier release")
var legacyHold = InputHoldState()
expect(legacyHold.startMouse(command: true), "Legacy combined begin remains valid")
expect(legacyHold.release() == [.mouseUp, .commandUp], "Legacy combined cleanup still releases both")
var mismatchedHold = InputHoldState()
expect(mismatchedHold.pressModifier() && !mismatchedHold.startMouse(command: false), "Held Command cannot be downgraded to a plain click")
expect(mismatchedHold.release() == [.commandUp], "Rejected mouse start retains the modifier release obligation")

func confirms(_ rows: [InputReceipt]) -> Bool {
    HarnessPolicy.probePassed(rows, scenario: .commandClick, windowID: 42, fixtureIDs: [42,43])
}
expect(!confirms(Array(cmdClick.dropFirst())), "A mouse Command flag alone does not prove modifier press delivery")
var wrongFlags = cmdClick
wrongFlags[1].flags = CGEventFlags([.maskCommand, .maskAlternate]).rawValue
expect(!confirms(wrongFlags), "Unexpected alternate modifier cannot pass")
wrongFlags = cmdClick; wrongFlags[1].flags = nil
expect(!confirms(wrongFlags), "Missing raw flags cannot pass")
wrongFlags = cmdClick; wrongFlags[3].flags = CGEventFlags.maskCommand.rawValue
expect(!confirms(wrongFlags), "Boolean release cannot conceal a raw held Command")
wrongFlags = cmdClick; wrongFlags[3] = probeRow("flags", false, 1.5)
expect(!confirms(wrongFlags), "Release timestamp must follow mouseUp")
wrongFlags = cmdClick; wrongFlags[0] = probeRow("flags", true, 0, id: 999)
expect(!confirms(wrongFlags), "Modifier delivery outside our Fixture cannot pass")

let intendedStart = CGPoint(x:180,y:119), intendedEnd = CGPoint(x:210,y:119)
func located(_ rows: [InputReceipt], drag: Bool) -> [InputReceipt] {
    var output = rows
    for i in output.indices where output[i].type != "flags" {
        output[i].contentX = drag && output[i].type != "down" ? 210 : 180
        output[i].contentY = 119
        output[i].receiverBounds = RectRecord(blank)
        output[i].blankHit = true
    }
    return output
}
let locatedClick = located(cmdClick, drag:false)
let locatedDrag = located(cmdDrag, drag:true)
func coordinates(_ rows: [InputReceipt], _ scenario: InputProbe = .commandDrag) -> Bool {
    HarnessPolicy.probeCoordinatesPassed(rows, scenario:scenario, start:intendedStart,end:intendedEnd)
}
expect(coordinates(locatedClick,.commandClick), "Click stays at its planned content position")
expect(coordinates(locatedDrag), "Drag moves 30 points and releases at the destination")
var wrongPoint = locatedDrag; wrongPoint[2].contentX = 180
expect(!coordinates(wrongPoint), "A stationary drag cannot prove movement")
wrongPoint = locatedDrag; wrongPoint[3].contentX = 180
expect(!coordinates(wrongPoint), "MouseUp must occur at the drag destination")
wrongPoint = locatedDrag; wrongPoint[2].contentX = .nan
expect(!coordinates(wrongPoint), "Nonfinite observed content position rejected")
wrongPoint = locatedDrag; wrongPoint[2].blankHit = false
expect(!coordinates(wrongPoint), "A nonblank received hit cannot pass")
expect(!coordinates(cmdDrag), "Missing content observations cannot pass")
print("PASS: \(assertions) total pure assertions including staged release and modifier/coordinate evidence")

// Stage 3 predicates used by the actual Runner, without AppKit / OS input.
let stageVisible=CGRect(x:0,y:30,width:1869,height:760)
let stageA=CGRect(x:30,y:467,width:360,height:270),stageB=CGRect(x:470,y:467,width:360,height:270)
func stage(_ id:UInt32,_ ax:CGRect,_ cg:CGRect?=nil,minimized:Bool=false,onscreen:Bool=true)->E2EWindowState {
    E2EWindowState(geometry:GeometrySample(pid:100,windowID:id,identifier:"fixture-\(id)",title:"Test \(id)",
        ax:RectRecord(ax),cg:RectRecord(cg ?? ax)),minimized:minimized,onscreen:onscreen)
}
let initial=[stage(42,stageA),stage(43,stageB)]
let parked=CGRect(x:1868,y:789,width:360,height:270)
let grouped=[stage(42,stageB),stage(43,parked)]
expect(E2EPolicy.grouped(grouped,at:initial[1],in:stageVisible),"Real geometry: A at B and B parked")
expect(!E2EPolicy.grouped([stage(42,stageB),stage(43,stageB)],at:initial[1],in:stageVisible),"Mere overlap is not grouping")
expect(!E2EPolicy.grouped([stage(42,stageB,minimized:true),stage(43,parked)],at:initial[1],in:stageVisible),"Minimized active window cannot pass")
expect(!E2EPolicy.grouped([stage(42,stageB),stage(43,parked,stageB)],at:initial[1],in:stageVisible),"AX alone cannot prove parked state")
expect(E2EPolicy.separated(initial,baseline:initial,in:stageVisible),"Drag-out restores separate source and target frames")
expect(!E2EPolicy.separated(grouped,baseline:initial,in:stageVisible),"Still parked is not ungrouped")
expect(!E2EPolicy.separated([stage(42,stageA),stage(43,stageB,onscreen:false)],baseline:initial,in:stageVisible),"Geometry alone cannot prove visibility")
expect(E2EPolicy.restored([stage(42,stageB),stage(43,stageB)],at:initial[1],in:stageVisible),"Quit restores both at common group frame")
expect(!E2EPolicy.restored(initial,at:initial[1],in:stageVisible),"Separate initial positions are not the Quit contract")
expect(!E2EPolicy.restored([stage(42,stageB)],at:initial[1],in:stageVisible),"Missing original window fails")
expect(!E2EPolicy.restored([stage(42,stageB),stage(43,stageB,minimized:true)],at:initial[1],in:stageVisible),"Minimized restored window fails")
let unequal=stage(42,stageA,stageA.insetBy(dx:4,dy:3))
expect(E2EPolicy.stable([unequal,initial[1]],[unequal,initial[1]]),"Stable AX/CG disagreement is not whole-frame equality failure")
expect(!E2EPolicy.stable(initial,[stage(42,stageA.offsetBy(dx:1,dy:0)),initial[1]]),"Temporal drift beyond 0.5pt cannot be stable")
expect(!E2EPolicy.stable(initial,[initial[1],initial[0]]),"Stable samples cannot swap identities")
expect(!E2EPolicy.stable(initial,[stage(44,stageA),initial[1]]),"Stable samples require exact original window ID")
expect(!E2EPolicy.visible(stage(42,.null),in:stageVisible),"Invalid frame fails visibility")
for direction:CGFloat in [1,-1] {
    let start=CGPoint(x:direction>0 ? 210:650,y:618),end=CGPoint(x:direction>0 ? 650:210,y:618)
    let points=try! E2EPolicy.dragPoints(from:start,to:end)
    expect(points.last==end,"Bounded path reaches exact destination")
    expect(abs(points[0].x-start.x)==12,"First small step crosses real takeover threshold")
    expect(zip([start]+points,points).allSatisfy{abs($0.x-$1.x)<=100 && $0.y==$1.y},"Every incremental step stays within source half width")
    expect(points.count<=7,"Gesture remains bounded under input watchdog")
}
rejects("No unbounded cross-screen drag") { _ = try E2EPolicy.dragPoints(from:.zero,to:CGPoint(x:700,y:0)) }
rejects("No unplanned vertical drag") { _ = try E2EPolicy.dragPoints(from:.zero,to:CGPoint(x:440,y:50)) }
rejects("No nonfinite point") { _ = try E2EPolicy.dragPoints(from:.zero,to:CGPoint(x:CGFloat.nan,y:0)) }
expect(GuestInvocation.parse(invocation.map{$0=="smoke" ? "e2e":$0} + ["--force"]) == .invalid,"E2E cannot add a permission / safety bypass")
expect(HarnessConstants.targetSHA256.count==64,"Build-generated target pin is concrete")
print("PASS: \(assertions) total pure assertions including E2E scope, transitions, visibility and captured drag path")

let strip=E2EPanel(id:99,frame:RectRecord(CGRect(x:470,y:439,width:360,height:28)))
expect(E2EPolicy.stripCandidates([strip],at:initial[1]).map(\.id)==[99],"Own full-width strip at exact group position")
expect(E2EPolicy.stripCandidates([],at:initial[1]).isEmpty,"No strip is distinguishable from grouping")
expect(E2EPolicy.stripCandidates([E2EPanel(id:99,frame:RectRecord(stageB))],at:initial[1]).isEmpty,"Content window cannot masquerade as strip")
expect(E2EPolicy.stripCandidates([E2EPanel(id:0,frame:strip.frame)],at:initial[1]).isEmpty,"Strip needs nonzero observed ID")
print("PASS: \(assertions) total pure assertions including strip presence / disappearance candidates")
