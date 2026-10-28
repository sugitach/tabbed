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
        for (index, window) in group.windows.enumerated() {
            guard !isStopping, !deferDisplayLayout() else { return }
            _ = engine.refreshTitle(window)
            guard !isStopping, !deferDisplayLayout() else { return }
            if index == group.activeIndex {
                engine.setFrame(group.contentFrame, of: window)
            } else {
                parkOffscreen(window, relativeTo: group.contentFrame)
            }
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

    /// Leave only a one-point edge on the group's display, never on a neighbor.
    private func parkOffscreen(_ window: ManagedWindow, relativeTo referenceFrame: CGRect) {
        guard let frame = engine.frame(of: window) else { return }
        let screens = NSScreen.screens.map(\.frame)
        func area(_ rect: CGRect) -> CGFloat {
            rect.isNull ? 0 : max(0, rect.width) * max(0, rect.height)
        }
        func distance(to screen: CGRect) -> CGFloat {
            let dx = max(screen.minX - referenceFrame.midX, 0, referenceFrame.midX - screen.maxX)
            let dy = max(screen.minY - referenceFrame.midY, 0, referenceFrame.midY - screen.maxY)
            return dx * dx + dy * dy
        }
        // The inactive window may already have been assigned to another display.
        // Select from the group frame, not its current parked AX frame.
        guard let sourceIndex = screens.indices.min(by: { lhs, rhs in
            let left = area(screens[lhs].intersection(referenceFrame))
            let right = area(screens[rhs].intersection(referenceFrame))
            return left != right ? left > right : distance(to: screens[lhs]) < distance(to: screens[rhs])
        }) else { return }
        let source = screens[sourceIndex]
        func parkingFrame(for size: CGSize) -> CGRect {
            guard size.width > 1, size.height > 1 else { return referenceFrame }
            var xs = [referenceFrame.minX, source.minX, source.maxX - size.width,
                      source.minX - size.width + 1, source.maxX - 1]
            var ys = [referenceFrame.minY, source.minY, source.maxY - size.height,
                      source.minY - size.height + 1, source.maxY - 1]
            for screen in screens {
                // Neighbor boundaries are the points at which a safe interval can
                // start or end. Include them for offset and partially shared edges.
                xs += [screen.minX - size.width, screen.maxX]
                ys += [screen.minY - size.height, screen.maxY]
            }
            var candidates: [CGRect] = []
            // Prefer below the display, then its sides, then above it.
            for x in xs {
                candidates.append(CGRect(x: x, y: source.minY + 1 - size.height,
                                         width: size.width, height: size.height))
            }
            for x in [source.minX + 1 - size.width, source.maxX - 1] {
                for y in ys {
                    candidates.append(CGRect(x: x, y: y, width: size.width, height: size.height))
                }
            }
            for x in xs {
                candidates.append(CGRect(x: x, y: source.maxY - 1,
                                         width: size.width, height: size.height))
            }
            return candidates.first { candidate in
                area(candidate.intersection(source)) > 0 && screens.indices.allSatisfy { index in
                    index == sourceIndex || area(candidate.intersection(screens[index])) == 0
                }
            } ?? CGRect(origin: referenceFrame.origin, size: size)
        }
        let parked = parkingFrame(for: referenceFrame.size)
        // A surrounded display may have no safe outside edge. In that case,
        // stack behind the active member; applyLayout raises it after parking.
        WindowDiagnostics.record(.init(event: .parking, windowID: window.id, pid: window.pid,
            requestedFrame: WindowDiagnostics.frame(parked), axFrame: WindowDiagnostics.frame(frame)))
        guard !isStopping, !deferDisplayLayout() else { return }
        engine.setFrame(parked, of: window)
        // Applications may acknowledge an AX size request but retain a larger
        // minimum size. Recompute the destination using the accepted dimensions
        // so the real window cannot spill into an adjacent display.
        if let actual = engine.frame(of: window), actual.size != parked.size {
            let corrected = parkingFrame(for: actual.size)
            WindowDiagnostics.record(.init(event: .parking, windowID: window.id, pid: window.pid,
                requestedFrame: WindowDiagnostics.frame(corrected), axFrame: WindowDiagnostics.frame(actual)))
            guard !isStopping, !deferDisplayLayout() else { return }
            engine.setFrame(corrected, of: window)
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
