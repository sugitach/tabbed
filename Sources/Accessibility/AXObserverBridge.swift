import ApplicationServices
import Foundation

@MainActor
final class AXObserverBridge {
    var onEvent: ((WindowID, String) -> Void)?

    private struct Observation {
        let observer: AXObserver
        let source: CFRunLoopSource
        let element: AXUIElement
        let pid: pid_t
    }

    private var observations: [WindowID: Observation] = [:]

    func observe(_ window: ManagedWindow) {
        guard observations[window.id] == nil else { return }

        var observer: AXObserver?
        let created = AXObserverCreate(window.pid, Self.callback, &observer)
        WindowDiagnostics.record(.init(event: .observerCreated, windowID: window.id,
            pid: window.pid, status: created.rawValue))
        guard created == .success,
              let observer else {
            return
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in Self.notifications {
            let status = AXObserverAddNotification(observer, window.element, notification as CFString, refcon)
            WindowDiagnostics.record(.init(event: .observerRegistered, windowID: window.id,
                pid: window.pid, status: status.rawValue, notification: WindowDiagnostics.notification(notification)))
        }

        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        observations[window.id] = Observation(observer: observer, source: source, element: window.element, pid: window.pid)
    }

    /// Match by element identity because destroyed windows may not resolve by id.
    private func windowID(for element: AXUIElement) -> WindowID? {
        for (id, observation) in observations where CFEqual(observation.element, element) {
            return id
        }
        return nil
    }

    func unobserve(_ id: WindowID) {
        guard let observation = observations.removeValue(forKey: id) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), observation.source, .commonModes)
    }

    private static let notifications = [
        kAXMovedNotification,
        kAXResizedNotification,
        kAXUIElementDestroyedNotification,
        kAXWindowMiniaturizedNotification
    ]

    private static let callback: AXObserverCallback = { observer, element, notification, refcon in
        guard let refcon else { return }

        MainActor.assumeIsolated {
            let bridge = Unmanaged<AXObserverBridge>.fromOpaque(refcon).takeUnretainedValue()
            guard let windowID = bridge.windowID(for: element) else {
                if WindowDiagnostics.isRecording {
                    let expected = bridge.observations.first { CFEqual($0.value.observer, observer) }
                    WindowDiagnostics.record(.init(event: .notificationIgnored, windowID: expected?.key,
                        pid: expected?.value.pid, notification: WindowDiagnostics.notification(notification as String),
                        reason: .unmatchedElement))
                }
                return
            }
            bridge.onEvent?(windowID, notification as String)
        }
    }
}
