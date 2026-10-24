import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var autoAddMenuItem: NSMenuItem?
    private var compactModeMenuItem: NSMenuItem?
    private var diagnosticMenuItem: NSMenuItem?
    private let engine = AXWindowEngine()
    private lazy var controller = TabGroupController(engine: engine)

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

    func applicationWillTerminate(_ notification: Notification) {
        WindowDiagnostics.recorder.stop()
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
        diagnosticMenuItem = menu.addItem(withTitle: "Record Window Diagnostics",
            action: #selector(toggleWindowDiagnostics), keyEquivalent: "")
        diagnosticMenuItem?.target = self
        diagnosticMenuItem?.toolTip = "Records window IDs, geometry and AX results locally. No titles, URLs or page content. Off by default; two log files, up to 8 MiB each."
        WindowDiagnostics.recorder.onStateChange = { [weak self] in
            self?.diagnosticMenuItem?.state = WindowDiagnostics.isRecording ? .on : .off
            self?.diagnosticMenuItem?.title = WindowDiagnostics.recorder.failure == nil
                ? "Record Window Diagnostics" : "Record Window Diagnostics (Stopped: Log Error)"
        }
        menu.addItem(withTitle: "Show Window Diagnostic Logs…",
                     action: #selector(showWindowDiagnosticLogs), keyEquivalent: "").target = self
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

    @objc private func toggleWindowDiagnostics() {
        if WindowDiagnostics.isRecording {
            WindowDiagnostics.recorder.stop()
        } else {
            do { try WindowDiagnostics.recorder.start() }
            catch {
                let alert = NSAlert()
                alert.messageText = "Window diagnostics could not start"
                alert.informativeText = "The local diagnostic log could not be opened safely. No permissions or window settings were changed."
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    @objc private func showWindowDiagnosticLogs() {
        let directory = WindowDiagnostics.recorder.directory
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        NSWorkspace.shared.open(directory)
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
