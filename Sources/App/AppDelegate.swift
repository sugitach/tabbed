import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var autoAddMenuItem: NSMenuItem?
    private var compactModeMenuItem: NSMenuItem?
    private let engine = AXWindowEngine()
    private lazy var controller = TabGroupController(engine: engine)
    private var quitWithoutRestoring = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        TabbedConfig.ensureFileExists()
        setUpStatusItem()

        let trusted = ensureAccessibilityPermission()
        NSLog("[Tabbed] accessibility trusted = \(trusted)")
        guard trusted else {
            // Keep the menu item available while the user grants access.
            statusItem?.button?.appearsDisabled = true
            return
        }
        controller.start()
        NSLog("[Tabbed] controller started — global ⌘-drag monitor active")
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
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
        menu.addItem(withTitle: "Tabbed", action: nil, keyEquivalent: "")
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
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Permissions

    private func ensureAccessibilityPermission() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
