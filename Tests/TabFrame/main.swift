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
        let (c,g)=fixture(); c.engine.frontmost=1; c.selectTab(1,in:g)
        assert(c.engine.writes.isEmpty)
        assert(g.activeIndex==0 && g.panel.relativeTo==1)
        print("PASS: selecting the already active tab does not rewrite window positions")
    }
    print("TOPIC_RESULT: 9 cases; simulated OS boundaries")
}
