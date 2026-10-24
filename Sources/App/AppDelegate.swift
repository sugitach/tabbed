import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var autoAddMenuItem: NSMenuItem?
    private var compactModeMenuItem: NSMenuItem?
    private var monitoringStatusItem: NSMenuItem?
    private var permissionTimer: Timer?
    private var accessibilityHelpPanel: AccessibilityHelpPanel?
    private var monitoringStarted = false
    private var nextMonitoringAttempt = Date.distantPast
    private lazy var codeSignature = AppCodeSignature.current()
    private var appBundleURL: URL { Bundle.main.bundleURL }
    private let engine = AXWindowEngine()
    private lazy var controller = TabGroupController(engine: engine)
    private var quitWithoutRestoring = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        TabbedConfig.ensureFileExists()
        setUpStatusItem()

        let trusted = AXIsProcessTrusted()
        NSLog("[Tabbed] accessibility trusted = \(trusted)")
        // The system prompt is asynchronous. Observe the actual grant rather
        // than requiring the user to quit and relaunch after changing Settings.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccessibilityStartup() }
        }
        permissionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .modalPanel)
        // Install global observers after AppKit has finished its launch turn.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.controller.isStopping else { return }
            self.refreshAccessibilityStartup()
            if !AXIsProcessTrusted() { self.showAccessibilityHelp() }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        stopPermissionPolling()
        showMonitoringStatus("Window management stopped", active: false)
        guard !quitWithoutRestoring else { return .terminateNow }
        let failures = controller.restoreWindowsForTermination()
        guard !failures.isEmpty else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Some windows could not be restored"
        alert.informativeText = "Window management is stopped. Keep Tabbed open to retry restoration later, or choose Quit Without Restoring… to exit without further window changes.\n\n"
            + failures.map { "\($0.appName): \($0.title)" }.joined(separator: "\n")
        alert.addButton(withTitle: "Keep Open")
        alert.addButton(withTitle: "Quit Without Restoring…")
        if alert.runModal() == .alertSecondButtonReturn {
            let confirmation = NSAlert()
            confirmation.messageText = "Quit without restoring all windows?"
            confirmation.informativeText = "Window management is already stopped. Tabbed will quit without making any further changes to your windows. Unrestored windows may remain offscreen; check that you can access them before quitting."
            // Cancel is the default. Only explicit confirmation allows exit.
            confirmation.addButton(withTitle: "Cancel")
            confirmation.addButton(withTitle: "Quit Without Restoring")
            if confirmation.runModal() == .alertSecondButtonReturn {
                quitWithoutRestoring = true
                return .terminateNow
            }
        }

        let stoppedAlert = NSAlert()
        stoppedAlert.messageText = "Tabbed is still running"
        stoppedAlert.informativeText = "Window management and ⌘-drag are stopped. The app has not quit.\n\nSome windows may still need restoration. Choose Quit Tabbed from the menu bar to retry, or choose Quit Without Restoring… in the warning to exit without further window changes."
        stoppedAlert.addButton(withTitle: "OK")
        stoppedAlert.runModal()
        return .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopPermissionPolling()
        // Respect the confirmed escape path: a fallback must not move windows
        // again after the user explicitly chose to leave them as they are.
        guard !quitWithoutRestoring else { return }
        // Fallback for normal termination notifications; no guarantee after SIGKILL/crash.
        let failures = controller.restoreWindowsForTermination()
        if !failures.isEmpty {
            NSLog("[Tabbed] termination restoration failed for %d windows", failures.count)
        }
    }

    // MARK: - Status bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle.angled",
                                     accessibilityDescription: "Tabbed")
        let menu = NSMenu()
        monitoringStatusItem = menu.addItem(withTitle: "Waiting for Accessibility Permission…", action: nil, keyEquivalent: "")
        item.button?.appearsDisabled = true
        menu.addItem(.separator())
        let autoAddItem = menu.addItem(
            withTitle: "Auto-add New Windows to Stack",
            action: #selector(toggleAutoAddNewWindowsToStack),
            keyEquivalent: ""
        )
        autoAddItem.target = self
        autoAddItem.state = AppSettings.autoAddNewWindowsToStack ? .on : .off
        autoAddMenuItem = autoAddItem

        let compactItem = menu.addItem(
            withTitle: "Always Use Compact Mode",
            action: #selector(toggleAlwaysUseCompactMode),
            keyEquivalent: ""
        )
        compactItem.target = self
        compactItem.state = AppSettings.alwaysUseCompactMode ? .on : .off
        compactModeMenuItem = compactItem

        menu.addItem(.separator())
        menu.addItem(withTitle: "Edit Configuration…",
                     action: #selector(editConfig), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Reload Configuration",
                     action: #selector(reloadConfig), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Accessibility Settings…",
                     action: #selector(openAXSettings), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Recheck Accessibility Permission",
                     action: #selector(recheckAccessibilityPermission), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Accessibility Permission Help…",
                     action: #selector(showAccessibilityHelp), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Tabbed",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleAutoAddNewWindowsToStack() {
        let enabled = !controller.autoAddNewWindowsToStack
        controller.setAutoAddNewWindowsToStack(enabled)
        autoAddMenuItem?.state = enabled ? .on : .off
    }

    @objc private func toggleAlwaysUseCompactMode() {
        let enabled = !controller.alwaysUseCompactMode
        controller.setAlwaysUseCompactMode(enabled)
        compactModeMenuItem?.state = enabled ? .on : .off
    }

    @objc private func reloadConfig() {
        controller.reloadConfig()
    }

    @objc private func editConfig() {
        NSWorkspace.shared.open(TabbedConfig.ensureFileExists())
    }

    @objc private func openAXSettings() {
        // Register/request access only as a result of an explicit user action.
        // Let the system prompt's Open System Settings button handle navigation.
        // Opening Settings here would leave the asynchronous prompt unanswered.
        _ = ensureAccessibilityPermission()
    }

    // MARK: - Permissions

    @objc private func showAccessibilityHelp() {
        guard !controller.isStopping else { return }
        guard !AXIsProcessTrusted() else {
            refreshAccessibilityStartup()
            return
        }
        if let panel = accessibilityHelpPanel {
            presentAccessibilityHelp(panel)
            return
        }
        let panel = AccessibilityHelpPanel(
            information: codeSignature.accessibilityRecoveryMessage(appPath: appBundleURL.path)
        ) { [weak self] response in self?.handleAccessibilityHelpResponse(response) }
        accessibilityHelpPanel = panel
        presentAccessibilityHelp(panel)
    }

    private func presentAccessibilityHelp(_ panel: AccessibilityHelpPanel) {
        // An accessory app may be inactive when launched. Ordering a key
        // window alone need not bring it above the current foreground app.
        // Only initial presentation and an explicit Help request activate us;
        // permission polling must leave Settings and other apps in front.
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.window.makeKeyAndOrderFront(nil)
        panel.window.orderFrontRegardless()
    }

    private func handleAccessibilityHelpResponse(_ response: NSApplication.ModalResponse) {
        guard !controller.isStopping else { return }
        if response == .alertFirstButtonReturn {
            openAXSettings()
        } else if response == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([appBundleURL])
        } else {
            accessibilityHelpPanel?.window.orderOut(nil)
            accessibilityHelpPanel = nil
        }
    }

    private func refreshAccessibilityStartup(now: Date = Date()) {
        guard !monitoringStarted, !controller.isStopping else { return }
        guard AXIsProcessTrusted() else {
            showMonitoringStatus("Waiting for Accessibility Permission…", active: false)
            return
        }
        // Trust can become visible before observers can be installed. Retry
        // without repeatedly prompting, relaunching, or claiming readiness.
        guard now >= nextMonitoringAttempt else { return }
        nextMonitoringAttempt = now.addingTimeInterval(5)
        guard controller.start() else {
            showMonitoringStatus("Could not start event monitoring; retrying…", active: false)
            return
        }
        monitoringStarted = true
        stopPermissionPolling()
        showMonitoringStatus("Tabbed — Window management active", active: true)
        accessibilityHelpPanel?.window.orderOut(nil)
        accessibilityHelpPanel = nil
        NSLog("[Tabbed] controller started — global ⌘-drag monitor active")
    }

    private func stopPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    private func showMonitoringStatus(_ title: String, active: Bool) {
        monitoringStatusItem?.title = title
        statusItem?.button?.appearsDisabled = !active
    }

    @objc private func recheckAccessibilityPermission() {
        nextMonitoringAttempt = .distantPast
        refreshAccessibilityStartup()
    }

    private func ensureAccessibilityPermission() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
