import AppKit

extension TabGroupController {
    func observeDisplayChanges() {
        currentDisplayConfiguration = DisplayConfigurationMonitor.currentKey()
        displayMonitor.onChange = { [weak self] in
            MainActor.assumeIsolated { self?.displayConfigurationDidChange() }
        }
        displayMonitor.start()
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc func screenParametersChanged() {
        displayConfigurationDidChange()
    }

    /// Also check the live Quartz topology at write/adoption boundaries: AX and
    /// Workspace events can arrive before AppKit's screen-parameters notification.
    func deferDisplayLayout() -> Bool {
        if displayTransitionPending { return true }
        guard isStarted, !isStopping else { return false }
        if displayMonitor.state.pending || DisplayConfigurationMonitor.currentKey() != currentDisplayConfiguration {
            displayConfigurationDidChange()
            return true
        }
        return false
    }

    func rememberDisplayLayouts() {
        guard let configuration = currentDisplayConfiguration else { return }
        for group in groups { group.displayLayouts.remember(group.contentFrame, for: configuration) }
    }

    func displayConfigurationDidChange() {
        guard !isStopping else { return }
        if !displayTransitionPending {
            // Use cached group frames, never the AX frames macOS may have already moved.
            rememberDisplayLayouts()
            displayTransitionPending = true
            pendingShortcutSelection = nil
            panelZOrderSyncGeneration &+= 1
            endTrackingActiveMove(restorePanel: false)
            dragDidCancel()
            for group in groups {
                group.moveAnchorFrame = nil
                group.panel.hide(animated: false)
            }
        }
        displayTransitionGeneration &+= 1
        let generation = displayTransitionGeneration
        scheduleDisplaySettlement(generation: generation, previousFrames: [:], stableSamples: 0)
    }

    func scheduleDisplaySettlement(generation: UInt64, previousFrames: [UUID: CGRect], stableSamples: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, !self.isStopping, self.displayTransitionGeneration == generation else { return }
            self.settleDisplayConfiguration(generation: generation,
                previousFrames: previousFrames, stableSamples: stableSamples)
        }
    }

    func settleDisplayConfiguration(generation: UInt64, previousFrames: [UUID: CGRect], stableSamples: Int) {
        guard !isStopping, displayTransitionPending, displayTransitionGeneration == generation else { return }
        guard !isApplyingLayout, let configuration = DisplayConfigurationMonitor.currentKey(),
              DisplayConfigurationMonitor.appKitMatchesQuartz() else {
            scheduleDisplaySettlement(generation: generation, previousFrames: [:], stableSamples: 0)
            return
        }
        let revision = displayMonitor.state.revision
        let frames = Dictionary(uniqueKeysWithValues: groups.compactMap { group -> (UUID, CGRect)? in
            guard isGroupOnActiveSpace(group), let active = group.activeWindow,
                  let frame = engine.windowServerFrame(of: active.id) ?? engine.frame(of: active) else { return nil }
            return (group.id, frame)
        })
        // Require two quiet samples after the initial delay. Any further display
        // notification invalidates this whole attempt, including rapid A -> B -> A.
        guard frames == previousFrames, stableSamples >= 1 else {
            scheduleDisplaySettlement(generation: generation, previousFrames: frames,
                stableSamples: frames == previousFrames ? stableSamples + 1 : 0)
            return
        }
        guard !isStopping, displayTransitionGeneration == generation else { return }
        guard configuration == DisplayConfigurationMonitor.currentKey(),
              displayMonitor.acknowledge(revision) else {
            displayConfigurationDidChange()
            return
        }
        let screens = NSScreen.screens.map(\.visibleFrame)
        for group in groups {
            let proposed = group.displayLayouts.frame(for: configuration) ?? frames[group.id] ?? group.contentFrame
            if let frame = WindowRestoration.destination(for: proposed, screens: screens) {
                group.contentFrame = frame
            }
        }
        currentDisplayConfiguration = configuration
        displayTransitionPending = false
        rememberDisplayLayouts()
        // Do not raise every group over the user's current app during hotplug.
        // applyLayout normally raises its active window; retain the frontmost one last.
        let frontmost = frontmostGroup()
        for group in groups where group !== frontmost { applyLayout(for: group, raiseWindow: false) }
        if let frontmost { applyLayout(for: frontmost) }
        syncPanelZOrderWithFrontmostGroupSoon()
    }
}
