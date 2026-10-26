import AppKit

extension TabGroupController {
    func mouseInteractionDidOccur() {
        guard !isStopping, !groups.isEmpty else { return }
        // Clicking inside an already focused app need not produce an AX focus
        // or workspace activation notification, but can raise its window.
        syncPanelZOrderWithFrontmostGroupSoon()
    }

    func effectiveFocusedWindowID(for pid: pid_t, preferMainWindowForPID: pid_t? = nil) -> WindowID? {
        let preferredPID = preferMainWindowForPID ??
            (Date() <= mainWindowPreferenceDeadline ? preferredMainWindowPID : nil)
        return preferredPID == pid
            ? engine.mainWindowID(for: pid)
            : engine.focusedOrMainWindowID(for: pid)
    }

    func frontmostGroup(preferMainWindowForPID: pid_t? = nil) -> TabGroup? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        guard pid != ownPID,
              let focusedID = effectiveFocusedWindowID(for: pid,
                  preferMainWindowForPID: preferMainWindowForPID) else {
            return nil
        }
        return groups.first { group in
            guard let active = group.activeWindow else { return false }
            return active.pid == pid && active.id == focusedID
        }
    }

    func syncPanelZOrderWithFrontmostGroupSoon(preferMainWindowForPID: pid_t? = nil) {
        // Activation and AppKit ordering finish asynchronously. Coalesce focus
        // notifications, then recheck after the destination app has settled.
        if let preferMainWindowForPID {
            preferredMainWindowPID = preferMainWindowForPID
            mainWindowPreferenceDeadline = Date().addingTimeInterval(1)
        }
        panelZOrderSyncGeneration &+= 1
        let generation = panelZOrderSyncGeneration
        for delay in [0.0, 0.05, 0.15, 0.35, 0.75] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, !self.isStopping,
                      self.panelZOrderSyncGeneration == generation else { return }
                self.syncPanelZOrderWithFrontmostGroup(preferMainWindowForPID:
                    Date() <= self.mainWindowPreferenceDeadline ? self.preferredMainWindowPID : nil)
            }
        }
    }

    func syncPanelZOrderWithFrontmostGroup(preferMainWindowForPID: pid_t? = nil) {
        guard !isStopping else { return }
        selectExternallyFocusedWindow(preferMainWindowForPID: preferMainWindowForPID)
        let frontmost = frontmostGroup(preferMainWindowForPID: preferMainWindowForPID)

        if let frontmost, isGroupOnActiveSpace(frontmost) {
            markRecentlyUsed(frontmost)
            positionPanel(for: frontmost)
        }

        for group in groups where group !== frontmost {
            reassertPanelZOrder(for: group)
        }
    }

    func reassertPanelZOrder(for group: TabGroup) {
        guard !isStopping else { return }
        guard !group.isPanelHiddenForMove else { return }
        guard isGroupOnActiveSpace(group) else { return }

        // Anchor every strip to its own window, including background groups.
        // Ordering below an unrelated frontmost window can bury a compact strip
        // behind its own content window.
        if let active = group.activeWindow {
            let ids = WindowServerSnapshot.visibleWindowIDs()
            let panelID = WindowID(exactly: group.panel.windowNumber)
            let panelIndex = panelID.flatMap { ids.firstIndex(of: $0) }
            let anchorIndex = ids.firstIndex(of: active.id)
            WindowDiagnostics.record(.init(event: .panelOrderSnapshot, groupID: group.id,
                activeWindowID: active.id, panelWindowID: panelID,
                panelFrame: WindowDiagnostics.frame(group.panel.frame),
                panelVisible: group.panel.isVisible, panelOrderIndex: panelIndex,
                anchorOrderIndex: anchorIndex))
            // A non-activating panel can remain behind the newly raised app.
            // The fallback is limited to the frontmost content window, so a
            // background group's panel cannot jump over an unrelated app.
            if let panelIndex, let anchorIndex, panelIndex > anchorIndex,
               engine.frontmostWindowID() == active.id {
                group.panel.orderFrontRegardless()
                WindowDiagnostics.record(.init(event: .panelOrderRepair, groupID: group.id,
                    activeWindowID: active.id, panelWindowID: panelID))
            }
            group.panel.order(.above, relativeTo: Int(active.id))
        } else {
            group.panel.orderOut(nil)
        }
    }

    func markRecentlyUsed(_ group: TabGroup) {
        mostRecentGroup = group
    }
}
