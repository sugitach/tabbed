// Shared with the non-GUI tests. Actual posts remain in InputLease under its lock.
enum InputRelease: Equatable { case mouseUp, commandUp }

struct InputHoldState {
    private(set) var started = false
    private(set) var finished = false
    private(set) var modifier = false
    private(set) var mouse = false
    private var mouseStarted = false

    mutating func pressModifier() -> Bool {
        guard !started, !finished else { return false }
        started = true; modifier = true
        return true
    }
    mutating func startMouse(command: Bool) -> Bool {
        guard !finished, !mouseStarted, !started || (modifier && command) else { return false }
        started = true; mouseStarted = true; mouse = true; modifier = command
        return true
    }
    mutating func endMouse() -> Bool {
        guard started, !finished, mouse else { return false }
        mouse = false
        if !modifier { finished = true }
        return true
    }
    mutating func release() -> [InputRelease] {
        guard started, !finished else { return [] }
        var actions: [InputRelease] = []
        if mouse { actions.append(.mouseUp) }
        if modifier { actions.append(.commandUp) }
        mouse = false; modifier = false; finished = true
        return actions
    }
}
