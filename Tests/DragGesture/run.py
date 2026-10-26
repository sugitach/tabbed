#!/usr/bin/env python3
"""Production gesture logic with fake window-server frames; no OS input."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[2]
raw = (root/'Sources/Drag/DragMonitor.swift').read_text()
# Only declaration visibility changes; compile the complete production class.
source = raw.replace('private ', '')
support='''import AppKit
import CoreGraphics
@MainActor final class NSEvent {
 enum EventType { case leftMouseDown, leftMouseDragged, leftMouseUp, flagsChanged, mouseMoved }
 struct EventTypeMask: OptionSet {
  let rawValue: Int
  static let leftMouseDown=Self(rawValue:1), leftMouseDragged=Self(rawValue:2),
   leftMouseUp=Self(rawValue:4), flagsChanged=Self(rawValue:8)
 }
 struct ModifierFlags: OptionSet { let rawValue: Int; static let command=Self(rawValue:1) }
 static var pressedMouseButtons=0
 static var mouseLocation=CGPoint.zero
 static var callback: ((NSEvent) -> Void)?
 static var added=0, removed=0
 static var failInstall=false
 static func addGlobalMonitorForEvents(matching mask: EventTypeMask, handler: @escaping (NSEvent) -> Void) -> Any? {
  precondition(mask == [.leftMouseDown,.leftMouseDragged,.leftMouseUp,.flagsChanged])
  if failInstall { return nil }
  added += 1; callback=handler; return added
 }
 static func removeMonitor(_ monitor: Any) {
  removed += 1
  if (monitor as? Int) == added { callback=nil }
 }
 let type: EventType
 let modifierFlags: ModifierFlags
 let cgEvent: CGEvent?
 init(_ type: EventType, _ point: CGPoint, _ command: Bool) {
  self.type=type; modifierFlags=command ? .command : []
  cgEvent=CGEvent(location:point)
 }
}
struct CGEvent { let location: CGPoint }
struct MonitoringEntry {
 enum Event { case inputMonitoringState }
 let event: Event
 let observerInstalled: Bool
 let receivedMouseEvent: Bool
 let startupReinstallCount: Int
 let gestureCandidateFound: Bool
}
@MainActor enum WindowDiagnostics {
 static var entries: [MonitoringEntry] = []
 static func record(_ entry: MonitoringEntry) { entries.append(entry) }
}
struct CoordinateConverter { static func appKitPoint(fromCG point: CGPoint) -> CGPoint { point } }
struct ManagedWindow { let id: UInt32 = 1 }
@MainActor final class WindowEngine {
 var frame: CGRect? = CGRect(x:100,y:100,width:800,height:600)
 func window(at: CGPoint, excluding: Set<UInt32>) -> ManagedWindow? { ManagedWindow() }
 func windowServerFrame(of id: UInt32) -> CGRect? { frame }
}
@MainActor final class Delegate: DragMonitorDelegate {
 var began=0, moved=0, ended=0, cancelled=0
 func dragDidBegin(window: ManagedWindow?, at: CGPoint) { began += 1 }
 func dragDidMove(to: CGPoint) { moved += 1 }
 func dragDidEnd(at: CGPoint) { ended += 1 }
 func dragDidCancel() { cancelled += 1 }
 func dragGroupingDidCancel() {}
 func dragDidEndWithoutGrouping(at: CGPoint) {}
}
'''
main='''import AppKit
import CoreGraphics
MainActor.assumeIsolated {
 let engine=WindowEngine(), delegate=Delegate()
 let monitor=DragMonitor(engine:engine); monitor.delegate=delegate
 precondition(monitor.start() && monitor.start() && NSEvent.added==1)
 var interactions=0
 monitor.onMouseInteraction = { interactions += 1 }
 @MainActor func send(_ type: NSEvent.EventType, _ x: CGFloat, _ command: Bool = true) {
  if type == .leftMouseDown { NSEvent.pressedMouseButtons = 1 }
  if type == .leftMouseUp { NSEvent.pressedMouseButtons = 0 }
  let event=NSEvent(type,CGPoint(x:x,y:100),command)
  NSEvent.callback?(event) // Void handler receives only the observation copy.
 }
 // An apparently installed but silent observer retries automatically, without
 // any menu action. Old queued callbacks cannot mutate the new generation.
 let stale=NSEvent.callback!
 monitor.checkInitialEventDelivery()
 precondition(NSEvent.added==1)
 monitor.checkInitialEventDelivery()
 precondition(NSEvent.added==2 && NSEvent.removed==1 && monitor.startupReinstallCount==1)
 stale(NSEvent(.leftMouseDown,CGPoint(x:100,y:100),true))
 precondition(monitor.candidateWindow==nil && !monitor.hasReceivedMouseEvent)
 // A held physical button postpones recovery even without observer delivery.
 NSEvent.pressedMouseButtons=1
 for _ in 0..<6 { monitor.checkInitialEventDelivery() }
 precondition(NSEvent.added==2)
 NSEvent.pressedMouseButtons=0
 // A failed replacement keeps the old token alive for the final retry.
 NSEvent.failInstall=true
 monitor.checkInitialEventDelivery(); monitor.checkInitialEventDelivery()
 precondition(NSEvent.added==2 && NSEvent.removed==1 && monitor.eventMonitor != nil)
 NSEvent.failInstall=false
 for _ in 0..<8 { monitor.checkInitialEventDelivery() }
 precondition(NSEvent.added==2 && monitor.startupDeliveryTimer==nil)
 // Content drag / click cannot group without actual window movement.
 send(.leftMouseDown,100); send(.leftMouseDragged,160); send(.leftMouseUp,160)
 precondition(delegate.began==0 && delegate.ended==0 && interactions==2)
 send(.leftMouseDown,100); send(.leftMouseUp,100)
 precondition(delegate.began==0)
 // Native movement is sufficient, regardless of title-bar implementation.
 send(.leftMouseDown,100); engine.frame!.origin.x=130
 send(.leftMouseDragged,130); send(.leftMouseUp,130)
 precondition(delegate.began==1 && delegate.ended==1)
 // Geometry can lag a dragged event and become visible at mouse-up.
 send(.leftMouseDown,130); send(.leftMouseDragged,160)
 engine.frame!.origin.x=160; send(.leftMouseUp,160)
 precondition(delegate.began==2 && delegate.ended==2)
 // Release Command pauses grouping, but re-press resumes this native drag.
 send(.leftMouseDown,160); engine.frame!.origin.x=190; send(.leftMouseDragged,190)
 send(.flagsChanged,190,false)
 engine.frame!.origin.x=220; send(.leftMouseDragged,220,false)
 precondition(delegate.ended==2 && delegate.cancelled==1)
 send(.flagsChanged,220,true)
 precondition(delegate.began==3)
 engine.frame!.origin.x=250; send(.leftMouseDragged,250); send(.leftMouseUp,250)
 precondition(delegate.ended==3 && engine.frame!.minX==250)
 // Cancel, continue moving without Command, release mouse, then retry same window.
 send(.leftMouseDown,250); engine.frame!.origin.x=280; send(.leftMouseDragged,280)
 send(.flagsChanged,280,false)
 engine.frame!.origin.x=310; send(.leftMouseDragged,310,false); send(.leftMouseUp,310,false)
 precondition(monitor.candidateWindow==nil && !monitor.commandIsHeld && !monitor.isObservingDrag)
 send(.leftMouseDown,310); engine.frame!.origin.x=340; send(.leftMouseDragged,340); send(.leftMouseUp,340)
 precondition(delegate.ended==4)
 // Native down can precede Command: still require actual movement of that window.
 send(.leftMouseDown,340,false); send(.flagsChanged,340)
 precondition(delegate.ended==4)
 engine.frame!.origin.x=370; send(.leftMouseDragged,370); send(.leftMouseUp,370)
 precondition(delegate.ended==5)
 // Resize rejection cannot be re-enabled by toggling Command.
 send(.leftMouseDown,370); engine.frame!.size.width=850; engine.frame!.origin.x=400
 send(.leftMouseDragged,400); send(.flagsChanged,400,false); send(.flagsChanged,400,true); send(.leftMouseUp,400)
 precondition(delegate.ended==5)
 engine.frame=nil; send(.leftMouseDown,400); send(.leftMouseDragged,430); send(.leftMouseUp,430)
 precondition(delegate.ended==5)
 // Modifier changes alone after release cannot resurrect the previous drag.
 engine.frame=CGRect(x:500,y:100,width:800,height:600)
 send(.flagsChanged,500,false); send(.flagsChanged,500,true)
 precondition(delegate.ended==5 && !monitor.isObservingDrag)
 // Toggling Command during content selection must not enable grouping.
 send(.leftMouseDown,500,false); send(.leftMouseDragged,530,false)
 send(.flagsChanged,530,true); send(.leftMouseDragged,560); send(.leftMouseUp,560)
 precondition(delegate.ended==5 && !monitor.isObservingDrag)
 // Lost mouse-up and unrelated window movement cannot let Command resurrect a drag.
 let previousBegins=delegate.began, previousEnds=delegate.ended
 send(.leftMouseDown,560,false)
 engine.frame!.origin.x=600
 NSEvent.pressedMouseButtons=0
 send(.flagsChanged,0,true)
 precondition(monitor.candidateWindow==nil && delegate.began==previousBegins)
 send(.flagsChanged,900,true); send(.leftMouseUp,900)
 precondition(delegate.began==previousBegins && delegate.ended==previousEnds)
 // Even with the button held, modifier coordinates and unrelated movement
 // are insufficient without an actual dragged event.
 send(.leftMouseDown,600,false); engine.frame!.origin.x=650
 send(.flagsChanged,0,true); send(.leftMouseUp,650)
 precondition(delegate.began==previousBegins && delegate.ended==previousEnds)
 // Own tab-panel releases use normal window delivery, canceling stale drags.
 send(.leftMouseDown,650); engine.frame!.origin.x=680; send(.leftMouseDragged,680)
 let before=delegate.ended, cancellations=delegate.cancelled
 monitor.ownPanelMouseUp()
 precondition(delegate.ended==before && delegate.cancelled==cancellations+1 && monitor.candidateWindow==nil)
 monitor.stop(); monitor.stop()
 precondition(NSEvent.removed==2 && NSEvent.callback==nil)
 NSEvent.failInstall=true
 precondition(!monitor.start())
 NSEvent.failInstall=false
 precondition(monitor.start() && NSEvent.added==3)
 let oldCallback=NSEvent.callback!
 // First real mouse delivery cancels further startup retries.
 send(.leftMouseDown,680,false)
 precondition(monitor.hasReceivedMouseEvent && monitor.startupDeliveryTimer==nil)
 for _ in 0..<8 { monitor.checkInitialEventDelivery() }
 precondition(NSEvent.added==3)
 monitor.stop()
 precondition(NSEvent.removed==3)
 oldCallback(NSEvent(.leftMouseDown,CGPoint(x:100,y:100),true))
 precondition(monitor.candidateWindow==nil && monitor.startupDeliveryTimer==nil)
 print("PASS: native movement, content/click observation, delayed geometry, Command pause/resume, next-drag reset, resize rejection, own-panel release, observer install/failure/idempotent stop, bounded startup recovery, held-button safety, failed replacement preservation, stale callbacks; no OS input")
}
'''
# Prevent native/AX double movement and input filtering from returning.
assert 'addGlobalMonitorForEvents' in raw
for forbidden in ['CGEvent.tap', 'tapPostEvent', 'engine.setFrame', 'addLocalMonitorForEvents']:
 assert forbidden not in raw, forbidden
controller=(root/'Sources/Group/TabGroupController.swift').read_text()
for name in ['dragDidBegin','dragDidMove','dragDidEndWithoutGrouping']:
 start=controller.index('    func '+name+'('); end=controller.index('\n    }',start)
 assert 'engine.setFrame' not in controller[start:end]
 assert 'engine.raise' not in controller[start:end]
with tempfile.TemporaryDirectory(prefix='tabbed-drag-') as directory:
 out=Path(directory)
 for name,text in [('DragMonitor.swift',source),('Support.swift',support),('main.swift',main)]: (out/name).write_text(text)
 subprocess.run(['/usr/bin/xcrun','swiftc','-swift-version','5','-module-cache-path',str(out/'cache'),str(out/'Support.swift'),str(out/'DragMonitor.swift'),str(out/'main.swift'),'-o',str(out/'tests')],check=True)
 subprocess.run([str(out/'tests')],check=True)
