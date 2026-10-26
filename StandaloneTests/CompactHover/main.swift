import Foundation
import CoreGraphics

@MainActor func run() {
    var checks = 0
    let compact = CGRect(x: 0, y: 0, width: 60, height: 30)
    let full = CGRect(x: -240, y: 0, width: 300, height: 30)
    func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message); checks += 1
    }
    func fixture(delay: TimeInterval = 3) -> TabBarPanel {
        Timer.reset()
        NSEvent.mouseLocation = CGPoint(x: 10, y: 10)
        let panel = TabBarPanel()
        panel.applyLayout(compact: true, resting: compact, expanded: full, hoverExpansionDelay: delay)
        return panel
    }
    do {
        let p = fixture()
        p.handleHover(true)
        Timer.advance(2.99)
        check(!p.model.hovered && p.frame == compact, "stays compact before three seconds")
        Timer.advance(0.02)
        check(p.model.hovered && p.frame == full, "expands after three-second hover")
    }
    do {
        let p = fixture()
        p.handleHover(true); Timer.advance(2)
        p.handleHover(false); Timer.advance(2)
        check(!p.model.hovered, "leaving cancels pending expansion")
        p.handleHover(true); Timer.advance(2)
        check(!p.model.hovered, "return starts a fresh deadline")
        Timer.advance(1.01)
        check(p.model.hovered, "fresh continuous hover expands")
    }
    do {
        let p = fixture()
        p.handleHover(true); Timer.advance(1)
        p.collapseAfterSelection()
        p.applyLayout(compact: true, resting: compact, expanded: full, hoverExpansionDelay: 3)
        check(p.frame == compact && !p.model.hovered, "compact icon selection stays compact")
        Timer.advance(2.01)
        check(p.model.hovered, "selection/layout does not restart continuous hover")
        p.collapseAfterSelection()
        check(!p.model.hovered && p.frame == compact, "expanded selection still collapses")
        p.handleHover(true); Timer.advance(4)
        check(!p.model.hovered, "expanded selection waits for pointer exit")
        p.handleHover(false); p.handleHover(true); Timer.advance(3.01)
        check(p.model.hovered, "pointer exit rearms hover expansion")
    }
    do {
        let p = fixture()
        p.handleHover(true); Timer.advance(1); p.hide(); Timer.advance(4)
        check(!p.model.hovered && p.expansionTimer == nil, "hidden panel cancels pending expansion")
    }
    do {
        let p = fixture()
        p.handleHover(true); Timer.advance(1)
        p.applyLayout(compact: false, resting: full, expanded: full)
        Timer.advance(4)
        check(!p.model.hovered && p.frame == full && p.expansionTimer == nil, "normal mode cancels pending expansion")
        p.collapseAfterSelection()
        check(!p.model.hovered && p.frame == full, "normal-mode selection never collapses the panel")
    }
    do {
        let p = fixture()
        p.handleHover(true); Timer.advance(1)
        p.applyLayout(compact: true, resting: compact, expanded: full, hoverExpansionDelay: 0)
        Timer.advance(4)
        check(!p.model.hovered, "changing compact reason cancels old deadline")
        p.handleHover(true)
        check(p.model.hovered && p.frame == full, "space-constrained compact expands immediately")
    }
    do {
        let p = fixture()
        p.handleHover(true)
        NSEvent.mouseLocation = CGPoint(x: 500, y: 500)
        Timer.advance(3.01)
        check(!p.model.hovered, "stale tracking event cannot expand away from pointer")
    }
    do {
        let p = fixture(delay: 0)
        p.handleHover(true)
        check(p.model.hovered, "legacy immediate expansion retained")
        p.handleHover(false)
        NSEvent.mouseLocation = CGPoint(x: 500, y: 500)
        Timer.advance(0.02)
        check(!p.model.hovered, "legacy collapse safe zone retained")
    }
    print("PASS: \(checks) compact-hover checks (real production methods; simulated clock/UI boundaries)")
}
MainActor.assumeIsolated { run() }
