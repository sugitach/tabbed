import AppKit

extension TabGroupController {
    func observeSpaceChanges() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    func observeApplicationChanges() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidLaunch(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidTerminate(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }

    @objc func applicationDidTerminate(_ notification: Notification) {
        guard !isStopping, !deferDisplayLayout() else { return }
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        let pid = app.processIdentifier
        for group in groups {
            for window in group.windows where window.pid == pid {
                remove(window.id, from: group, keepWindowObserved: false)
            }
        }
    }

    func pruneDeadWindows() {
        guard !isStopping, !deferDisplayLayout() else { return }
        for group in groups {
            // Unknown AX liveness must not discard a parked window's Quit target.
            for window in group.windows where engine.isKnownClosed(window) {
                remove(window.id, from: group, keepWindowObserved: false)
            }
        }
    }

    @objc func activeSpaceChanged() {
        guard !isStopping, !deferDisplayLayout() else { return }
        pruneDeadWindows()
        for group in groups {
            if isGroupOnActiveSpace(group) {
                applyLayout(for: group)
            } else {
                group.panel.hide()
            }
        }
    }

    @objc func applicationDidActivate(_ notification: Notification) {
        guard !isStopping, !deferDisplayLayout() else { return }
        pruneDeadWindows()
        syncPanelZOrderWithFrontmostGroupSoon()
    }

    @objc func applicationDidLaunch(_ notification: Notification) {
        // Installing an observer does not adopt/write geometry. A launch event
        // skipped during display settlement will not be delivered again.
        guard !isStopping else { return }
        guard autoAddNewWindowsToStack,
              let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        observeAppForWindowCreation(app)
    }

    func isGroupOnActiveSpace(_ group: TabGroup) -> Bool {
        // A restored/dragged window may migrate between display Spaces after
        // the group captured its target. Use the active window's live identity.
        let groupSpace = group.activeWindow.flatMap { engine.spaceID(of: $0) } ?? group.spaceID
        guard let groupSpace,
              let activeSpaces = engine.activeSpaceIDs() else {
            return true
        }
        return activeSpaces.contains(groupSpace)
    }
}
