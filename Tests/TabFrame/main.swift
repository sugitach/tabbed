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
        let (c,g)=fixture(); c.parkOffscreen(g.windows[1], relativeTo: g.contentFrame)
        let parked=c.engine.writes.last!.1
        assert(parked.size == g.contentFrame.size && parked.maxY == 1)
        assert(parked.intersection(saved[0].frame).height == 1)
        assert(parked.intersection(NSScreen.screens[1].frame).isNull)
        NSScreen.screens=saved
        print("PASS: parking stays on the source display across offset displays")
    }
    do {
        let (c,g)=fixture(); c.engine.frontmost=1; c.selectTab(1,in:g)
        assert(c.engine.writes.isEmpty)
        assert(g.activeIndex==0 && g.panel.relativeTo==1)
        print("PASS: selecting the already active tab does not rewrite window positions")
    }
    do {
        let saved = NSScreen.screens
        let primary = CGRect(x:0,y:0,width:3840,height:2160)
        let small = CGRect(x:3840,y:-742,width:1470,height:956)
        let square = CGRect(x:0,y:0,width:1000,height:1000)
        let surround = [square,
            CGRect(x:-2000,y:-2000,width:2000,height:5000),
            CGRect(x:1000,y:-2000,width:2000,height:5000),
            CGRect(x:0,y:-2000,width:1000,height:2000),
            CGRect(x:0,y:1000,width:1000,height:2000)]
        let cases: [(String, [CGRect], CGRect, Int, Bool)] = [
            ("actual tall primary with smaller offset neighbor", [primary,small],
                CGRect(x:0,y:0,width:1468,height:2129),0,false),
            ("group on the secondary display", [primary,small],
                CGRect(x:3900,y:-700,width:900,height:800),1,false),
            ("negative display coordinates", [CGRect(x:-1600,y:-200,width:1600,height:900),primary],
                CGRect(x:-1500,y:0,width:1200,height:650),0,false),
            ("blocked bottom edge", [square,CGRect(x:0,y:-1000,width:1000,height:1000)],
                CGRect(x:100,y:100,width:600,height:600),0,false),
            ("partly shared bottom edge", [square,CGRect(x:0,y:-1000,width:700,height:1000)],
                CGRect(x:100,y:100,width:600,height:600),0,false),
            ("display chosen by largest intersection", [square,square.offsetBy(dx:1000,dy:0)],
                CGRect(x:900,y:100,width:600,height:600),1,false),
            ("surrounded display uses stacking fallback", surround,
                CGRect(x:100,y:100,width:600,height:600),0,true),
            ("disconnected reference uses nearest display", [square,square.offsetBy(dx:3000,dy:0)],
                CGRect(x:1200,y:100,width:600,height:600),0,false),
        ]
        func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width*r.height }
        for (name, frames, reference, source, fallback) in cases {
            NSScreen.screens = frames.map { NSScreen(frame:$0,visibleFrame:$0) }
            let (c,g)=fixture(); g.contentFrame=reference
            // A previously shrunken inactive window must not select the target
            // display or determine the parked size.
            c.engine.frames[2]=CGRect(x:5309,y:-742,width:1468,height:922)
            c.applyLayout(for:g)
            let parked=c.engine.frames[2]!
            assert(parked.size == reference.size, name)
            assert(c.engine.frames[1] == reference && c.engine.raised.last == 1, name)
            if fallback {
                assert(parked == reference, name)
            } else {
                let visible=parked.intersection(frames[source])
                assert(area(visible)>0 && (visible.width<=1 || visible.height<=1), name)
                for index in frames.indices where index != source {
                    assert(area(parked.intersection(frames[index]))==0, name)
                }
            }
            print("PASS: " + name)
        }
        NSScreen.screens=saved
    }
    do {
        let saved = NSScreen.screens
        let source = CGRect(x:0,y:0,width:1000,height:1000)
        let neighbor = CGRect(x:1000,y:-1000,width:1000,height:1000)
        NSScreen.screens = [source,neighbor].map { NSScreen(frame:$0,visibleFrame:$0) }
        let (c,g)=fixture()
        g.contentFrame = CGRect(x:100,y:100,width:400,height:400)
        c.engine.frames[2] = CGRect(x:100,y:100,width:1400,height:800)
        c.engine.rejectSize.insert(2)
        c.applyLayout(for:g)
        let parked = c.engine.frames[2]!
        let visible = parked.intersection(source)
        assert(parked.size == CGSize(width:1400,height:800))
        assert(!visible.isNull && visible.height == 1)
        assert(parked.intersection(neighbor).isEmpty)
        assert(c.engine.writes.filter { $0.0 == 2 }.count == 2)
        assert(c.engine.raised.last == 1)
        print("PASS: refused resize recalculates parking from accepted dimensions")
        NSScreen.screens = saved
    }
    print("TOPIC_RESULT: 18 cases; simulated OS boundaries")
}
