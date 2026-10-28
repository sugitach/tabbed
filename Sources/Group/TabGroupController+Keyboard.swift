import AppKit

extension TabGroupController {
    /// Logical shortcut intent while native window operations catch up.
    struct PendingShortcutSelection {
        let token = UUID()
        let group: TabGroup
        let originalWindowID: WindowID
        var targetWindowID: WindowID
    }
}

extension TabGroupController: KeyboardShortcutMonitorDelegate {
    /// Activate the tab at `index` in the group the user is currently focused on.
    func keyboardShortcutSelectTab(at index: Int) -> Bool {
        guard let group = shortcutGroup(), group.windows.indices.contains(index) else { return false }
        enqueueShortcutSelection(group.windows[index].id, in: group)
        return true
    }

    /// Accumulate every step before committing one native window switch.
    func keyboardShortcutCycleTab(forward: Bool) -> Bool {
        guard let group = shortcutGroup(), group.windows.count > 1 else { return false }
        let currentID = pendingShortcutSelection?.targetWindowID ?? group.activeWindow?.id
        guard let index = group.windows.firstIndex(where: { $0.id == currentID }) else { return false }
        let count = group.windows.count
        let next = forward ? (index + 1) % count : (index - 1 + count) % count
        enqueueShortcutSelection(group.windows[next].id, in: group)
        return true
    }

    private func shortcutGroup() -> TabGroup? {
        guard !isStopping else { return nil }
        // Avoid one synchronous AX lookup per queued key. Validate the live
        // focused window again before committing any native window changes.
        if let pending = pendingShortcutSelection {
            if groups.contains(where: { $0 === pending.group }),
               pending.group.activeWindow?.id == pending.originalWindowID,
               pending.group.activeWindow?.pid == NSWorkspace.shared.frontmostApplication?.processIdentifier,
               isGroupOnActiveSpace(pending.group) {
                return pending.group
            }
            pendingShortcutSelection = nil
        }
        return focusedGroup()
    }

    private func enqueueShortcutSelection(_ id: WindowID, in group: TabGroup) {
        if pendingShortcutSelection?.group === group {
            pendingShortcutSelection?.targetWindowID = id
            return
        }
        guard let active = group.activeWindow, active.id != id else { return }
        pendingShortcutSelection = PendingShortcutSelection(group: group,
            originalWindowID: active.id, targetWindowID: id)
        scheduleShortcutSelection()
    }

    private func scheduleShortcutSelection() {
        // Let already queued Carbon hotkeys drain before making blocking AX
        // calls. A short fixed batch also keeps continuous key repeat responsive.
        guard let token = pendingShortcutSelection?.token else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard self?.pendingShortcutSelection?.token == token else { return }
            self?.commitShortcutSelection()
        }
    }

    private func commitShortcutSelection() {
        guard let pending = pendingShortcutSelection else { return }
        guard !isStopping else { pendingShortcutSelection = nil; return }
        if isApplyingLayout || shortcutSelectionInProgress {
            scheduleShortcutSelection()
            return
        }
        pendingShortcutSelection = nil
        guard groups.contains(where: { $0 === pending.group }),
              pending.group.activeWindow?.id == pending.originalWindowID,
              focusedGroup() === pending.group,
              pending.group.contains(pending.targetWindowID),
              pending.targetWindowID != pending.originalWindowID else { return }
        shortcutSelectionInProgress = true
        defer { shortcutSelectionInProgress = false }
        selectTab(pending.targetWindowID, in: pending.group)
    }

    /// The on-screen group whose active window currently holds focus.
    private func focusedGroup() -> TabGroup? {
        if let group = frontmostGroup(), isGroupOnActiveSpace(group) { return group }
        // During our own native switch AX may still name the previous member.
        // Only a live member of a settling group can retain shortcut ownership;
        // an ungrouped window or another app must still be a no-op.
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              pid != ownPID, let id = effectiveFocusedWindowID(for: pid) else { return nil }
        return groups.first { group in
            isGroupOnActiveSpace(group) &&
            ProcessInfo.processInfo.systemUptime < group.focusSettlementUntil &&
            group.windows.contains { $0.id == id && $0.pid == pid }
        }
    }
}
