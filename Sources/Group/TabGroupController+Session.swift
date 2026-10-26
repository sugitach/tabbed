import AppKit

extension TabGroupController {
    func savedIdentity(for window: ManagedWindow) -> SavedWindowIdentity? {
        guard let app = NSRunningApplication(processIdentifier: window.pid),
              !app.isTerminated, let launched = app.launchDate else { return nil }
        return SavedWindowIdentity(id: window.id, pid: window.pid,
            processLaunchTime: launched.timeIntervalSince1970, bundleID: app.bundleIdentifier)
    }

    /// Called before quit-time cascading/clearing, and kept across cancelled Quit retries.
    func captureSessionForTermination() {
        guard sessionForTermination == nil else { return }
        var savedGroups = groups.compactMap { group -> SavedWindowGroup? in
            let windows = group.windows.compactMap { savedIdentity(for: $0) }
            guard windows.count >= 2 else { return nil }
            let selected = windows.first { $0.id == group.activeWindow?.id } ?? windows[0]
            return SavedWindowGroup(windows: windows, selectedID: selected.id, frame: group.contentFrame)
        }
        // AX may still be resolving some startup groups when Quit begins.
        // Retain those groups unless explicit user interaction cancelled them.
        if pendingSessionGeneration == sessionInteractionGeneration {
            var usedIDs = Set(savedGroups.flatMap(\.windows).map(\.id))
            for pending in pendingSessionGroups {
                guard pending.windows.allSatisfy({ !usedIDs.contains($0.id) }) else { continue }
                savedGroups.append(pending)
                usedIDs.formUnion(pending.windows.map(\.id))
            }
        }
        sessionForTermination = GroupSession(groups: savedGroups)
    }

    func persistSessionForTermination() {
        // Quitting before permission/startup readiness must not erase the last session.
        guard isStarted else { return }
        captureSessionForTermination()
        guard let sessionForTermination else { return }
        do { try sessionStore.save(sessionForTermination) }
        catch { NSLog("[Tabbed] Could not save window groups: %@", error.localizedDescription) }
    }

    /// One startup session with bounded AX retries after monitoring is ready; never launch apps or match by title.
    func restoreSavedGroups() {
        guard !isStopping, isStarted, !didRestoreSession else { return }
        didRestoreSession = true
        guard let session = sessionStore.load() else { return }
        restoreSessionGroups(session.groups, attemptsRemaining: 3)
    }

    func restoreSessionGroups(_ savedGroups: [SavedWindowGroup], attemptsRemaining: Int) {
        guard !isStopping else { return }
        var pending: [SavedWindowGroup] = []
        for saved in savedGroups {
            // Never revive a group already restored, manually regrouped, or ungrouped
            // during a deferred retry.
            guard !saved.windows.contains(where: { group(containing: $0.id) != nil }) else { continue }
            var unavailable = false
            let windows = saved.windows.compactMap { identity -> ManagedWindow? in
                guard group(containing: identity.id) == nil,
                      let app = NSRunningApplication(processIdentifier: identity.pid),
                      !app.isTerminated,
                      app.launchDate?.timeIntervalSince1970 == identity.processLaunchTime,
                      app.bundleIdentifier == identity.bundleID else { return nil }
                guard let window = engine.existingWindow(id: identity.id, pid: identity.pid) else {
                    unavailable = true
                    return nil
                }
                guard savedIdentity(for: window) == identity else { return nil }
                return window
            }
            if unavailable && attemptsRemaining > 0 {
                pending.append(saved)
                continue
            }
            guard windows.count >= 2 else { continue }
            let activeIndex = windows.firstIndex { $0.id == saved.selectedID } ?? 0
            let active = windows[activeIndex]
            // Respect Space changes made while Tabbed was stopped.
            let space = engine.spaceID(of: active)
            guard windows.allSatisfy({ engine.spaceID(of: $0) == space }) else { continue }
            guard let frame = WindowRestoration.destination(for: saved.frame,
                screens: NSScreen.screens.map(\.visibleFrame)) else { continue }
            let restored = TabGroup(windows: windows, activeIndex: activeIndex,
                contentFrame: frame, spaceID: space)
            groups.append(restored)
            wire(restored)
            observeWindows(in: restored)
            updateFocusObservers()
            applyLayout(for: restored)
        }
        pendingSessionGroups = pending
        pendingSessionGeneration = sessionInteractionGeneration
        if !pending.isEmpty && attemptsRemaining > 0 {
            let generation = sessionInteractionGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.sessionInteractionGeneration == generation else { return }
                self.restoreSessionGroups(pending, attemptsRemaining: attemptsRemaining - 1)
            }
        }
    }
}
