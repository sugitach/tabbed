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
        let (c,g)=fixture(); let desired=g.contentFrame
        c.beginTrackingActiveMove(for:g)
        c.activeMoveDeadline = .distantFuture
        c.engine.cgFrames[2]=CGRect(x:100,y:200,width:1100,height:720)
        c.selectTab(2,in:g)
        c.tickActiveMove()
        assert(c.activeMoveGroup == nil && c.engine.cgReads.isEmpty && g.contentFrame==desired)
        print("PASS: tab selection cancels previous window tracking")
    }
    do {
        let (c,g)=fixture(); let desired=g.contentFrame
        c.beginTrackingActiveMove(for:g); c.activeMoveDeadline = .distantFuture
        g.activeIndex=1 // Also protect switches that bypass selectTab.
        c.engine.cgFrames[2]=CGRect(x:100,y:200,width:1100,height:720)
        c.tickActiveMove()
        assert(c.activeMoveGroup == nil && c.engine.cgReads.isEmpty && g.contentFrame==desired)
        print("PASS: tracking rejects a changed active window identity")
    }
    do {
        let (c,g)=fixture()
        let user=CGRect(x:120,y:220,width:700,height:500)
        c.engine.frames[1]=user
        c.handleWindowNotification(id:1,notification:kAXResizedNotification)
        assert(g.contentFrame==user)
        let next=CGRect(x:130,y:230,width:710,height:510)
        c.engine.cgFrames[1]=next; c.tickActiveMove()
        assert(g.contentFrame==next)
        print("PASS: legitimate active resize and same-window tracking remain enabled")
    }
    do {
        let (c,g)=fixture(); let desired=g.contentFrame
        c.handleWindowNotification(id:99,notification:kAXResizedNotification)
        c.handleWindowNotification(id:2,notification:kAXResizedNotification)
        assert(g.contentFrame==desired && c.engine.reads.isEmpty)
        print("PASS: unmanaged and inactive notifications cannot change group geometry")
    }
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
        let (c,g)=fixture(); c.engine.rejectSize.insert(2)
        c.selectTab(2,in:g)
        c.handleWindowNotification(id:2,notification:kAXResizedNotification)
        assert(g.contentFrame.height==720)
        print("KNOWN LIMITATION: persistent rejected size still propagates; real AX resize fix requires OS verification")
    }
    do {
        let engine=AXWindowEngine()
        let desired=CGRect(x:100,y:200,width:1359,height:1070)
        engine.setFrame(desired,of:Window(42,100))
        assert(engine.actual==desired && engine.operations==["position","size","position"])
        print("PASS: move before resize avoids simulated parked-display clamping")
    }
    do {
        let engine=AXWindowEngine()
        let parked=CGRect(x:1439,y:-679,width:1100,height:720)
        engine.setFrame(parked,of:Window(42,100))
        assert(engine.actual==parked && engine.operations==["size","position"])
        print("PASS: unchanged-size parking keeps the existing setter order")
    }
    do {
        let saved = NSScreen.screens
        NSScreen.screens = saved + [NSScreen(frame:CGRect(x:1440,y:-742,width:1470,height:956),visibleFrame:CGRect(x:1440,y:-742,width:1470,height:924))]
        let (c,g)=fixture(); c.parkOffscreen(g.windows[1])
        let parked=c.engine.writes.last!.1
        assert(parked.minX==2909 && parked.maxY == -741)
        NSScreen.screens=saved
        print("PASS: parking uses the desktop outer edge across offset displays")
    }
    do {
        let (c,g)=fixture(); c.selectTab(1,in:g)
        assert(c.engine.writes.isEmpty)
        assert(g.activeIndex==0 && g.panel.relativeTo==1)
        print("PASS: selecting the already active tab does not rewrite window positions")
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
        assert(c.syncCount==5 && g.panel.forcedFront>0 && g.panel.relativeTo==1)
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
        assert(c.syncCount==5 && g.panel.forcedFront>0 && g.panel.relativeTo==1)
        print("PASS: ordinary clicks schedule panel repair without focus notifications ")
    }
    do {
        let c=Controller()
        let a=Window(1,10), b=Window(2,10), d=Window(3,20), e=Window(4,20)
        let source=Group([a,b],CGRect(x:20,y:20,width:600,height:400))
        source.activeIndex=1; source.panel.show()
        let targetFrame=CGRect(x:700,y:100,width:800,height:500)
        let destination=Group([d,e],targetFrame)
        c.groups=[source,destination]
        c.engine.frames=[1:source.contentFrame,2:source.contentFrame,3:targetFrame,4:targetFrame]
        c.engine.spaces=[1:1,2:1,3:2,4:2]
        c.formGroup(dragged:b,target:d)
        assert(c.groups.count==1 && c.groups[0] === destination)
        assert(destination.windows.map(\.id)==[3,4,1,2] && destination.activeWindow?.id==2)
        assert(destination.contentFrame==targetFrame && !source.panel.visible)
        assert(c.engine.spaceMoves==[1,2])
        let writes=c.engine.writes.count
        c.formGroup(dragged:b,target:a)
        assert(c.groups.count==1 && c.engine.writes.count==writes)
        print("PASS: merging groups retains every member, moves every source Space, preserves order/frame and active tab; same-group drop is inert")
    }
    do {
        let c=Controller()
        let a=Window(1,10), b=Window(2,10), target=Window(3,20)
        let frame=CGRect(x:200,y:100,width:700,height:500)
        let source=Group([a,b],frame); source.activeIndex=1
        c.groups=[source]; c.engine.frames=[1:frame,2:frame,3:frame]
        c.formGroup(dragged:b,target:target)
        assert(c.groups.count==1)
        assert(c.groups[0].windows.map(\.id)==[3,1,2] && c.groups[0].activeWindow?.id==2)
        assert(c.groups[0].contentFrame==frame)
        print("PASS: dropping a group onto a single window retains all source tabs")
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
    do {
        for compact in [false, true] {
            DispatchQueue.main.drain()
            let (c,g)=fixture(); g.useCompact=compact; c.applyLayout(for:g)
            let panelFrame=g.panel.frame
            let moved=g.contentFrame.offsetBy(dx:80,dy:40)
            c.engine.frames[1]=moved; c.engine.cgFrames[1]=moved
            let before=Date()
            c.handleWindowNotification(id:1,notification:kAXMovedNotification)
            assert(g.isPanelHiddenForMove && !g.panel.visible && g.contentFrame==moved)
            assert(c.activeMoveDeadline>=before.addingTimeInterval(0.1) && c.activeMoveDeadline<=Date().addingTimeInterval(0.1))
            c.activeMoveDeadline = .distantFuture
            c.positionPanel(for:g); c.mouseInteractionDidOccur(); DispatchQueue.main.drain()
            c.reassertPanelZOrder(for:g)
            assert(!g.panel.visible && g.panel.frame==panelFrame, "Focus/order repair cannot reveal or reposition a moving panel")
            c.tickActiveMove(); assert(!g.panel.visible)
            c.activeMoveDeadline = .distantPast
            c.tickActiveMove()
            assert(g.panel.visible && !g.isPanelHiddenForMove && c.activeMoveGroup == nil)
            assert(g.panel.frame==g.stripFrame && g.panel.relativeTo==1)
            assert(c.engine.writes.count==2, "Move tracking must never move the content window")
        }
        print("PASS: normal and compact panels hide while moving and return at the final position after 0.1 seconds of stability")
    }
    do {
        let (c,g)=fixture(); g.panel.show()
        let moved=g.contentFrame.offsetBy(dx:30,dy:10)
        c.engine.frames[1]=moved; c.engine.cgFrames[1]=moved
        c.handleWindowNotification(id:1,notification:kAXMovedNotification)
        c.activeMoveDeadline = .distantPast
        let continued=moved.offsetBy(dx:50,dy:0)
        c.engine.cgFrames[1]=continued
        c.draggedWindow=g.activeWindow // Command-grouping drag is still a native move.
        c.tickActiveMove()
        assert(!g.panel.visible && g.contentFrame==continued && c.activeMoveDeadline>Date())
        let deadline=c.activeMoveDeadline
        c.engine.frames[1]=continued
        c.handleWindowNotification(id:1,notification:kAXMovedNotification)
        assert(c.activeMoveDeadline==deadline, "Duplicate notifications do not postpone the return")
        c.activeMoveDeadline = .distantPast; c.tickActiveMove()
        assert(g.panel.visible)
        print("PASS: continued native/Command movement resets stability, duplicate notifications do not, and an expired tick samples before showing")
    }
    do {
        let (c,g)=fixture(); g.panel.show()
        var resized=g.contentFrame; resized.size.width+=100
        c.engine.frames[1]=resized; c.engine.cgFrames[1]=resized
        c.handleWindowNotification(id:1,notification:kAXResizedNotification)
        assert(g.panel.visible && !g.isPanelHiddenForMove && g.contentFrame==resized)
        c.activeMoveDeadline = .distantPast; c.tickActiveMove()
        assert(g.panel.visible)
        print("PASS: resize without a position change keeps the panel visible")
    }
    do {
        for action in ["dissolve", "space", "closed"] {
            let (c,g)=fixture(); g.panel.show()
            let moved=g.contentFrame.offsetBy(dx:10,dy:20)
            c.engine.frames[1]=moved; c.engine.cgFrames[1]=moved
            c.handleWindowNotification(id:1,notification:kAXMovedNotification)
            switch action {
            case "dissolve": c.dissolve(g)
            case "quit": c.isStopping=true; c.endTrackingActiveMove()
            case "space": g.spaceID=3; c.engine.activeSpaces=[4]
            default: c.groups=[]
            }
            c.activeMoveDeadline = .distantPast; c.tickActiveMove()
            DispatchQueue.main.drain()
            assert(!g.panel.visible && !g.isPanelHiddenForMove)
        }
        print("PASS: dissolved groups, other Spaces and removed groups cannot resurrect a hidden panel")
    }
    print("TOPIC_RESULT: 22 cases; simulated OS boundaries")
}
