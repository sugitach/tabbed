import Foundation
import CoreGraphics
@MainActor func fixture() -> (Controller, Group) {
    let c = Controller()
    let g = Group([Window(1,100),Window(2,100)],CGRect(x:100,y:200,width:640,height:480))
    c.groups=[g]
    c.engine.frames=[1:g.contentFrame,2:CGRect(x:1439,y:-679,width:1100,height:720)]
    return (c,g)
}
MainActor.assumeIsolated {
    do {
        let (c,g)=fixture(); c.applyLayout(for:g)
        assert(g.panel.visible && g.panel.relativeTo==1)
        print("PASS: panel is anchored after show resets ordering")
    }
    do {
        let (c,g)=fixture(); c.reassertPanelZOrder(for:g)
        assert(g.panel.relativeTo==1)
        print("PASS: background group ordering targets its own window")
    }
    do {
        let (c,g)=fixture(); WindowServerSnapshot.ids=[1,900]; c.engine.frontmost=1
        c.reassertPanelZOrder(for:g)
        assert(g.panel.forcedFront==1 && g.panel.relativeTo==1)
        WindowServerSnapshot.ids=[900,1]; c.reassertPanelZOrder(for:g)
        assert(g.panel.forcedFront==1)
        WindowServerSnapshot.ids=[99,1,900]; c.engine.frontmost=99
        c.reassertPanelZOrder(for:g)
        assert(g.panel.forcedFront==1 && g.panel.relativeTo==1)
        WindowServerSnapshot.ids=[]
        print("PASS: buried frontmost strip gets fallback; background and already-front strips do not")
    }
    do {
        DispatchQueue.main.drain()
        let (c,g)=fixture()
        WindowServerSnapshot.ids=[900,1]; c.engine.frontmost=1
        c.reassertPanelZOrder(for:g)
        c.syncPanelZOrderWithFrontmostGroupSoon()
        c.syncPanelZOrderWithFrontmostGroupSoon()
        // Simulate the destination app raising its window after our initial order.
        WindowServerSnapshot.ids=[1,900]
        DispatchQueue.main.drain()
        assert(c.syncCount==6 && g.panel.forcedFront>0 && g.panel.relativeTo==1)
        WindowServerSnapshot.ids=[] // Earlier generation has no effect.
        print("PASS: delayed order checks coalesce ")
    }
    do {
        DispatchQueue.main.drain()
        let (c,g)=fixture()
        WindowServerSnapshot.ids=[1,900]; c.engine.frontmost=1
        // No focus/activation notification: a plain content click alone repairs.
        c.mouseInteractionDidOccur()
        DispatchQueue.main.drain()
        assert(c.syncCount==6 && g.panel.forcedFront>0 && g.panel.relativeTo==1)
        print("PASS: ordinary clicks schedule panel repair without focus notifications ")
    }
    do {
        DispatchQueue.main.drain()
        let c=Controller(), a=Window(1,10), b=Window(2,10)
        let frame=CGRect(x:200,y:100,width:700,height:500)
        c.engine.frames=[1:frame,2:frame]; c.engine.frontmost=2
        var previous: Group?
        for _ in 0..<3 {
            // Ordering initially succeeds; a later native raise buries the new
            // panel, without any further click, move, or activation callback.
            WindowServerSnapshot.ids=[900,2]
            c.formGroup(dragged:b,target:a)
            let group=c.groups[0]
            assert(group !== previous && group.panel.visible)
            let writes=c.engine.writes.count
            WindowServerSnapshot.ids=[2,900]
            DispatchQueue.main.drain()
            assert(group.panel.forcedFront>0 && group.panel.relativeTo==2,
                   "New/recreated group must recover from a delayed native raise")
            assert(c.engine.writes.count==writes, "Order repair must not move content windows")
            c.dissolve(group)
            assert(c.groups.isEmpty && !group.panel.visible)
            previous=group
        }
        WindowServerSnapshot.ids=[]
        print("PASS: grouping and repeated dissolve/regroup repair a delayed raise without further input or window movement")
    }
    do {
        let (c,g)=fixture(); g.spaceID=6
        c.engine.activeSpaces=[3,6]
        c.engine.spaces[1]=6
        assert(c.isGroupOnActiveSpace(g), "A group on another display's current Space is visible")
        // Restoring a parked window can change its live Space after the group
        // captured its original target. Follow that window, not the old ID.
        c.engine.spaces[1]=3
        assert(c.isGroupOnActiveSpace(g))
        c.engine.activeSpaces=[4,6]
        assert(!c.isGroupOnActiveSpace(g), "A stale group Space cannot keep the panel on another desktop")
        c.engine.spaces[1]=nil
        assert(c.isGroupOnActiveSpace(g), "Unavailable live identity falls back to the remembered Space")
        c.engine.activeSpaces=[4]
        assert(!c.isGroupOnActiveSpace(g))
        c.engine.activeSpaces=nil
        assert(c.isGroupOnActiveSpace(g), "An unavailable Space query must retain the existing permissive fallback")
        print("PASS: group visibility covers every display, follows live Space identity, and respects desktop switches")
    }
    print("TOPIC_RESULT: 7 cases; simulated OS boundaries")
}
