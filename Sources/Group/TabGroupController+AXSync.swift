import AppKit
import ApplicationServices

extension TabGroupController {
    func observeWindows(in group: TabGroup) {
        for window in group.windows {
            observer.observe(window)
        }
    }

    func handleWindowNotification(id: WindowID, notification: String) {
        WindowDiagnostics.record(.init(event: .notificationReceived, windowID: id,
            applyingLayout: isApplyingLayout, notification: WindowDiagnostics.notification(notification)))
        guard !isApplyingLayout else {
            WindowDiagnostics.record(.init(event: .notificationIgnored, windowID: id, reason: .applyingLayout))
            return
        }
        guard let group = group(containing: id) else {
            WindowDiagnostics.record(.init(event: .notificationIgnored, windowID: id, reason: .unmanaged))
            return
        }

        switch notification {
        case kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification:
            remove(id, from: group, keepWindowObserved: false)

        case kAXMovedNotification, kAXResizedNotification:
            guard group.activeWindow?.id == id,
                  isGroupOnActiveSpace(group) else {
                WindowDiagnostics.record(.init(event: .notificationIgnored, windowID: id,
                    groupID: group.id, activeWindowID: group.activeWindow?.id,
                    reason: group.activeWindow?.id != id ? .inactive : .wrongSpace))
                return
            }
            guard let frame = engine.frame(of: group.windows[group.activeIndex]) else {
                WindowDiagnostics.record(.init(event: .notificationIgnored, windowID: id,
                    groupID: group.id, reason: .unavailable))
                return
            }
            WindowDiagnostics.record(.init(event: .frameAdopted, windowID: id,
                groupID: group.id, activeWindowID: group.activeWindow?.id,
                groupFrame: WindowDiagnostics.frame(group.contentFrame),
                axFrame: WindowDiagnostics.frame(frame), source: .accessibility))
            beginTrackingActiveMove(for: group)
            adoptTrackedFrame(frame, for: group)

        default:
            break
        }
    }

    func beginTrackingActiveMove(for group: TabGroup) {
        if activeMoveGroup !== group || activeMoveOriginWindowID != group.activeWindow?.id {
            endTrackingActiveMove()
        }
        activeMoveGroup = group
        activeMoveOriginWindowID = group.activeWindow?.id
        WindowDiagnostics.record(.init(event: .trackingBegin, groupID: group.id,
            activeWindowID: group.activeWindow?.id, trackingWindowID: activeMoveOriginWindowID))
        guard activeMoveTimer == nil else { return }
        activeMoveDeadline = Date().addingTimeInterval(0.1)
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickActiveMove() }
        }
        activeMoveTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func adoptTrackedFrame(_ frame: CGRect, for group: TabGroup) {
        if frame != group.contentFrame {
            // Reset only on real geometry changes: duplicate AX notifications
            // must not prevent the panel from returning after motion stops.
            activeMoveDeadline = Date().addingTimeInterval(0.1)
            if frame.origin != group.contentFrame.origin, !group.isPanelHiddenForMove {
                group.isPanelHiddenForMove = true
                group.panel.hide(animated: false)
            }
        }
        group.contentFrame = frame
        if !group.isPanelHiddenForMove { positionPanel(for: group) }
    }

    func tickActiveMove() {
        guard let group = activeMoveGroup, let active = group.activeWindow,
              groups.contains(where: { $0 === group }),
              active.id == activeMoveOriginWindowID else {
            endTrackingActiveMove()
            return
        }
        let cgFrame = engine.windowServerFrame(of: active.id)
        let axFrame = cgFrame == nil ? engine.frame(of: active) : nil
        guard let frame = cgFrame ?? axFrame else {
            endTrackingActiveMove()
            return
        }
        WindowDiagnostics.record(.init(event: .trackingSample, windowID: active.id, pid: active.pid,
            groupID: group.id, activeWindowID: active.id, trackingWindowID: activeMoveOriginWindowID,
            groupFrame: WindowDiagnostics.frame(group.contentFrame),
            axFrame: WindowDiagnostics.frame(axFrame), cgFrame: WindowDiagnostics.frame(cgFrame),
            source: cgFrame == nil ? .accessibility : .windowServer))
        // Sample before testing the deadline, so a delayed tick cannot briefly
        // show the panel while the window has continued moving.
        adoptTrackedFrame(frame, for: group)
        if Date() >= activeMoveDeadline { endTrackingActiveMove() }
    }

    func endTrackingActiveMove(restorePanel: Bool = true) {
        WindowDiagnostics.record(.init(event: .trackingEnd, groupID: activeMoveGroup?.id,
            activeWindowID: activeMoveGroup?.activeWindow?.id, trackingWindowID: activeMoveOriginWindowID))
        activeMoveTimer?.invalidate()
        activeMoveTimer = nil
        let group = activeMoveGroup
        activeMoveGroup = nil
        activeMoveOriginWindowID = nil
        guard let group else { return }
        let wasHidden = group.isPanelHiddenForMove
        group.isPanelHiddenForMove = false
        guard restorePanel, wasHidden,
              groups.contains(where: { $0 === group }),
              isGroupOnActiveSpace(group) else { return }
        positionPanel(for: group)
        group.panel.show()
        reassertPanelZOrder(for: group)
        syncPanelZOrderWithFrontmostGroupSoon()
    }
}
