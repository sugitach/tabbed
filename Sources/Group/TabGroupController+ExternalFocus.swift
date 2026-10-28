import AppKit
import ApplicationServices

extension TabGroupController {
    /// Handle main-window transitions before deferring/coalescing later events.
    func applicationFocusDidChange(pid: pid_t, mainWindowChanged: Bool,
                                   element: AXUIElement? = nil) {
        guard !isStopping, !deferDisplayLayout() else { return }
        if mainWindowChanged {
            if let element {
                selectNotifiedMainWindow(element, pid: pid)
            } else {
                selectExternallyFocusedWindow(preferMainWindowForPID: pid)
            }
        }
        syncPanelZOrderWithFrontmostGroupSoon(
            preferMainWindowForPID: mainWindowChanged ? pid : nil)
    }

    /// Chrome can return its previous main window before this callback queries AX.
    /// Only an exact, still-live member from this main-window notification may
    /// be revealed synchronously. Never retain an event target for later retries.
    func selectNotifiedMainWindow(_ element: AXUIElement, pid: pid_t) {
        guard !isStopping, !isApplyingLayout, draggedWindow == nil,
              pid != ownPID,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let window = groups.lazy.flatMap({ $0.windows }).first(where: {
                  $0.pid == pid && CFEqual($0.element, element)
              }),
              engine.isAlive(window) else { return }
        selectExternallyActivatedWindow(window.id, pid: pid)
    }

    /// Read current focus, including parked tabs, for ordinary/settled checks.
    func selectExternallyFocusedWindow(preferMainWindowForPID: pid_t? = nil) {
        guard !isStopping, !isApplyingLayout, draggedWindow == nil,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ownPID,
              let focusedID = effectiveFocusedWindowID(for: app.processIdentifier,
                  preferMainWindowForPID: preferMainWindowForPID) else { return }
        selectExternallyActivatedWindow(focusedID, pid: app.processIdentifier)
    }

    func selectExternallyActivatedWindow(_ id: WindowID, pid: pid_t) {
        guard !isStopping, !isApplyingLayout, draggedWindow == nil,
              pid != ownPID,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let group = groups.first(where: { group in
                  group.windows.contains { $0.id == id && $0.pid == pid }
              }),
              group.activeWindow?.id != id,
              group.moveAnchorFrame == nil,
              isGroupOnActiveSpace(group) else { return }

        // isApplyingLayout only covers synchronous AX calls. Chrome can still
        // report the previous main/focused window after those calls return, and
        // replay delayed main-window notifications. Treat both paths as echoes
        // during this group's activation settlement. Explicit tab selections
        // bypass this guard; the final deferred live check picks up a genuine
        // external activation without retaining/replaying a stale event target.
        guard group.activeWindow?.pid != pid ||
              ProcessInfo.processInfo.systemUptime >= group.focusSettlementUntil else {
            WindowDiagnostics.record(.init(event: .focusSelectionDeferred, windowID: id,
                pid: pid, groupID: group.id, activeWindowID: group.activeWindow?.id,
                reason: .activationSettling))
            return
        }

        // Preserve the visible group's geometry rather than adopting the parked frame.
        if activeMoveGroup === group { endTrackingActiveMove() }
        selectTab(id, in: group)
    }
}
