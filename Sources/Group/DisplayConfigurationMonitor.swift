import AppKit
import CoreGraphics

/// The Quartz callback only marks/queues a transition. It never reads or writes AX
/// windows, blocks the callback thread, or intercepts input.
final class DisplayConfigurationMonitor {
    private let lock = NSLock()
    private var revision: UInt64 = 0
    private var pending = false
    private var registered = false
    var onChange: (() -> Void)?

    var state: (revision: UInt64, pending: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (revision, pending)
    }

    @discardableResult
    func acknowledge(_ expected: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard revision == expected else { return false }
        pending = false
        return true
    }

    private static let callback: CGDisplayReconfigurationCallBack = { _, _, context in
        guard let context else { return }
        let monitor = Unmanaged<DisplayConfigurationMonitor>.fromOpaque(context).takeUnretainedValue()
        monitor.lock.lock()
        monitor.revision &+= 1
        monitor.pending = true
        monitor.lock.unlock()
        DispatchQueue.main.async { [weak monitor] in monitor?.onChange?() }
    }

    func start() {
        guard !registered else { return }
        registered = CGDisplayRegisterReconfigurationCallback(Self.callback,
            Unmanaged.passUnretained(self).toOpaque()) == .success
    }

    func stop() {
        if registered {
            CGDisplayRemoveReconfigurationCallback(Self.callback, Unmanaged.passUnretained(self).toOpaque())
            registered = false
        }
        onChange = nil
    }

    deinit { stop() }

    static func appKitMatchesQuartz() -> Bool {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return false }
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        return screens.allSatisfy { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            let id = number.uint32Value
            let frame = screen.frame
            let quartz = CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
            return CGDisplayIsActive(id) != 0 && quartz == CGDisplayBounds(id)
        }
    }

    static func currentKey() -> String? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return nil }
        func identity(_ id: CGDirectDisplayID) -> String {
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return String(id) }
            return CFUUIDCreateString(nil, uuid) as String
        }
        return DisplayConfiguration.key(for: ids.prefix(Int(count)).map { id in
            let mirror = CGDisplayMirrorsDisplay(id)
            return DisplayConfiguration.Screen(identity: identity(id), bounds: CGDisplayBounds(id),
                pixelWidth: CGDisplayPixelsWide(id), pixelHeight: CGDisplayPixelsHigh(id),
                rotation: CGDisplayRotation(id), mirrorIdentity: mirror == kCGNullDirectDisplay ? "" : identity(mirror),
                primary: id == CGMainDisplayID())
        })
    }
}
