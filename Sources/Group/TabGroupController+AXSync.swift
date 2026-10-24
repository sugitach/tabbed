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
                  id != draggedWindow?.id,
                  isGroupOnActiveSpace(group) else {
                WindowDiagnostics.record(.init(event: .notificationIgnored, windowID: id,
                    groupID: group.id, activeWindowID: group.activeWindow?.id,
                    reason: group.activeWindow?.id != id ? .inactive : (id == draggedWindow?.id ? .dragging : .wrongSpace)))
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
            group.contentFrame = frame
            positionPanel(for: group)
            beginTrackingActiveMove(for: group)

        default:
            break
        }
    }

    func beginTrackingActiveMove(for group: TabGroup) {
        activeMoveGroup = group
        activeMoveOriginWindowID = group.activeWindow?.id
        WindowDiagnostics.record(.init(event: .trackingBegin, groupID: group.id,
            activeWindowID: group.activeWindow?.id, trackingWindowID: activeMoveOriginWindowID))
        activeMoveDeadline = Date().addingTimeInterval(0.2)
        guard activeMoveTimer == nil else { return }
        activeMoveTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickActiveMove() }
        }
    }

    func tickActiveMove() {
        guard let group = activeMoveGroup, let active = group.activeWindow,
              active.id != draggedWindow?.id, Date() <= activeMoveDeadline else {
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
        group.contentFrame = frame
        positionPanel(for: group)
    }

    func endTrackingActiveMove() {
        WindowDiagnostics.record(.init(event: .trackingEnd, groupID: activeMoveGroup?.id,
            activeWindowID: activeMoveGroup?.activeWindow?.id, trackingWindowID: activeMoveOriginWindowID))
        activeMoveTimer?.invalidate()
        activeMoveTimer = nil
        activeMoveGroup = nil
        activeMoveOriginWindowID = nil
    }
}
