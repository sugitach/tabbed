import AppKit

extension TabGroupController {
    func beginPanelMove(for group: TabGroup) {
        guard !isStopping, !deferDisplayLayout() else { return }
        group.moveAnchorFrame = group.contentFrame
    }

    func updatePanelMove(for group: TabGroup, translation: CGSize) {
        guard !isStopping, !deferDisplayLayout(), let anchor = group.moveAnchorFrame else { return }
        group.contentFrame = anchor.offsetBy(dx: translation.width, dy: translation.height)
        positionPanel(for: group)
        // AX calls can reenter the main run loop and begin another transition.
        guard !isStopping, !deferDisplayLayout(), group.moveAnchorFrame != nil else { return }
        if let active = group.activeWindow { engine.setFrame(group.contentFrame, of: active) }
    }

    func endPanelMove(for group: TabGroup) {
        let wasMoving = group.moveAnchorFrame != nil
        group.moveAnchorFrame = nil
        guard !isStopping, !deferDisplayLayout(), wasMoving else { return }
        applyLayout(for: group)
    }

    @discardableResult
    func add(_ window: ManagedWindow, to group: TabGroup) -> Bool {
        guard !isStopping, !deferDisplayLayout() else { return false }
        if group.contains(window.id) {
            group.activeIndex = group.windows.firstIndex { $0.id == window.id } ?? group.activeIndex
            applyLayout(for: group)
            return true
        }

        if let sourceGroup = self.group(containing: window.id), sourceGroup !== group {
            remove(window.id, from: sourceGroup, keepWindowObserved: true)
        }

        if let reference = group.activeWindow,
           let windowSpace = engine.spaceID(of: window),
           let groupSpace = group.spaceID,
           windowSpace != groupSpace {
            engine.move(window, toSpaceOf: reference)
        }

        group.windows.append(window)
        group.activeIndex = group.windows.count - 1
        observeWindows(in: group)
        markRecentlyUsed(group)
        updateFocusObservers()
        applyLayout(for: group)
        return true
    }

    func positionPanel(for group: TabGroup) {
        guard !isStopping, !deferDisplayLayout() else { return }
        guard !group.isPanelHiddenForMove else { return }
        let compact = group.useCompact
        if group.viewModel.compact != compact {
            group.viewModel.compact = compact
        }
        group.panel.onFrameChanged = { [weak self, weak group] in
            guard let self, let group else { return }
            self.reassertPanelZOrder(for: group)
        }
        group.panel.applyLayout(
            compact: compact,
            resting: group.stripFrame,
            expanded: compact ? group.compactExpandedFrame : group.stripFrameAbove,
            hoverExpansionDelay: alwaysUseCompactMode ? 3 : 0
        )
        reassertPanelZOrder(for: group)
    }

    func applyLayout(for group: TabGroup, raiseWindow: Bool = true) {
        guard !isStopping, !deferDisplayLayout() else { return }
        guard isGroupOnActiveSpace(group) else {
            group.panel.hide()
            group.syncViewModel()
            return
        }

        isApplyingLayout = true
        defer { isApplyingLayout = false }
        WindowDiagnostics.record(.init(event: .layoutBegin, groupID: group.id,
            activeWindowID: group.activeWindow?.id, memberIDs: group.windows.map(\.id),
            groupFrame: WindowDiagnostics.frame(group.contentFrame), applyingLayout: true))
        // Reveal the destination before hiding the previous tab. AX callbacks
        // may run during setters; ownership is tracked before each request.
        guard let active = group.activeWindow, restoreTabWindow(active) else { return }
        engine.setFrame(group.contentFrame, of: active)
        for window in group.windows {
            guard !isStopping, !deferDisplayLayout() else { return }
            _ = engine.refreshTitle(window)
            if window.id != active.id { minimizeTabWindow(window, fallbackFrame: group.contentFrame) }
        }
        guard !isStopping, !deferDisplayLayout() else { return }
        if raiseWindow, let active = group.activeWindow {
            engine.raise(active)
        }
        group.focusSettlementUntil = ProcessInfo.processInfo.systemUptime + 1
        isApplyingLayout = false
        WindowDiagnostics.record(.init(event: .layoutEnd, groupID: group.id,
            activeWindowID: group.activeWindow?.id,
            groupFrame: WindowDiagnostics.frame(group.contentFrame), applyingLayout: false))

        positionPanel(for: group)
        if !group.isPanelHiddenForMove { group.panel.show() }
        reassertPanelZOrder(for: group)
        group.syncViewModel()
        // A native drag/AX raise may finish after this initial ordering. New
        // and recreated groups need the same settled checks as tab selection,
        // even when no subsequent focus notification or mouse event arrives.
        syncPanelZOrderWithFrontmostGroupSoon()
    }

    /// Do not undo a user's own minimization when releasing a group.
    func restoreTabWindow(_ window: ManagedWindow) -> Bool {
        guard window.minimizedByTabbed else { return true }
        window.minimizedByTabbed = false
        // AX acknowledges the request before macOS completes the animation.
        guard engine.setMinimized(false, of: window) else {
            window.minimizedByTabbed = true
            return false
        }
        return true
    }

