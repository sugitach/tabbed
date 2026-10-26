import Foundation
import CoreGraphics

// Deterministic boundary clock; no sleeps, windows, or generated input.
@MainActor final class Timer {
    static var now: TimeInterval = 0
    static var scheduled: [Timer] = []
    let interval: TimeInterval
    let repeats: Bool
    let callback: (Timer) -> Void
    var deadline: TimeInterval
    var valid = true
    init(timeInterval: TimeInterval, repeats: Bool, block: @escaping (Timer) -> Void) {
        interval = timeInterval; self.repeats = repeats; callback = block
        deadline = Self.now + timeInterval
    }
    static func scheduledTimer(withTimeInterval interval: TimeInterval, repeats: Bool,
                               block: @escaping (Timer) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats, block: block)
        scheduled.append(timer)
        return timer
    }
    func invalidate() { valid = false }
    static func advance(_ interval: TimeInterval) {
        let end = now + interval
        while let next = scheduled.filter({ $0.valid && $0.deadline <= end }).min(by: { $0.deadline < $1.deadline }) {
            now = next.deadline
            if next.repeats { next.deadline += next.interval } else { next.valid = false }
            next.callback(next)
        }
        now = end
        scheduled.removeAll { !$0.valid }
    }
    static func reset() { now = 0; scheduled = [] }
}
@MainActor enum RunLoop {
    enum Mode { case common }
    static let main = Loop()
    @MainActor final class Loop {
        func add(_ timer: Timer, forMode mode: Mode) { Timer.scheduled.append(timer) }
    }
}
@MainActor enum NSEvent { static var mouseLocation = CGPoint(x: 10, y: 10) }
@MainActor final class Model { var hovered = false }
@MainActor final class TabBarPanel {
    enum AnimationBehavior { case `default`, none }
    var animationBehavior = AnimationBehavior.default
    var onFrameChanged: (() -> Void)?
    let model = Model()
    var waitForPointerExit = false, isCompact = false, isPointerHovering = false
    var restingFrame = CGRect.zero, expandedFrame = CGRect.zero
    let collapseSafeZoneX: CGFloat = 28, collapseSafeZoneY: CGFloat = 72
    var collapseWatcher: Timer?, expansionTimer: Timer?
    var hoverExpansionDelay: TimeInterval = 0
    var isVisible = true
    var frame = CGRect.zero
    func setFrame(_ value: CGRect, display: Bool) { frame = value }
    func orderOut(_ sender: Any?) { isVisible = false }
}
