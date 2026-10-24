import AppKit

extension TabGroupController {
    func add(_ window: ManagedWindow, to group: TabGroup) {
        guard !isStopping else { return }
        if group.contains(window.id) {
            group.activeIndex = group.windows.firstIndex { $0.id == window.id } ?? group.activeIndex
            applyLayout(for: group)
            return
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
    }

    func positionPanel(for group: TabGroup) {
        guard !isStopping else { return }
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
            expanded: compact ? group.compactExpandedFrame : group.stripFrameAbove
        )
        reassertPanelZOrder(for: group)
    }

    func applyLayout(for group: TabGroup) {
        guard !isStopping else { return }
        guard isGroupOnActiveSpace(group) else {
            group.panel.hide()
            group.syncViewModel()
            return
        }

        isApplyingLayout = true
        WindowDiagnostics.record(.init(event: .layoutBegin, groupID: group.id,
            activeWindowID: group.activeWindow?.id, memberIDs: group.windows.map(\.id),
            groupFrame: WindowDiagnostics.frame(group.contentFrame), applyingLayout: true))
        for (index, window) in group.windows.enumerated() {
            _ = engine.refreshTitle(window)
            if index == group.activeIndex {
                engine.setFrame(group.contentFrame, of: window)
            } else {
                parkOffscreen(window)
            }
        }
        if let active = group.activeWindow {
            engine.raise(active)
        }
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

    /// Park inactive tabs out of view without triggering AX clamping.
    private func parkOffscreen(_ window: ManagedWindow) {
        guard let frame = engine.frame(of: window) else { return }
        // Use the outer edge of the entire desktop, not a shared display edge.
        guard let desktop = NSScreen.screens.map(\.frame).reduce(nil as CGRect?, { result, next in
            result.map { $0.union(next) } ?? next
        }) else { return }
        let parked = CGRect(x: desktop.maxX - 1,
                            y: desktop.minY + 1 - frame.height,
                            width: frame.width, height: frame.height)
        WindowDiagnostics.record(.init(event: .parking, windowID: window.id, pid: window.pid,
            requestedFrame: WindowDiagnostics.frame(parked), axFrame: WindowDiagnostics.frame(frame)))
        engine.setFrame(parked, of: window)
    }

    func selectTab(_ id: WindowID, in group: TabGroup) {
        guard !isStopping else { return }
        guard let idx = group.windows.firstIndex(where: { $0.id == id }) else { return }
        WindowDiagnostics.record(.init(event: .selection, windowID: id, pid: group.windows[idx].pid,
            groupID: group.id, activeWindowID: group.activeWindow?.id,
            trackingWindowID: activeMoveOriginWindowID,
            groupFrame: WindowDiagnostics.frame(group.contentFrame)))
        endTrackingActiveMove()
        let changesWindow = group.activeIndex != idx
        group.activeIndex = idx
        group.panel.collapseAfterSelection()
        if changesWindow {
            applyLayout(for: group)
        }
        if isGroupOnActiveSpace(group) {
            engine.activate(group.windows[idx])
            reassertPanelZOrder(for: group)
            syncPanelZOrderWithFrontmostGroupSoon()
        }
    }

    func untab(_ id: WindowID, from group: TabGroup) {
        guard !isStopping else { return }
        guard let window = group.windows.first(where: { $0.id == id }) else { return }
        let base = group.contentFrame
        remove(id, from: group, keepWindowObserved: false)
        let size = engine.frame(of: window)?.size ?? base.size
        let destination = WindowRestoration.ungroupedFrame(base, index: 1)
        engine.setFrame(CGRect(origin: destination.origin, size: size), of: window)
        engine.activate(window)
    }

    func remove(_ id: WindowID, from group: TabGroup, keepWindowObserved: Bool) {
        guard let idx = group.windows.firstIndex(where: { $0.id == id }) else { return }
        WindowDiagnostics.record(.init(event: .memberRemoved, windowID: id, groupID: group.id,
            activeWindowID: group.activeWindow?.id, memberIDs: group.windows.map(\.id)))
        group.windows.remove(at: idx)
        if !keepWindowObserved {
            observer.unobserve(id)
        }

        if group.windows.count <= 1 {
            dissolve(group)
            return
        }

        if idx < group.activeIndex {
            group.activeIndex -= 1
        } else if group.activeIndex >= group.windows.count {
            group.activeIndex = group.windows.count - 1
        }

        applyLayout(for: group)
        updateFocusObservers()
    }

    func dissolve(_ group: TabGroup) {
        if activeMoveGroup === group { endTrackingActiveMove(restorePanel: false) }
        WindowDiagnostics.record(.init(event: .groupDissolved, groupID: group.id,
            activeWindowID: group.activeWindow?.id, memberIDs: group.windows.map(\.id)))
        group.panel.hide()
        for window in group.windows {
            observer.unobserve(window.id)
            engine.setFrame(group.contentFrame, of: window)
        }
        groups.removeAll { $0 === group }
        if mostRecentGroup === group {
            mostRecentGroup = groups.last
        }
        updateFocusObservers()
    }
}
