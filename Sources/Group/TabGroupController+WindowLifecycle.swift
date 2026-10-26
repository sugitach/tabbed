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
            let closedIDs = Set(group.windows.filter { owners[$0.id] != $0.pid }.map(\.id))
            removeWindows(closedIDs, from: group, keepWindowObserved: false)
        }
    }
}
