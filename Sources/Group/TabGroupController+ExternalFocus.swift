import AppKit

extension TabGroupController {
    /// Read current focus after AX notifications settle, including parked tabs.
    func selectExternallyFocusedWindow(preferMainWindowForPID: pid_t? = nil) {
        guard !isStopping, !isApplyingLayout, draggedWindow == nil,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ownPID,
              let focusedID = effectiveFocusedWindowID(for: app.processIdentifier,
                  preferMainWindowForPID: preferMainWindowForPID),
              let group = groups.first(where: { group in
                  group.windows.contains { $0.id == focusedID && $0.pid == app.processIdentifier }
              }),
              group.activeWindow?.id != focusedID,
              group.moveAnchorFrame == nil,
              isGroupOnActiveSpace(group) else { return }

        // Main-window notifications can precede Chrome updating AXFocusedWindow
        // (for example after a notification click). Re-read the live main window,
        // never replay the event element or fall back to an arbitrary group.
        // Never adopt the parked window's geometry as the group's new frame.
        if activeMoveGroup === group { endTrackingActiveMove() }
        selectTab(focusedID, in: group)
    }
}
