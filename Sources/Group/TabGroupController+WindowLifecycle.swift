import AppKit

extension TabGroupController {
    func updateWindowLifecycleMonitoring() {
        guard !isStopping, !groups.isEmpty else {
            stopWindowLifecycleMonitoring()
            return
        }
        guard windowLifecycleTimer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcileWindowLifetimes() }
        }
        timer.tolerance = 0.05
        windowLifecycleTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopWindowLifecycleMonitoring() {
        windowLifecycleTimer?.invalidate()
        windowLifecycleTimer = nil
    }

    func reconcileWindowLifetimes() {
        guard !isStopping, !isApplyingLayout, !groups.isEmpty,
              let owners = WindowServerSnapshot.windowOwners() else { return }
        // AX destruction notifications are not reliable in every application.
        // Use one complete WindowServer snapshot, never a visibility-filtered
        // list or an AX timeout, as the fallback closure evidence.
        for group in groups {
            let closedIDs = Set(group.windows.filter { window in
                guard owners[window.id] != window.pid else { return false }
                // Minimized windows may disappear from WindowServer lists.
                if window.minimizedByTabbed || engine.isMinimized(of: window) == true {
                    return engine.isKnownClosed(window)
                }
                return true
            }.map(\.id))
            removeWindows(closedIDs, from: group, keepWindowObserved: false)
        }
    }
}
