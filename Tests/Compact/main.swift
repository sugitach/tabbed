import Foundation
import CoreGraphics
MainActor.assumeIsolated {
    do {
        let p=Panel(), resting=CGRect(x:900,y:500,width:60,height:30), expanded=CGRect(x:600,y:500,width:360,height:30)
        p.onFrameChanged={p.order(.above,relativeTo:42)}
        p.applyLayout(compact:true,resting:resting,expanded:expanded)
        p.handleHover(true); assert(p.model.hovered && p.frame==expanded)
        p.collapseAfterSelection(); assert(!p.model.hovered && p.frame==resting)
        p.handleHover(true); assert(!p.model.hovered)
        NSEvent.mouseLocation=CGPoint(x:500,y:400); p.tickCollapseWatch()
        p.handleHover(true); assert(p.model.hovered && p.frame==expanded)
        p.handleHover(false); p.tickCollapseWatch()
        assert(!p.model.hovered && p.frame==resting)
        p.applyLayout(compact:false,resting:expanded,expanded:expanded)
        p.collapseAfterSelection(); assert(p.frame==expanded && !p.model.hovered)
        print("PASS: compact selection collapses, rearms after exit, ")
    }
    print("TOPIC_RESULT: 1 cases; simulated OS boundaries")
}
