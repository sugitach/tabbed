import Foundation
import CoreGraphics
@MainActor func run() throws {
var count = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message); count += 1
}
func frame(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 1000, _ h: CGFloat = 700) -> CGRect {
    CGRect(x:x,y:y,width:w,height:h)
}
func screen(_ f: CGRect) -> NSScreen { NSScreen(frame:f,visibleFrame:f) }
func settle() { for _ in 0..<4 { DispatchQueue.main.drain() } }
let builtIn = screen(frame(0,0,1440,900)), external = screen(frame(1440,0,1920,1080))
let a = frame(1600,120), b = frame(80,90), movedB = frame(140,140,1100,720)
let c = Controller(), group = Group([Window(1,10),Window(2,10)],a)
c.groups=[group];c.engine.frames=[1:a,2:a];c.engine.frontmost=1
NSScreen.screens=[builtIn,external]
// Quartz can mark a transition before the main-queue begin callback.
c.displayMonitor.pending=true
DisplayConfigurationMonitor.key="B";NSScreen.screens=[builtIn]
c.engine.frames[1]=b
check(c.deferDisplayLayout(),"early callback gates layout")
c.applyLayout(for:group);c.adoptTrackedFrame(b,for:group);c.selectTab(2,in:group)
check(c.engine.writes.isEmpty && group.contentFrame==a && group.activeIndex==0,"no AX adoption/writes/switch during transition")
settle()
check(!c.displayTransitionPending && group.contentFrame==b,"first configuration adopts macOS placement")
check(c.engine.frames[1]==b && c.engine.writes.contains{$0.0==2},"active restored and inactive reparked")
check(group.displayLayouts.frame(for:"A")==a,"original layout survives OS movement")
c.adoptTrackedFrame(movedB,for:group)
DisplayConfigurationMonitor.key="A";NSScreen.screens=[builtIn,external];c.engine.frames[1]=frame(0,0,600,400)
c.displayConfigurationDidChange();settle()
check(group.contentFrame==a,"reconnection restores A position and size")
check(group.displayLayouts.frame(for:"B")==movedB,"deliberate movement remembered in B")
DisplayConfigurationMonitor.key="B";NSScreen.screens=[builtIn];c.engine.frames[1]=frame(0,0)
c.displayConfigurationDidChange();settle()
check(group.contentFrame==movedB,"second visit restores latest B")
// Multiple groups and a rapid intermediate configuration must not overwrite either layout.
let second=Group([Window(3,11),Window(4,11)],frame(200,80,800,600))
c.groups.append(second);c.engine.frames[3]=second.contentFrame;c.engine.frames[4]=second.contentFrame
c.displayConfigurationDidChange();DisplayConfigurationMonitor.key="C"
c.displayConfigurationDidChange();DisplayConfigurationMonitor.key="B"
c.displayConfigurationDidChange();settle()
check(group.contentFrame==movedB && second.contentFrame==frame(200,80,800,600),"rapid A/B sequence preserves both groups")
// Do not settle using stale AppKit screen geometry even if Quartz is already updated.
DisplayConfigurationMonitor.key="A";DisplayConfigurationMonitor.appKitReady=false
c.displayConfigurationDidChange();settle()
check(c.displayTransitionPending,"wait for AppKit coordinate conversion to catch up")
DisplayConfigurationMonitor.appKitReady=true;NSScreen.screens=[builtIn,external];settle()
check(group.contentFrame==a,"restore after AppKit catches up")
// A group on another Space is remembered but not written there.
second.spaceID=2;c.engine.spaces[3]=2;c.engine.activeSpaces=[1]
DisplayConfigurationMonitor.key="B";NSScreen.screens=[builtIn];c.displayConfigurationDidChange()
c.engine.writes=[];settle()
check(!c.engine.writes.contains{$0.0==3 || $0.0==4},"other Space not moved during hotplug")
// A strip drag must not keep writing its old anchor across topology changes.
c.beginPanelMove(for: group)
check(group.moveAnchorFrame != nil, "strip drag begins in stable configuration")
c.displayConfigurationDidChange(); let beforeDrag = group.contentFrame
c.engine.writes=[]
c.updatePanelMove(for:group,translation:CGSize(width:400,height:200))
c.beginPanelMove(for:group);c.endPanelMove(for:group)
check(group.moveAnchorFrame == nil && group.contentFrame == beforeDrag && c.engine.writes.isEmpty,
    "transition invalidates strip drag and blocks subsequent drag callbacks")
settle();c.engine.writes=[];let settled = group.contentFrame
c.updatePanelMove(for:group,translation:CGSize(width:400,height:200));c.endPanelMove(for:group)
check(group.contentFrame == settled && c.engine.writes.isEmpty,
    "old strip gesture stays cancelled after settlement")
c.beginPanelMove(for:group);c.updatePanelMove(for:group,translation:CGSize(width:20,height:10))
check(group.contentFrame == settled.offsetBy(dx:20,dy:10) && !c.engine.writes.isEmpty,
    "fresh strip drag works after settlement")
c.endPanelMove(for:group)
check(group.moveAnchorFrame == nil, "completed strip drag clears its anchor")
// Pending settlement must be inert after termination.
c.displayConfigurationDidChange();c.isStopping=true;let writes=c.engine.writes.count;settle()
check(c.engine.writes.count==writes,"no callback writes after stop")
// Canonical identity and bounded serializable history.
let one=DisplayConfiguration.Screen(identity:"one",bounds:builtIn.frame,pixelWidth:2880,pixelHeight:1800,rotation:0,mirrorIdentity:"",primary:true)
let two=DisplayConfiguration.Screen(identity:"two",bounds:external.frame,pixelWidth:1920,pixelHeight:1080,rotation:0,mirrorIdentity:"",primary:false)
check(DisplayConfiguration.key(for:[one,two])==DisplayConfiguration.key(for:[two,one]),"enumeration order irrelevant")
let rearranged=DisplayConfiguration.Screen(identity:"two",bounds:frame(-1920,0,1920,1080),pixelWidth:1920,pixelHeight:1080,rotation:0,mirrorIdentity:"",primary:false)
check(DisplayConfiguration.key(for:[one,two]) != DisplayConfiguration.key(for:[one,rearranged]),"arrangement changes identity")
var history=DisplayLayoutHistory()
for i in 0..<20 { history.remember(a,for:String(i)) }
check(history.entries.count==16 && history.frame(for:"0")==nil && history.isValid,"bounded history")
let decoded=try JSONDecoder().decode(DisplayLayoutHistory.self,from:JSONEncoder().encode(history))
check(decoded.frame(for:"19")==a && decoded.isValid,"history survives serialization")
print("DISPLAY_CONFIGURATION_RESULT: \(count)/\(count)")

}
try MainActor.assumeIsolated { try run() }
