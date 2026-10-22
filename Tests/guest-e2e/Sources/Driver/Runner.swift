import AppKit
import ApplicationServices
import Security
import Darwin

@MainActor
private final class LaunchWaiter {
    private var continuation: CheckedContinuation<NSRunningApplication, Error>?
    private var result: Result<NSRunningApplication, Error>?
    func install(_ continuation: CheckedContinuation<NSRunningApplication, Error>) {
        if let result { continuation.resume(with: result) } else { self.continuation = continuation }
    }
    @discardableResult func finish(_ result: Result<NSRunningApplication, Error>) -> Bool {
        guard self.result == nil else { return false }
        self.result = result; continuation?.resume(with: result); continuation = nil
        return true
    }
}

@MainActor
final class Runner {
    var report: (String) -> Void = { _ in }
    var finished: () -> Void = {}
    private var task: Task<Void, Never>?
    private var fixture: NSRunningApplication?
    private var target: NSRunningApplication?
    private var fixtureRecord: FixtureRecord?
    private var directory: URL?
    private var lease: InputLease?
    private var deadline: TimeInterval = 0
    private var lastFrames: [RectRecord] = []
    private var runID = ""
    private var mode = ""
    private var launchOutstanding = false
    private var displayFrame: CGRect?
    private var displayScale: CGFloat?
    var running: Bool { task != nil }
    private(set) var completedE2E = false
    private var phase = "preflight"
    private var checkpoints: [[String: Any]] = []
    private var e2ePanels: [E2EPanel] = []

