import AppKit

extension TabGroupController {
    /// Read current focus after AX notifications settle, including parked tabs.
    func selectExternallyFocusedWindow() {
        guard !isStopping, !isApplyingLayout, draggedWindow == nil,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ownPID,
              let focusedID = engine.focusedOrMainWindowID(for: app.processIdentifier),
              let group = groups.first(where: { group in
                  group.windows.contains { $0.id == focusedID && $0.pid == app.processIdentifier }
              }),
              group.activeWindow?.id != focusedID,
              group.moveAnchorFrame == nil,
              isGroupOnActiveSpace(group) else { return }

        // Never adopt the parked window's geometry as the group's new frame.
        if activeMoveGroup === group { endTrackingActiveMove() }
        selectTab(focusedID, in: group)
    }
}
