import CoreGraphics

/// Pure shutdown policy, separate from AX and panels so it can be tested without permissions.
enum WindowRestoration {
    /// AX setters may return before the application publishes its new frame.
    /// Observe a bounded settling interval without repeating window writes.
    static func verify(frame: CGRect, read: () -> CGRect?, wait: () -> Void) -> Bool {
        for attempt in 0...10 {
            if let actual = read(),
               abs(actual.minX - frame.minX) <= 2, abs(actual.minY - frame.minY) <= 2,
               abs(actual.width - frame.width) <= 2, abs(actual.height - frame.height) <= 2 {
                return true
            }
            if attempt < 10 { wait() }
        }
        return false
    }

    static func destination(for frame: CGRect, screens: [CGRect]) -> CGRect? {
        guard isFinite(frame) else { return nil }
        let usable = screens.filter { isFinite($0) && !$0.isEmpty }
        guard let screen = usable.max(by: {
            area($0.intersection(frame)) < area($1.intersection(frame))
        }) else { return nil }
        let width = min(max(frame.width, 1), screen.width)
        let height = min(max(frame.height, 1), screen.height)
        return CGRect(x: min(max(frame.minX, screen.minX), screen.maxX - width),
                      y: min(max(frame.minY, screen.minY), screen.maxY - height),
                      width: width, height: height)
    }

    private static func isFinite(_ frame: CGRect) -> Bool {
        frame.minX.isFinite && frame.minY.isFinite && frame.width.isFinite && frame.height.isFinite
    }

    private static func area(_ frame: CGRect) -> CGFloat {
        frame.isNull || frame.isEmpty ? 0 : frame.width * frame.height
    }

    static func restore<Window>(
        _ entries: [(Window, CGRect)], screens: [CGRect],
        isAlive: (Window) -> Bool, move: (Window, CGRect) -> Bool
    ) -> [Window] {
        var failures: [Window] = []
        for (window, frame) in entries {
            guard isAlive(window) else { continue }
            let restored = destination(for: frame, screens: screens).map { move(window, $0) } ?? false
            // A window may close between the liveness check and the AX write.
            if !restored && isAlive(window) { failures.append(window) }
        }
        return failures
    }
}