    func minimizeTabWindow(_ window: ManagedWindow, fallbackFrame: CGRect) {
        if engine.isMinimized(of: window) == true { return }
        let previouslyOwned = window.minimizedByTabbed
        window.minimizedByTabbed = true
        guard engine.setMinimized(true, of: window) else {
            window.minimizedByTabbed = previouslyOwned
            // Unsupported/rejected minimization must never strand a window offscreen.
            // Stack behind the active member, which applyLayout raises last.
            engine.setFrame(fallbackFrame, of: window)
            return
        }
    }

    func selectTab(_ id: WindowID, in group: TabGroup) {
        guard !isStopping, !deferDisplayLayout() else { return }
        guard let idx = group.windows.firstIndex(where: { $0.id == id }) else { return }
        WindowDiagnostics.record(.init(event: .selection, windowID: id, pid: group.windows[idx].pid,
            groupID: group.id, activeWindowID: group.activeWindow?.id,
            trackingWindowID: activeMoveOriginWindowID,
            groupFrame: WindowDiagnostics.frame(group.contentFrame)))
        endTrackingActiveMove()
        let changesWindow = group.activeIndex != idx
        guard restoreTabWindow(group.windows[idx]) else { return }
        group.activeIndex = idx
        group.panel.collapseAfterSelection()
        if changesWindow {
            applyLayout(for: group)
        }
        if !isStopping, !deferDisplayLayout(), isGroupOnActiveSpace(group) {
            group.focusSettlementUntil = ProcessInfo.processInfo.systemUptime + 1
            engine.activate(group.windows[idx])
            reassertPanelZOrder(for: group)
            syncPanelZOrderWithFrontmostGroupSoon(preferMainWindowForPID: group.windows[idx].pid)
        }
    }

    func untab(_ id: WindowID, from group: TabGroup) {
        sessionInteractionGeneration &+= 1
        guard !isStopping, !deferDisplayLayout() else { return }
        guard let window = group.windows.first(where: { $0.id == id }) else { return }
        guard restoreTabWindow(window) else { return }
        let base = group.contentFrame
        remove(id, from: group, keepWindowObserved: false)
        let size = engine.frame(of: window)?.size ?? base.size
        let destination = WindowRestoration.ungroupedFrame(base, index: 1)
        guard !isStopping, !deferDisplayLayout() else { return }
        engine.setFrame(CGRect(origin: destination.origin, size: size), of: window)
        engine.activate(window)
    }

    func remove(_ id: WindowID, from group: TabGroup, keepWindowObserved: Bool) {
        removeWindows([id], from: group, keepWindowObserved: keepWindowObserved)
    }

    /// Remove a closure snapshot atomically before applying layout.
    func removeWindows(_ ids: Set<WindowID>, from group: TabGroup, keepWindowObserved: Bool) {
        if !isStopping, deferDisplayLayout() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak group] in
                guard let self, let group, !self.isStopping,
                      self.groups.contains(where: { $0 === group }) else { return }
                self.removeWindows(ids, from: group, keepWindowObserved: keepWindowObserved)
            }
            return
        }
        let removed = group.windows.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        for window in removed {
            WindowDiagnostics.record(.init(event: .memberRemoved, windowID: window.id, groupID: group.id,
                activeWindowID: group.activeWindow?.id, memberIDs: group.windows.map(\.id)))
        }
        let selectedID = group.activeWindow?.id
        let removedBeforeSelection = group.windows.prefix(group.activeIndex).filter { ids.contains($0.id) }.count
        let nextIndex = group.activeIndex - removedBeforeSelection
        group.windows.removeAll { ids.contains($0.id) }
        if !keepWindowObserved {
            for window in removed { observer.unobserve(window.id) }
        }
        group.activeIndex = group.windows.firstIndex { $0.id == selectedID }
            ?? max(0, min(nextIndex, group.windows.count - 1))

        if activeMoveGroup === group { endTrackingActiveMove(restorePanel: false) }

        if group.windows.count <= 1 {
            dissolve(group)
            return
        }

        applyLayout(for: group)
        updateFocusObservers()
    }

    func dissolve(_ group: TabGroup) {
        guard !isStopping, !deferDisplayLayout() else { return }
        if activeMoveGroup === group { endTrackingActiveMove(restorePanel: false) }
        guard group.windows.allSatisfy({ restoreTabWindow($0) }) else { return }
        WindowDiagnostics.record(.init(event: .groupDissolved, groupID: group.id,
            activeWindowID: group.activeWindow?.id, memberIDs: group.windows.map(\.id)))
        group.panel.hide()
        for window in group.windows {
            observer.unobserve(window.id)
            engine.setFrame(group.contentFrame, of: window)
        }
        groups.removeAll { $0 === group }
        updateWindowLifecycleMonitoring()
        if mostRecentGroup === group {
            mostRecentGroup = groups.last
        }
        updateFocusObservers()
    }
}
