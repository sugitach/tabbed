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
    print("TOPIC_RESULT: 2 cases; simulated OS boundaries")
}
