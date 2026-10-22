import AppKit

@MainActor
final class DriverDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let runner = Runner()
    var window: NSWindow!
    let consent = NSButton(checkboxWithTitle: "I confirm: isolated disposable guest VM, no other work. Start explicitly authorizes this run.", target: nil, action: nil)
    let smoke = NSButton(title: "1. Start transport smoke (no Tabbed)", target: nil, action: nil)
    let e2e = NSButton(title: "2. E2E group / drag-out / regroup / Quit", target: nil, action: nil)
    let stop = NSButton(title: "STOP / release input", target: nil, action: nil)
    let close = NSButton(title: "Close this run's test windows", target: nil, action: nil)
    let output = NSTextView()
    var diagnosticOnly = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        let invocation = GuestInvocation.parse(Array(CommandLine.arguments.dropFirst()))
        if case .pointDiagnostic = invocation { diagnosticOnly = true }
        window = NSWindow(contentRect: CGRect(x: 30, y: 380, width: 950, height: 310),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Tabbed Guest Harness — EXPLICIT START REQUIRED"
        window.delegate = self; window.isReleasedWhenClosed = false
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 8
        root.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        window.contentView = root
        let purpose: String
        if diagnosticOnly {
            purpose = "READ-ONLY POINT DIAGNOSIS: fixture launch + CG metadata + AX hit. No input events.\n" +
                "No screenshots or permission requests by this app; existing guest AX permission only."
        } else if case .probe(let scenario, _) = invocation {
            purpose = scenario.usesSession ?
                "Stage 2: \(scenario.rawValue) via SESSION; AX hit must identify signed fixture A. No Tabbed.\nGuest AX + event-post required; session input is not PID-scoped. Stop on first failure." :
                "Stage 2: \(scenario.rawValue), only the signed fixture PID. No Tabbed launch.\nOnly guest event-post permission is preflighted; no AX/CG rectangle matching."
        } else {
            purpose = "Legacy session smoke / deferred E2E. Target: \(HarnessConstants.target.path)\n" +
                "Pinned executable SHA256: \(HarnessConstants.targetSHA256)"
        }
        let summary = NSTextField(wrappingLabelWithString:
            "OS: \(ProcessInfo.processInfo.operatingSystemVersionString) | arch: arm64 | VM flag: \(Observation.vmFlag())\n" +
            purpose + "\n" +
            "Needs one >=1100×700-point display and guest permissions. Harness only preflights; Tabbed itself may prompt at launch. No network/account/password operations.")
        root.addArrangedSubview(summary); root.addArrangedSubview(consent)
        let buttons = NSStackView(views: [smoke, e2e, stop, close]); buttons.spacing = 8
        root.addArrangedSubview(buttons)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.documentView = output
        output.isEditable = false; output.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        output.isVerticallyResizable = true; output.autoresizingMask = [.width]
        root.addArrangedSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([scroll.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -24), scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 90)])
        smoke.target = self; smoke.action = #selector(startSmoke)
        e2e.target = self; e2e.action = #selector(startE2E)
        stop.target = self; stop.action = #selector(stopRun)
        close.target = self; close.action = #selector(closeFixtures)
        runner.report = { [weak self] text in self?.append(text) }
        runner.finished = { [weak self] in
            self?.setRunning(false)
            if case .e2e = invocation, self?.runner.completedE2E == true { NSApp.terminate(nil) }
        }
        // Ordinary launch is UI only. Only the exact CLI invocation below requests a run.
        append("READY. Not yet tested in a guest. Stop does not undo grouping; failure preserves evidence.")
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        switch invocation {
        case .manual: break
        case .invalid:
            append("STOP: invalid invocation. No run started. Use an exact confirmed smoke or process-probe invocation.")
        case .smoke(let id):
            // Script execution is an explicit start. Never infer consent from an environment variable.
            consent.state = .on
            append("Explicit script start: smoke only; run ID \(id)")
            begin(e2e: false, requestedRunID: id)
        case .e2e(let id):
            consent.state = .on
            append("Explicit E2E: group / drag-out ungroup / regroup / normal Quit. Run ID \(id)")
            begin(e2e:true, requestedRunID:id)
        case .probe(let scenario, let id):
            consent.state = .on
            append("Explicit probe: \(scenario.rawValue); mode \(scenario.resultMode). Run ID \(id)")
            begin(e2e: false, requestedRunID: id, probe: scenario)
        case .pointDiagnostic(let id):
            consent.state = .on
            append("Explicit read-only point diagnosis; no event posting. Run ID \(id)")
            begin(e2e: false, requestedRunID: id, pointDiagnostic: true)
        }
    }
    func append(_ s: String) {
        output.textStorage?.append(NSAttributedString(string: s + "\n"))
        output.scrollToEndOfDocument(nil)
    }
    func setRunning(_ b: Bool) { smoke.isEnabled = !b && !diagnosticOnly; e2e.isEnabled = !b && !diagnosticOnly; close.isEnabled = !b; consent.isEnabled = !b }
    func begin(e2e: Bool, requestedRunID: String? = nil, probe: InputProbe? = nil, pointDiagnostic: Bool = false) {
        guard !diagnosticOnly || (pointDiagnostic && !e2e && probe == nil) else {
            append("STOP: diagnostic invocation cannot start an input test"); return
        }
        guard consent.state == .on, !runner.running else { append("Confirm the guest-only checkbox first."); return }
        // Keep the Stop control above fixture windows. Only our dashboard is moved.
        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            window.setFrame(CGRect(x: v.minX + 15, y: v.maxY - 315, width: 950, height: 310), display: true)
        }
        setRunning(true); runner.start(e2e: e2e, requestedRunID: requestedRunID, probe: probe, pointDiagnostic: pointDiagnostic)
    }
    @objc func startSmoke() { begin(e2e: false) }
    @objc func startE2E() { begin(e2e: true) }
    @objc func stopRun() { runner.stop() }
    @objc func closeFixtures() { runner.closeFixtures() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if runner.running { runner.stop(); append("Run stopping; choose Quit again after completion."); return .terminateCancel }
        return .terminateNow
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { NSApp.terminate(nil); return false }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = DriverDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