    private var fixtureURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Tabbed Guest Fixture.app")
    }
    private func log(_ message: String, fields: [String: Any] = [:]) {
        report(message)
        guard let directory else { return }
        var object = fields
        object["message"] = message; object["uptime"] = ProcessInfo.processInfo.systemUptime
        object["runID"] = runID; object["mode"] = mode
        do {
            var bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            bytes.append(10)
            let url = directory.appendingPathComponent("driver.jsonl")
            if !FileManager.default.fileExists(atPath: url.path) {
                try bytes.write(to: url, options: .withoutOverwriting)
            } else {
                let file = try FileHandle(forWritingTo: url)
                defer { try? file.close() }
                try file.seekToEnd(); try file.write(contentsOf: bytes)
            }
        } catch {
            // A missing audit trail must not allow further events.
            releaseInputs(); task?.cancel()
            report("STOP: log write failed (no credentials are logged)")
        }
    }
    private func check() throws {
        try Task.checkCancellation()
        guard ProcessInfo.processInfo.systemUptime < deadline else { throw HarnessError.stop("Run deadline exceeded") }
    }
    private func pause(_ seconds: Double) async throws {
        try check()
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        try check()
    }
    private func signedBundle(_ url: URL) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else {
            throw HarnessError.stop("Invalid code signature: \(url.lastPathComponent)")
        }
    }
    private func preflight(e2e: Bool, processProbe: Bool = false, pointDiagnostic: Bool = false) throws {
        guard !launchOutstanding else { throw HarnessError.stop("Earlier Launch Services outcome still pending; inspect guest, do not retry") }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: HarnessConstants.driverID).count == 1 else {
            throw HarnessError.stop("Run exactly one harness instance")
        }
        guard Observation.vmFlag() == "1" else { throw HarnessError.stop("VM detection is not 1; fail closed, no override") }
        guard NSScreen.screens.count == 1, let s = NSScreen.main,
              s.visibleFrame.width >= 1100, s.visibleFrame.height >= 700 else {
            throw HarnessError.stop("Use one guest display with visible area >= 1100 x 700 points")
        }
        guard s.frame.origin == .zero,
              HarnessPolicy.close(s.frame, CGDisplayBounds(CGMainDisplayID()), tolerance: 0.5) else {
            throw HarnessError.stop("Unsupported AppKit / Quartz display coordinate mapping")
        }
        displayFrame = s.frame; displayScale = s.backingScaleFactor
        guard pointDiagnostic || CGPreflightPostEventAccess() else {
            throw HarnessError.stop("Guest event-post permission missing. No request or setting change was made.")
        }
        guard pointDiagnostic || processProbe || AXIsProcessTrusted() else {
            throw HarnessError.stop("Guest Accessibility permission missing. No request or setting change was made.")
        }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: HarnessConstants.fixtureID).isEmpty else {
            throw HarnessError.stop("Close the previous test fixture first")
        }
        let existing = NSWorkspace.shared.runningApplications.filter {
            [HarnessConstants.targetID, "dev.local.Tabbed"].contains($0.bundleIdentifier ?? "") ||
                $0.executableURL?.lastPathComponent == "Tabbed"
        }
        guard existing.isEmpty else { throw HarnessError.stop("Quit all existing Tabbed instances manually before a fresh run") }
        try signedBundle(Bundle.main.bundleURL)
        try signedBundle(fixtureURL)
        let expected = try String(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/fixture.sha256"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard try Observation.hash(fixtureURL.appendingPathComponent("Contents/MacOS/Fixture")) == expected else {
            throw HarnessError.stop("Fixture executable hash mismatch")
        }
        if e2e {
            try signedBundle(HarnessConstants.target)
            guard Bundle(url: HarnessConstants.target)?.bundleIdentifier == HarnessConstants.targetID,
                  try Observation.hash(HarnessConstants.target.appendingPathComponent("Contents/MacOS/Tabbed")) == HarnessConstants.targetSHA256 else {
                throw HarnessError.stop("Fixed Tabbed path / bundle ID / pinned executable hash mismatch")
            }
            let compact=CFPreferencesCopyAppValue("alwaysUseCompactMode" as CFString,HarnessConstants.targetID as CFString)
            guard (compact as? NSNumber)?.boolValue != true,
                  ProcessInfo.processInfo.environment["TABBED_FORCE_COMPACT"] == nil else {
                throw HarnessError.stop("E2E requires the normal non-compact strip; no setting changed")
            }
            let autoAdd = CFPreferencesCopyAppValue("autoAddNewWindowsToStack" as CFString, HarnessConstants.targetID as CFString)
            guard (autoAdd as? NSNumber)?.boolValue != true else {
                throw HarnessError.stop("Tabbed auto-add preference is ON; no preference was changed")
            }
        }
    }

    func start(e2e: Bool, requestedRunID: String? = nil, probe: InputProbe? = nil, pointDiagnostic: Bool = false) {
        guard task == nil else { return }
        task = Task { @MainActor in
            defer { self.releaseInputs(); self.task = nil; self.finished() }
            self.directory = nil; self.runID = ""; self.mode = e2e ? "E2E" : "TRANSPORT_SMOKE"
            self.lastFrames = []; self.completedE2E = false; self.phase = "preflight"; self.checkpoints = []; self.e2ePanels = []
            self.displayFrame = nil; self.displayScale = nil
            do {
                self.mode = pointDiagnostic ? "POINT_DIAGNOSTIC_NO_INPUT" :
                    (probe?.resultMode ?? (e2e ? E2EPolicy.mode : "TRANSPORT_SMOKE"))
                let id = requestedRunID ?? UUID().uuidString
                guard HarnessPolicy.validRunID(id) else { throw HarnessError.stop("Invalid requested run ID") }
                let nextDirectory = HarnessConstants.root.appendingPathComponent(id, isDirectory: true)
                try FileManager.default.createDirectory(at: HarnessConstants.root, withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
                // Atomic creation rejects reuse, including an existing/symlinked result directory.
                guard Darwin.mkdir(nextDirectory.path, 0o700) == 0 else {
                    throw HarnessError.stop("Cannot exclusively create new run directory")
                }
                self.runID = id; self.directory = nextDirectory
                self.deadline = ProcessInfo.processInfo.systemUptime + 75
                guard probe == nil || !e2e else { throw HarnessError.stop("An input probe cannot launch Tabbed") }
                guard !pointDiagnostic || (!e2e && probe == nil) else { throw HarnessError.stop("Diagnosis cannot select an input scenario") }
                try self.preflight(e2e: e2e, processProbe: probe.map { !$0.usesSession } ?? false, pointDiagnostic: pointDiagnostic)
                self.log("START — authorized guest run", fields: ["os": ProcessInfo.processInfo.operatingSystemVersionString,
                    "vmFlag": Observation.vmFlag(), "targetSHA256": HarnessConstants.targetSHA256])
                self.fixture = try await self.launch(self.fixtureURL, arguments: ["--run-id", self.runID] +
                    (probe != nil ? ["--process-probe"] : []))
                try self.check()
                let r = try await self.waitForFixture(processProbe: probe != nil)
                self.fixtureRecord = r
                if pointDiagnostic {
                    try await self.runPointDiagnostic(record: r)
                    try self.check()
                    self.writeResult("DIAGNOSTIC_ONLY_NO_INPUT")
                    return // Never reach InputLease, legacy smoke, or Tabbed launch.
                }
                if let probe {
                    try await self.runInputProbe(probe, record: r)
                    try self.check()
                    self.writeResult("PASS")
                    return
                }
                if e2e {
                    try await self.runE2E()
                    try self.check()
                    self.completedE2E = self.writeResult("PASS")
                    return
                }
                _ = try await self.waitForStableGeometry(phase: "after-launch")
                self.log("Fixture PID and both window identifiers verified", fields: ["fixturePID": r.pid,
                    "windowIDs": r.windows.map(\.id)])
                // Activate only our fixture. No AX positions are set by the driver.
                guard self.fixture?.activate(options: []) == true else { throw HarnessError.stop("Fixture activation failed") }
                let before = try await self.waitForStableGeometry(phase: "after-activation")
                guard zip(before, r.windows).allSatisfy({ HarnessPolicy.close($0.0, $0.1.initial.rect) }) else {
                    throw HarnessError.stop("Fixture geometry changed before the gesture")
                }
                let a = before[0], b = before[1]
                let contentA = try GeometryPolicy.contentRegion(r.windows[0], frame: a)
                let contentB = try GeometryPolicy.contentRegion(r.windows[1], frame: b)
                let start = CGPoint(x: contentA.midX, y: contentA.midY)
                let end = e2e ? CGPoint(x: contentB.midX, y: contentB.midY) : CGPoint(x: start.x + 30, y: start.y)
                try await self.gesture(start: start, end: end, e2e: e2e)
                try await self.pause(0.08)
                guard !CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand),
                      !CGEventSource.buttonState(.combinedSessionState, button: .left) else {
                    throw HarnessError.stop("Session still reports Command / left mouse held after release")
                }
                self.log("Session reports Command / left mouse released")
                do {
                    try await self.pause(0.4)
                    let receipts = try JSONDecoder().decode([InputReceipt].self,
                        from: Data(contentsOf: self.directory!.appendingPathComponent("input.json")))
                    guard HarnessPolicy.smokePassed(receipts, windowID: r.windows[0].id) else {
                        throw HarnessError.stop("Fixture did not confirm tagged Command down -> drag -> up")
                    }
                    guard zip(try self.observe(), r.windows).allSatisfy({ HarnessPolicy.close($0.0, $0.1.initial.rect) }) else {
                        throw HarnessError.stop("Unexpected fixture movement in smoke test")
                    }
                }
                try self.check()
                self.log("PASS: fixture received Command drag; Tabbed acceptance is NOT tested")
                try self.check() // A failed final audit write cancels the run; never emit a PASS result then.
                self.writeResult("PASS")
            } catch {
                self.releaseInputs()
                self.log("STOP/FAIL: \(error)")
                self.writeResult("STOP_OR_FAIL: \(error)")
                self.report("No forced termination or window repair. Inspect guest and saved logs.")
            }
        }
    }

    func stop() {
        guard task != nil else { return }
        task?.cancel()
        releaseInputs() // Immediate, independent of the next async cancellation checkpoint.
        report("Stop requested; input release attempted. Test windows and Tabbed are preserved.")
    }
    func closeFixtures() {
        guard task == nil, let fixture, let record = fixtureRecord,
              fixture.processIdentifier == record.pid,
              Observation.canonical(fixture.bundleURL ?? URL(fileURLWithPath: "/")) == Observation.canonical(fixtureURL) else { return }
        _ = fixture.terminate() // Only our known fixture, on a separate explicit user action.
    }
    @discardableResult private func writeResult(_ result: String) -> Bool {
        guard let directory else { return false }
        let output: [String: Any] = ["runID": runID, "mode": mode, "result": result,
            "frames": lastFrames.map { ["x": $0.x, "y": $0.y, "width": $0.width, "height": $0.height] },
            "phase": phase, "checkpoints": checkpoints, "driverPID": getpid(),
            "fixturePID": fixtureRecord?.pid ?? 0, "targetPID": target?.processIdentifier ?? 0,
            "limitations": mode == E2EPolicy.mode ?
                "This run only: real group / drag-out ungroup / regroup / normal Quit and restoration. The x-button path, fault injection, physical keyboard / VM forwarding and other environments remain untested." :
                "Synthetic guest input; this scenario/run only. Tabbed acceptance, physical keyboard / VM forwarding and other scenarios remain unverified. No fault injection in this build."]
        do {
            try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent("result.json"), options: .atomic)
            report("Log directory: Library/Application Support/TabbedGuestHarness/\(runID)")
            return true
        } catch { report("Result file write failed; do not treat this run as auditable success"); return false }
    }
    private func launch(_ url: URL, arguments: [String]) async throws -> NSRunningApplication {
        try check()
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = arguments; config.activates = false
        config.addsToRecentItems = false; config.promptsUserIfNeeded = false
        config.allowsRunningApplicationSubstitution = false
        let waiter = LaunchWaiter()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                waiter.install(continuation)
                if Task.isCancelled { waiter.finish(.failure(CancellationError())); return }
                launchOutstanding = true
                NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
                    Task { @MainActor in
                        self.launchOutstanding = false
                        let result: Result<NSRunningApplication, Error> = app.map { .success($0) }
                            ?? .failure(error ?? HarnessError.stop("Launch failed"))
                        if !waiter.finish(result) {
                            self.report("Late launch callback: process may now be running. No further input or cleanup was performed; inspect guest.")
                        }
                    }
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    waiter.finish(.failure(HarnessError.stop("Launch wait timed out; launch outcome uncertain until callback / guest inspection")))
                }
            }
        }, onCancel: { Task { @MainActor in waiter.finish(.failure(CancellationError())) } })
    }
    private func waitForFixture(processProbe: Bool) async throws -> FixtureRecord {
        for _ in 0..<40 {
            try check()
            if let data = try? Data(contentsOf: directory!.appendingPathComponent("fixture.json")),
               let r = try? JSONDecoder().decode(FixtureRecord.self, from: data) {
                guard r.runID == runID, r.pid == fixture?.processIdentifier, r.processProbe == processProbe,
                      (!processProbe || r.deliveryTraceReady), r.windows.count == 2,
                      Set(r.windows.map(\.id)).count == 2,
                      r.windows.enumerated().allSatisfy({
                          $0.element.id != 0 && $0.element.identifier == "TGH-\(runID)-\($0.offset)" &&
                          $0.element.title == "Tabbed Test \($0.offset == 0 ? "A" : "B") [\(runID)]" &&
                          GeometryPolicy.valid($0.element.initial.rect)
                      }) else {
                    throw HarnessError.stop("Fixture handshake mismatch")
                }
                return r
            }
            try await pause(0.1)
        }
        throw HarnessError.stop("Fixture handshake timeout")
    }
    private struct FixtureSnapshot {
        let elements: [AXUIElement]
        let samples: [GeometrySample]
    }
    private func fixtureSnapshot(requireAgreement: Bool = true) throws -> FixtureSnapshot {
        try check()
        guard NSScreen.screens.count == 1, let screen = NSScreen.main,
              screen.frame == displayFrame, screen.backingScaleFactor == displayScale,
              HarnessPolicy.close(screen.frame, CGDisplayBounds(CGMainDisplayID()), tolerance: 0.5) else {
            throw HarnessError.stop("Display coordinate mapping changed during run")
        }
        guard let record = fixtureRecord, let fixture, !fixture.isTerminated,
              fixture.processIdentifier == record.pid,
              Observation.canonical(fixture.bundleURL ?? URL(fileURLWithPath: "/")) == Observation.canonical(fixtureURL) else {
            throw HarnessError.stop("Fixture process identity changed")
        }
        let app = AXUIElementCreateApplication(record.pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        let elements = Observation.children(app, kAXWindowsAttribute)
        var samples: [GeometrySample] = []
        let verified = try record.windows.map { w in
            let matches = elements.filter {
                AXUIElementSetMessagingTimeout($0, 0.15)
                return Observation.text($0, kAXIdentifierAttribute) == w.identifier && Observation.text($0, kAXTitleAttribute) == w.title
            }
            guard matches.count == 1, let e = matches.first, try Observation.pid(e) == record.pid,
                  Observation.text(e, kAXRoleAttribute) == kAXWindowRole,
                  Observation.text(e, kAXSubroleAttribute) == kAXStandardWindowSubrole else {
                throw HarnessError.stop("Fixture AX PID / identifier / role mismatch")
            }
            AXUIElementSetMessagingTimeout(e, 0.2)
            let ax = try Observation.frame(e)
            let cg = try Observation.windowServer(w.id, pid: record.pid)
            guard GeometryPolicy.valid(ax), GeometryPolicy.valid(cg) else {
                throw HarnessError.stop("Invalid AX / WindowServer geometry")
            }
            samples.append(GeometrySample(pid: record.pid, windowID: w.id, identifier: w.identifier,
                title: w.title, ax: RectRecord(ax), cg: RectRecord(cg)))
            guard !requireAgreement || HarnessPolicy.close(ax, cg) else {
                throw HarnessError.stop("AX / WindowServer geometry disagreement: AX=\(RectRecord(ax)) CG=\(RectRecord(cg))")
            }
            return e
        }
        return FixtureSnapshot(elements: verified, samples: samples)
    }
    private func fixtureElements() throws -> [AXUIElement] { try fixtureSnapshot().elements }
    private func waitForStableGeometry(phase: String) async throws -> [CGRect] {
        guard let record = fixtureRecord else { throw HarnessError.stop("Missing fixture identity") }
        var gate = StableGeometryGate(expected: record)
        let end = ProcessInfo.processInfo.systemUptime + 4
        for index in 0..<25 {
            try check()
            guard ProcessInfo.processInfo.systemUptime < end else { break }
            // Only AX/CG disagreement is allowed to wait here; lookup, identity,
            // permission, display and invalid-frame errors terminate immediately.
            let snapshot = try fixtureSnapshot(requireAgreement: false)
            let time = ProcessInfo.processInfo.systemUptime
            guard time < end else { break }
            let ready = try gate.record(snapshot.samples, at: time)
            let encoded = try JSONEncoder().encode(snapshot.samples)
            log("Startup geometry sample", fields: ["phase": phase, "sample": index,
                "stable": ready, "measurements": try JSONSerialization.jsonObject(with: encoded),
                "displayFrame": ["x": displayFrame!.minX, "y": displayFrame!.minY,
                    "width": displayFrame!.width, "height": displayFrame!.height],
                "backingScale": displayScale!])
            try check()
            if ready {
                let frames = snapshot.samples.map { $0.ax.rect }
                lastFrames = frames.map(RectRecord.init)
                return frames
            }
            try await pause(0.15)
        }
        throw HarnessError.stop("Startup AX / WindowServer geometry did not stabilize within bounded wait; see raw samples")
    }
    private func observe() throws -> [CGRect] {
        // Use the very same AX sample that was checked against CG, not a later AX reread.
        let frames = try fixtureSnapshot().samples.map { $0.ax.rect }
        lastFrames = frames.map(RectRecord.init)
        let app = AXUIElementCreateApplication(fixtureRecord!.pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        let focused = Observation.element(app, kAXFocusedWindowAttribute)
        log("AX + WindowServer observation", fields: ["frames": lastFrames.map {
            ["x": $0.x, "y": $0.y, "width": $0.width, "height": $0.height]
        }, "focusedFixtureIdentifier": focused.flatMap { Observation.text($0, kAXIdentifierAttribute) } ?? "unavailable"])
        return frames
    }
    private func validateTarget() throws {
        guard let target, !target.isTerminated, target.bundleIdentifier == HarnessConstants.targetID,
              Observation.canonical(target.bundleURL ?? URL(fileURLWithPath: "/")) == Observation.canonical(HarnessConstants.target),
              try Observation.hash(HarnessConstants.target.appendingPathComponent("Contents/MacOS/Tabbed")) == HarnessConstants.targetSHA256 else {
            throw HarnessError.stop("Pinned Tabbed process identity changed")
        }
        guard NSWorkspace.shared.runningApplications.filter({ $0.executableURL?.lastPathComponent == "Tabbed" }).allSatisfy({ $0.processIdentifier == target.processIdentifier }) else {
            throw HarnessError.stop("A second Tabbed process appeared")
        }
    }
    private func runPointDiagnostic(record: FixtureRecord) async throws {
        // Reproduce v0.4's activation and point selection, without validation
        // throwing before the raw observations are saved. No input path follows.
        let before = ProcessInfo.processInfo.systemUptime
        let activated = fixture?.activate(options: []) == true
        let after = ProcessInfo.processInfo.systemUptime
        try await pause(0.4)
        let window = record.windows[0]
        let safe = try GeometryPolicy.contentRegion(window, frame: window.initial.rect)
        let point = CGPoint(x: safe.midX, y: safe.midY)
        var snapshot = try PointDiagnostic.capture(point: point, expected: window, fixturePID: record.pid,
            activation: ["startUptime": before, "endUptime": after, "returnedTrue": activated, "waitSeconds": 0.4])
        snapshot["runID"] = runID
        try JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory!.appendingPathComponent("point-diagnostic.json"), options: .withoutOverwriting)
        log("DIAGNOSTIC SAVED: no input events; preserve fixture for a CUA screenshot", fields: [
            "point": ["x": point.x, "y": point.y],
            "v04TopWindowDecision": snapshot["v04TopWindowDecision"]!,
            "firstEligibleCandidate": snapshot["firstEligibleCandidate"] ?? NSNull(),
            "axHit": snapshot["axHit"]!])
    }
    private func runInputProbe(_ scenario: InputProbe, record: FixtureRecord) async throws {
        guard fixture?.activate(options: []) == true else { throw HarnessError.stop("Fixture activation failed") }
        try await pause(0.4)
        let window = record.windows[0]
        let safe = try GeometryPolicy.contentRegion(window, frame: window.initial.rect)
        let start = CGPoint(x: safe.midX, y: safe.midY)
        let end = CGPoint(x: start.x + 30, y: start.y)
        func validate(_ point: CGPoint) throws {
            try check()
            guard NSScreen.screens.count == 1, let screen = NSScreen.main,
                  screen.frame == displayFrame, screen.backingScaleFactor == displayScale,
                  HarnessPolicy.close(screen.frame, CGDisplayBounds(CGMainDisplayID()), tolerance: 0.5) else {
                throw HarnessError.stop("Input probe display mapping changed")
            }
            guard let fixture, !fixture.isTerminated, fixture.processIdentifier == record.pid,
                  Observation.canonical(fixture.bundleURL ?? URL(fileURLWithPath: "/")) == Observation.canonical(fixtureURL),
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == record.pid,
                  CGPreflightPostEventAccess(), safe.contains(point),
                  !NSWorkspace.shared.runningApplications.contains(where: { $0.executableURL?.lastPathComponent == "Tabbed" }) else {
                throw HarnessError.stop("Input probe identity / foreground / permission changed")
            }
            // CG bounds of another process are not its actual hit region (Dock in 0.5).
            // Keep target ID/owner/bounds checks. Session plain-click additionally
            // requires the system-wide AX hit to identify this exact fixture window.
            let frame = try Observation.windowServer(window.id, pid: record.pid)
            guard frame.insetBy(dx: 12, dy: 12).contains(point), Observation.isOnscreen(window.id, pid: record.pid) else {
                throw HarnessError.stop("Input probe point no longer belongs to its fixture window")
            }
            if scenario.usesSession {
                guard AXIsProcessTrusted() else { throw HarnessError.stop("Session probe AX permission changed") }
                let snapshot = try fixtureSnapshot(requireAgreement: false)
                guard let index = record.windows.firstIndex(where: { $0.id == window.id }),
                      try GeometryPolicy.contentRegion(window, frame: snapshot.samples[index].ax.rect).contains(point) else {
                    throw HarnessError.stop("Session probe point is outside current AX blank content")
                }
                try Observation.requireFixtureHit(at: point, window: snapshot.elements[index], pid: record.pid)
            }
        }
        try validate(start)
        guard CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).isEmpty,
              !CGEventSource.buttonState(.combinedSessionState, button: .left) else {
            throw HarnessError.stop("Release physical modifiers / mouse before an input probe")
        }
        let cursor = NSEvent.mouseLocation
        log(scenario.usesSession ? "Session input probe; AX hit verified, not PID-scoped" :
            "Process-only input probe; no session-tap delivery claim", fields: ["scenario": scenario.rawValue,
            "destinationPID": record.pid, "windowID": window.id,
            "point": ["x": start.x, "y": start.y],
            "endPoint": ["x": scenario == .commandDrag ? end.x : start.x, "y": start.y],
            "modifierWaitSeconds": scenario.command ? 0.12 : 0,
            "cursorAppKitBefore": ["x": cursor.x, "y": cursor.y],
            "targetPolicy": scenario.usesSession ?
                "CGSessionEventTap; foreground signed fixture A, AX identity + point hit, current AX content and CG ID/owner/bounds; receiver gate unchanged; TOCTOU remains" :
                "CGEventPostToPid with public mouse window fields set to verified fixture A ID; receiver gate unchanged; no session claim"])
        try check()
        let input = try InputLease(processPID: scenario.usesSession ? nil : record.pid,
            processWindowID: scenario.usesSession ? nil : window.id, command: scenario.command); lease = input
        defer {
            releaseInputs()
            let cursorAfter = NSEvent.mouseLocation
            log("Input probe post calls returned; not a delivery acknowledgement", fields: ["events": input.postAudit(),
                "cursorAppKitAfter": ["x": cursorAfter.x, "y": cursorAfter.y]])
        }
        if scenario.command {
            try validate(start); try input.pressModifier(at: start)
            try await pause(0.12)
        }
        try validate(start); try input.begin(at: start)
        try await pause(0.12)
        if scenario == .commandDrag {
            try validate(end); try input.drag(to: end)
            try await pause(0.12)
        }
        try validate(scenario == .commandDrag ? end : start)
        if scenario.command {
            try input.finishMouse()
            try await pause(0.12)
            try validate(scenario == .commandDrag ? end : start)
        }
        try input.finishNormally(); lease = nil
        try await pause(0.3)
        let receipts = try JSONDecoder().decode([InputReceipt].self,
            from: Data(contentsOf: directory!.appendingPathComponent("input.json")))
        guard HarnessPolicy.probePassed(receipts, scenario: scenario, windowID: window.id,
            fixtureIDs: Set(record.windows.map(\.id))) else {
            throw HarnessError.stop("Fixture did not confirm this exact input probe and release")
        }
        func contentPoint(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x - window.initial.rect.minX - window.contentOffset.rect.minX,
                y: window.contentOffset.rect.height - (point.y - window.initial.rect.minY - window.contentOffset.rect.minY))
        }
        guard HarnessPolicy.probeCoordinatesPassed(receipts, scenario: scenario,
            start: contentPoint(start), end: contentPoint(end)) else {
            throw HarnessError.stop("Fixture coordinates do not confirm the planned blank-content gesture")
        }
        let trace = try JSONDecoder().decode([[String: String]].self,
            from: Data(contentsOf: directory!.appendingPathComponent("fixture-delivery.json")))
        guard trace.count <= 128, trace.first?["stage"] == "output-ready",
              trace.allSatisfy({ $0["pid"] == String(record.pid) }),
              trace.contains(where: { $0["stage"] == "local-monitor-installed" }),
              trace.last(where: { $0["stage"] == "input-write-ok" })?["receiptCount"] == String(receipts.count),
              !trace.contains(where: { $0["stage"] == "input-write-error" }) else {
            throw HarnessError.stop("Fixture diagnostic output did not confirm the complete receipt write")
        }
        guard let fixture, !fixture.isTerminated else { throw HarnessError.stop("Fixture terminated after receipt / diagnostic output") }
        let frames = try record.windows.map { try Observation.windowServer($0.id, pid: record.pid) }
        guard zip(frames, record.windows).allSatisfy({ GeometryPolicy.valid($0.0) &&
            Observation.isOnscreen($0.1.id, pid: record.pid) }) else {
            throw HarnessError.stop("An input probe fixture window is missing or off screen")
        }
        lastFrames = frames.map(RectRecord.init)
        log(scenario.usesSession ? "PASS: session \(scenario.rawValue) receipt, flags, coordinates and release; Tabbed remains untested" :
            "PASS: process-only fixture receipt; session transport and Tabbed remain untested")
    }
    private func validateEventPoint(_ p: CGPoint, e2e: Bool) throws {
        let snapshot = try fixtureSnapshot()
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess(), let r = fixtureRecord,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == r.pid else {
            throw HarnessError.stop("Permission or foreground fixture changed")
        }
        if e2e { try validateTarget() }
        else if NSWorkspace.shared.runningApplications.contains(where: { $0.executableURL?.lastPathComponent == "Tabbed" }) {
            throw HarnessError.stop("Tabbed appeared during smoke test")
        }
        let id = try Observation.topWindow(at: p, allowed: Set(r.windows.map(\.id)), pid: r.pid,
            overlayPID: e2e && lease != nil ? target?.processIdentifier : nil,
            overlayFrame: e2e && lease != nil ? r.windows[1].initial.rect : nil)
        guard let index = r.windows.firstIndex(where: { $0.id == id }),
              try GeometryPolicy.contentRegion(r.windows[index], frame: snapshot.samples[index].ax.rect).contains(p),
              snapshot.samples[index].cg.rect.insetBy(dx: 12, dy: 12).contains(p) else {
            throw HarnessError.stop("Event point is outside verified blank fixture content")
        }
        // System-wide AX hit testing honors z-order. An overlay that hides the
        // fixture from AX stops the run; no new overlay exemption is introduced.
        try Observation.requireFixtureHit(at: p, window: snapshot.elements[index], pid: r.pid)
    }
    private func releaseInputs() {
        // No events at startup / preflight failure. Release only input this run attempted to hold.
        lease?.release(); lease = nil
    }
    private func gesture(start: CGPoint, end: CGPoint, e2e: Bool) async throws {
        defer { releaseInputs() }
        try validateEventPoint(start, e2e: e2e)
        let physicalFlags = CGEventSource.flagsState(.combinedSessionState)
        guard physicalFlags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).isEmpty,
              !CGEventSource.buttonState(.combinedSessionState, button: .left) else {
            throw HarnessError.stop("Release physical modifiers / mouse before starting")
        }
        let input = try InputLease(); lease = input
        try input.begin(at: start)
        log("Command + mouseDown posted (delivery not yet proven)")
        for p in [CGPoint(x: start.x + 12, y: start.y), end, end] {
            try await pause(0.12)
            try validateEventPoint(p, e2e: e2e)
            try input.drag(to: p)
        }
        try await pause(0.12)
        try validateEventPoint(end, e2e: e2e)
        try input.finishNormally()
        log("Gesture finished; Command release posted")
    }
    private func e2eVisibleFrame() throws -> CGRect {
        guard let screen = NSScreen.main else { throw HarnessError.stop("Missing E2E display") }
        let v=screen.visibleFrame
        return CGRect(x:v.minX,y:screen.frame.maxY-v.maxY,width:v.width,height:v.height)
    }
    private func e2eState(_ label: String) throws -> [E2EWindowState] {
        let snapshot=try fixtureSnapshot(requireAgreement:false)
        let rows=try zip(snapshot.elements,snapshot.samples).map { element,sample in
            E2EWindowState(geometry:sample,
                minimized:(try Observation.attribute(element,kAXMinimizedAttribute) as? NSNumber)?.boolValue ?? true,
                onscreen:Observation.isOnscreen(sample.windowID,pid:sample.pid))
        }
        lastFrames=rows.map { $0.geometry.cg }
        let encoded=try JSONEncoder().encode(rows)
        var checkpoint:[String:Any]=["phase":label,"uptime":ProcessInfo.processInfo.systemUptime,
            "windows":try JSONSerialization.jsonObject(with:encoded),"targetPID":target?.processIdentifier ?? 0,
            "targetTerminated":target?.isTerminated ?? true]
        let visible=try e2eVisibleFrame()
        checkpoint["visibleFrame"]=["x":visible.minX,"y":visible.minY,"width":visible.width,"height":visible.height]
        checkpoint["displayScale"]=displayScale!
        e2ePanels=try target.map { try Observation.targetPanels(pid:$0.processIdentifier) } ?? []
        checkpoint["ownedTargetPanels"]=try JSONSerialization.jsonObject(with:JSONEncoder().encode(e2ePanels))
        checkpoints.append(checkpoint)
        try JSONSerialization.data(withJSONObject:checkpoints,options:[.prettyPrinted,.sortedKeys])
            .write(to:directory!.appendingPathComponent("e2e-checkpoints.json"),options:.atomic)
        log("E2E observation",fields:checkpoint)
        try check()
        return rows
    }
    private func awaitE2E(_ label:String, condition:([E2EWindowState])->Bool) async throws -> [E2EWindowState] {
        // Three stable observations, each API relative to itself, over >=0.3s.
        // A missing/changed identity or AX error throws immediately, never retries input.
        var anchor:[E2EWindowState]?
        var since=0.0, count=0
        for _ in 0..<18 {
            let rows=try e2eState(label), time=ProcessInfo.processInfo.systemUptime
            if condition(rows) {
                if let a=anchor, E2EPolicy.stable(rows,a) { count += 1 }
                else { anchor=rows; since=time; count=1 }
                if count>=3 && time-since>=0.3 { return rows }
            } else { anchor=nil; count=0 }
            try await pause(0.15)
        }
        throw HarnessError.stop("E2E condition / stable observation failed at \(label)")
    }
    private func e2eSafePoint(_ index:Int) throws -> CGPoint {
        guard let record=fixtureRecord else { throw HarnessError.stop("Missing E2E fixture") }
        let snapshot=try fixtureSnapshot(requireAgreement:false)
        let safe=try GeometryPolicy.contentRegion(record.windows[index],frame:snapshot.samples[index].ax.rect)
            .intersection(snapshot.samples[index].cg.rect.insetBy(dx:12,dy:12))
        guard GeometryPolicy.valid(safe) else { throw HarnessError.stop("No common safe blank region") }
        let point=CGPoint(x:safe.midX,y:safe.midY)
        try Observation.requireFixtureHit(at:point,window:snapshot.elements[index],pid:record.pid)
        return point
    }
    private func requireE2EInputPoint(_ point:CGPoint) throws {
        try check(); try validateTarget()
        let snapshot=try fixtureSnapshot(requireAgreement:false)
        guard let record=fixtureRecord, AXIsProcessTrusted(), CGPreflightPostEventAccess(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier==record.pid,
              try GeometryPolicy.contentRegion(record.windows[0],frame:snapshot.samples[0].ax.rect).contains(point),
              snapshot.samples[0].cg.rect.insetBy(dx:12,dy:12).contains(point),
              Observation.isOnscreen(record.windows[0].id,pid:record.pid) else {
            throw HarnessError.stop("E2E foreground / permission / current source content changed")
        }
        // Every incremental point must still hit the actual, moving source A.
        // No CG z-order heuristic, Dock exclusion, overlay bypass or rectangle equality.
        try Observation.requireFixtureHit(at:point,window:snapshot.elements[0],pid:record.pid)
    }
    private func requireReleased() throws {
        guard CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand,.maskAlternate,.maskControl,.maskShift]).isEmpty,
              !CGEventSource.buttonState(.combinedSessionState,button:.left) else {
            throw HarnessError.stop("E2E session reports a held modifier / left mouse")
        }
    }
    private func e2eGesture(to end:CGPoint, label:String) async throws {
        guard fixture?.activate(options:[])==true else { throw HarnessError.stop("Fixture activation failed") }
        try await pause(0.15)
        let start=try e2eSafePoint(0), points=try E2EPolicy.dragPoints(from:start,to:end)
        try requireReleased(); try requireE2EInputPoint(start)
        let input=try InputLease(); lease=input
        let began=ProcessInfo.processInfo.systemUptime
        defer {
            releaseInputs()
            log("E2E gesture audit",fields:["gesture":label,"events":input.postAudit()])
        }
        try input.pressModifier(at:start); try await pause(0.12)
        try requireE2EInputPoint(start); try input.begin(at:start)
        for point in points {
            try await pause(0.12); try requireE2EInputPoint(point); try input.drag(to:point)
        }
        try await pause(0.12); try requireE2EInputPoint(end); try input.finishMouse()
        try await pause(0.12); try requireE2EInputPoint(end); try input.finishNormally(); lease=nil
        try await pause(0.15); try requireReleased()
        let audit=input.postAudit().filter { $0["phase"]=="before-post" }
        let expected=["12","1"]+Array(repeating:"6",count:points.count)+["2","12"]
        guard audit.map({$0["type"] ?? ""})==expected,
              audit.enumerated().allSatisfy({ i,row in
                  row["transport"]=="session" && row["requestedPID"]=="none" &&
                  row["flags"]==(i==audit.count-1 ? "0" : "1048576")
              }) else { throw HarnessError.stop("Incomplete E2E input posting / release audit") }
        let rows=try JSONDecoder().decode([InputReceipt].self,from:Data(contentsOf:directory!.appendingPathComponent("input.json")))
        let flags=rows.filter { $0.tag==HarnessConstants.eventTag && $0.type=="flags" && $0.time>=began }
        guard let record=fixtureRecord, let first=flags.first,let last=flags.last,flags.count>=2,
              first.command && first.flags==CGEventFlags.maskCommand.rawValue,
              !last.command && last.flags==0 && last.time>first.time,
              flags.allSatisfy({record.windows.map(\.id).contains($0.windowID)}) else {
            throw HarnessError.stop("Fixture did not confirm this gesture's Command press / release")
        }
        log("E2E gesture released; Tabbed may consume drag/up, judged by external state",fields:["gesture":label])
        try check()
    }
    private func runE2E() async throws {
        guard let record=fixtureRecord else { throw HarnessError.stop("Missing E2E fixture") }
        let visible=try e2eVisibleFrame()
        phase="baseline"
        let baseline=try await awaitE2E(phase) { $0.count==2 && $0.allSatisfy { E2EPolicy.visible($0,in:visible) } }
        guard fixture?.activate(options:[])==true else { throw HarnessError.stop("Fixture activation failed") }
        try await pause(0.15)
        let originalStart=try e2eSafePoint(0)
        phase="target-launch"
        log("Launching only the pinned production build",fields:["targetSHA256":HarnessConstants.targetSHA256])
        try check()
        target=try await launch(HarnessConstants.target,arguments:[])
        try validateTarget()
        for _ in 0..<20 {
            if Observation.targetDragTapReady(pid:target!.processIdentifier) { break }
            try await pause(0.2)
        }
        guard Observation.targetDragTapReady(pid:target!.processIdentifier) else {
            throw HarnessError.stop("Pinned Tabbed drag tap not ready; no input sent")
        }
        phase="group"
        let drop=try e2eSafePoint(1)
        try await e2eGesture(to:drop,label:phase)
        _ = try await awaitE2E(phase) {
            E2EPolicy.grouped($0,at:baseline[1],in:visible) && E2EPolicy.stripCandidates(self.e2ePanels,at:baseline[1]).count==1
        }
        let originalStrip=E2EPolicy.stripCandidates(e2ePanels,at:baseline[1])[0].id
        phase="ungroup-drag-out"
        // Same real Cmd-drag path, ending away from B. This exercises remove+dissolve,
        // not the hover-only x / untab-offset path. No window repair or internal calls.
        try await e2eGesture(to:originalStart,label:phase)
        _ = try await awaitE2E(phase) {
            E2EPolicy.separated($0,baseline:baseline,in:visible) &&
                !self.e2ePanels.contains(where:{$0.id==originalStrip}) &&
                E2EPolicy.stripCandidates(self.e2ePanels,at:baseline[1]).isEmpty
        }
        phase="regroup"
        // Recheck B's current real blank hit before the source can cover it.
        let secondDrop=try e2eSafePoint(1)
        try await e2eGesture(to:secondDrop,label:phase)
        _ = try await awaitE2E(phase) {
            E2EPolicy.grouped($0,at:baseline[1],in:visible) && E2EPolicy.stripCandidates(self.e2ePanels,at:baseline[1]).count==1
        }
        phase="normal-quit"
        try validateTarget(); try requireReleased()
        let app=AXUIElementCreateApplication(target!.processIdentifier)
        AXUIElementSetMessagingTimeout(app,0.2)
        guard let menu=Observation.find(app,pid:target!.processIdentifier,title:"Tabbed",role:kAXMenuBarItemRole),
              AXUIElementPerformAction(menu,kAXPressAction as CFString) == .success else {
            throw HarnessError.stop("Cannot press exact pinned Tabbed status menu; no coordinate fallback")
        }
        try await pause(0.25); try validateTarget()
        guard let quit=Observation.find(app,pid:target!.processIdentifier,title:"Quit Tabbed",role:kAXMenuItemRole),
              AXUIElementPerformAction(quit,kAXPressAction as CFString) == .success else {
            throw HarnessError.stop("Cannot invoke exact normal Quit item; no terminate/kill fallback")
        }
        log("Normal Quit menu invoked"); try check()
        for _ in 0..<45 {
            if target!.isTerminated { break }; try await pause(0.2)
        }
        guard target!.isTerminated else { throw HarnessError.stop("Tabbed still running / restoration alert; preserve guest") }
        try Observation.requireNoTargetTaps(pid:target!.processIdentifier)
        phase="quit-restored"
        for _ in 0..<3 {
            try await pause(0.3)
            guard E2EPolicy.restored(try e2eState(phase),at:baseline[1],in:visible) else {
                throw HarnessError.stop("Quit left a fixture missing, parked, minimized or at the wrong group frame")
            }
        }
        try requireReleased()
        guard !NSWorkspace.shared.runningApplications.contains(where:{$0.executableURL?.lastPathComponent=="Tabbed"}) else {
            throw HarnessError.stop("A Tabbed process remains after Quit")
        }
        phase="fixture-cleanup"
        guard let fixture,!fixture.isTerminated,fixture.processIdentifier==record.pid,
              let fixtureBundle=fixture.bundleURL,Observation.canonical(fixtureBundle)==Observation.canonical(fixtureURL),fixture.terminate() else {
            throw HarnessError.stop("Cannot normally close this run's fixture; no forced cleanup")
        }
        for _ in 0..<25 { if fixture.isTerminated { break }; try await pause(0.1) }
        guard fixture.isTerminated,
              NSRunningApplication.runningApplications(withBundleIdentifier:HarnessConstants.fixtureID).isEmpty else {
            throw HarnessError.stop("Fixture remains after normal cleanup")
        }
        phase="complete"
        log("PASS: real grouping, drag-out ungrouping, regrouping, normal Quit, restoration and fixture cleanup")
        try check()
    }
}
