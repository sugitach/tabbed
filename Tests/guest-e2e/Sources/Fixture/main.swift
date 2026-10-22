import AppKit

// Fixture only: no global event taps, event posting, AX control, network or subprocesses.
final class FixtureWindow: NSWindow {
    var recordInput: ((NSEvent) -> Bool)?
    override func sendEvent(_ event: NSEvent) {
        if recordInput?(event) == false { return }
        super.sendEvent(event)
    }
}

final class BlankView: NSView {
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
}

@MainActor
final class FixtureDelegate: NSObject, NSApplicationDelegate {
    var windows: [FixtureWindow] = []
    var directory: URL!
    var receipts: [InputReceipt] = []
    var deliveryTrace: DeliveryTrace?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = Array(CommandLine.arguments.dropFirst())
        // Only the driver's explicit launch supplies the run UUID.
        guard let invocation = FixtureInvocation.parse(args),
              NSScreen.screens.count == 1, let screen = NSScreen.main,
              screen.visibleFrame.width >= 1100, screen.visibleFrame.height >= 700 else {
            NSApp.terminate(nil); return
        }
        let runID = invocation.runID
        directory = HarnessConstants.root.appendingPathComponent(runID, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path),
              !FileManager.default.fileExists(atPath: directory.appendingPathComponent("fixture.json").path) else {
            NSApp.terminate(nil); return
        }
        if invocation.processProbe {
            do {
                let trace = try DeliveryTrace(directory: directory)
                guard trace.install() else { NSApp.terminate(nil); return }
                deliveryTrace = trace
            } catch { NSApp.terminate(nil); return }
        }
        let visible = screen.visibleFrame
        let screenTop = screen.frame.maxY
        var records: [WindowRecord] = []
        for i in 0..<2 {
            let ident = "TGH-\(runID)-\(i)"
            let title = "Tabbed Test \(i == 0 ? "A" : "B") [\(runID)]"
            let w = FixtureWindow(contentRect: .zero,
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            w.title = title; w.setAccessibilityIdentifier(ident)
            // Suppress AppKit's inferred orderFront animation for this fixture only.
            // The driver must still independently sample AX + WindowServer stability.
            w.animationBehavior = .none
            w.isReleasedWhenClosed = false
            w.setFrame(CGRect(x: visible.minX + 30 + CGFloat(i) * 440,
                              y: visible.minY + 55, width: 360, height: 270), display: true)
            let content = BlankView(frame: .zero)
            content.wantsLayer = true
            content.layer?.backgroundColor = (i == 0 ? NSColor.systemBlue : NSColor.systemGreen).cgColor
            w.contentView = content
            w.recordInput = { [weak self, weak w] e in
                guard let self, let w else { return false }
                guard self.deliveryTrace?.event("window-entry", e, receiver: w.windowNumber) != false else { return false }
                let type: String
                switch e.type { case .leftMouseDown: type = "down"; case .leftMouseDragged: type = "drag"
                case .leftMouseUp: type = "up"; case .flagsChanged: type = "flags"; default: return true }
                let tag = e.cgEvent?.getIntegerValueField(.eventSourceUserData) ?? 0
                var accepted = true
                var contentPoint: CGPoint?
                var blankHit: Bool?
                if invocation.processProbe && type != "flags" {
                    // In process-only mode, allow only tagged input inside A's
                    // blank content before standard dispatch. Missing tags,
                    // titlebars, controls and the other window are rejected.
                    // hitTest takes superview coordinates; bounds uses view coordinates.
                    let local = content.convert(e.locationInWindow, from: nil)
                    let parent = content.superview?.convert(e.locationInWindow, from: nil) ?? e.locationInWindow
                    contentPoint = local
                    blankHit = content.hitTest(parent) === content
                    accepted = HarnessPolicy.acceptProcessMouse(tag: tag, windowID: UInt32(w.windowNumber),
                        expectedWindowID: self.windows.first.map { UInt32($0.windowNumber) } ?? 0,
                        pointInContent: local, bounds: content.bounds, hitIsBlank: blankHit == true)
                }
                var receipt = InputReceipt(type: accepted ? type : "rejected-" + type, windowID: UInt32(w.windowNumber),
                    command: e.modifierFlags.contains(.command),
                    tag: tag,
                    time: ProcessInfo.processInfo.systemUptime)
                receipt.flags = UInt64(e.modifierFlags.rawValue)
                if let contentPoint {
                    receipt.contentX = contentPoint.x; receipt.contentY = contentPoint.y
                    receipt.receiverBounds = RectRecord(content.bounds); receipt.blankHit = blankHit
                }
                guard self.deliveryTrace?.record("receiver-decision", ["type": type, "accepted": String(accepted),
                    "tag": String(tag), "receiverWindow": String(w.windowNumber),
                    "expectedWindow": self.windows.first.map { String($0.windowNumber) } ?? "nil",
                    "contentX": contentPoint.map { String(describing: $0.x) } ?? "n/a",
                    "contentY": contentPoint.map { String(describing: $0.y) } ?? "n/a",
                    "contentBounds": String(describing: content.bounds),
                    "blankHit": blankHit.map { String($0) } ?? "n/a"]) != false else { return false }
                self.receipts.append(receipt)
                if self.receipts.count > 200 { self.receipts.removeFirst() }
                do {
                    guard self.deliveryTrace?.record("input-write-start") != false else { return false }
                    try JSONEncoder().encode(self.receipts).write(to: self.directory.appendingPathComponent("input.json"), options: .atomic)
                    guard self.deliveryTrace?.record("input-write-ok", ["receiptCount": String(self.receipts.count)]) != false else { return false }
                } catch {
                    self.deliveryTrace?.record("input-write-error", ["error": String(describing: error)])
                    NSApp.terminate(nil); return false
                }
                return accepted
            }
            w.makeKeyAndOrderFront(nil)
            let r = w.frame
            let c = w.convertToScreen(content.convert(content.bounds, to: nil))
            records.append(WindowRecord(id: UInt32(w.windowNumber), identifier: ident, title: title,
                initial: RectRecord(CGRect(x: r.minX, y: screenTop-r.maxY, width: r.width, height: r.height)),
                contentOffset: RectRecord(CGRect(x: c.minX-r.minX, y: r.maxY-c.maxY,
                                                width: c.width, height: c.height))))
            windows.append(w)
        }
        do {
            try JSONEncoder().encode(FixtureRecord(runID: runID, pid: getpid(), windows: records, processProbe: invocation.processProbe,
                deliveryTraceReady: deliveryTrace?.ready == true))
                .write(to: directory.appendingPathComponent("fixture.json"), options: .atomic)
        } catch { NSApp.terminate(nil) }
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { deliveryTrace?.stop() }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = FixtureDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
