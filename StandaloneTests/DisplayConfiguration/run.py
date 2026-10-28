#!/usr/bin/env python3
"""Actual topology/layout methods with fake screens/AX/clock. Never operates the desktop."""
from pathlib import Path
import hashlib, json, re, subprocess, tempfile
ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = Path(tempfile.mkdtemp(prefix='tabbed-display-tests-'))
selected = {
 'Group/TabGroupController+DisplayConfiguration.swift': ['deferDisplayLayout','rememberDisplayLayouts','displayConfigurationDidChange','scheduleDisplaySettlement','settleDisplayConfiguration'],
 'Group/TabGroupController+AXSync.swift': ['beginTrackingActiveMove','adoptTrackedFrame','tickActiveMove','endTrackingActiveMove'],
 'Group/TabGroupController+GroupOperations.swift': ['applyLayout','parkOffscreen','positionPanel','selectTab','beginPanelMove','updatePanelMove','endPanelMove'],
 'Group/TabGroupController+PanelZOrder.swift': ['reassertPanelZOrder'],
 'Group/TabGroupController+Workspace.swift': ['isGroupOnActiveSpace'],
 'UI/TabBarPanel.swift': ['applyLayout','cancelCollapseWatch','setExpanded','collapseAfterSelection','beginCollapseWatch','tickCollapseWatch','cancelPendingExpansion'],
}
def method(source, name):
 hit = re.search(r'(?m)^    (?:private )?func '+name+r'\(', source)
 if not hit: raise RuntimeError(name)
 opening=source.index('{',hit.end()); depth=1
 for end in range(opening+1,len(source)):
  if source[end]=='{': depth+=1
  elif source[end]=='}': depth-=1
  if not depth:return source[hit.start():end+1].replace('private func ','func ',1)
 raise RuntimeError(name)
parts=['import Foundation\nimport CoreGraphics']
hashes={}
for path,names in selected.items():
 data=(ROOT/'Sources'/path).read_bytes(); hashes[path]=hashlib.sha256(data).hexdigest()
 owner='Panel' if path.startswith('UI/') else 'Controller'
 parts += ['extension '+owner+' {']+[method(data.decode(),n) for n in names]+['}']
(OUT/'Production.swift').write_text('\n'.join(parts))
support=(ROOT/'Tests/MovementVisibility/Support.swift').read_text()
support=support.replace('    func deferDisplayLayout() -> Bool { false }','')
support=support.replace('    var contentFrame: CGRect','    var moveAnchorFrame: CGRect?\n    var displayLayouts = DisplayLayoutHistory()\n    var contentFrame: CGRect')
support=support.replace('    var isStopping = false','''    var isStarted = true
    let displayMonitor = DisplayConfigurationMonitor()
    var currentDisplayConfiguration: String? = "A"
    var displayTransitionPending = false
    var displayTransitionGeneration: UInt64 = 0
    var pendingShortcutSelection: Int?
    func dragDidCancel() { draggedWindow = nil }
    func syncPanelZOrderWithFrontmostGroupSoon(preferMainWindowForPID: pid_t? = nil) { syncCount += 1 }
    var isStopping = false''')
(OUT/'Support.swift').write_text(support + (HERE/'Support.swift').read_text())
(OUT/'main.swift').write_bytes((HERE/'main.swift').read_bytes())
sdk='/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk'
cmd=['xcrun','--sdk',sdk,'swiftc','-swift-version','5','-target','arm64-apple-macosx14.0','-sdk',sdk,'-module-cache-path',str(OUT/'cache')]
cmd += [str(ROOT/'Sources'/p) for p in ['App/WindowDiagnostics.swift','Group/DisplayLayoutHistory.swift','Group/WindowRestoration.swift']]
cmd += [str(OUT/p) for p in ['Support.swift','Production.swift','main.swift']]+['-o',str(OUT/'tests')]
r=subprocess.run(cmd,capture_output=True,text=True);(OUT/'compile.log').write_text(r.stdout+r.stderr)
print(r.stdout+r.stderr,end='');code=r.returncode
if not code:
 r=subprocess.run([OUT/'tests'],capture_output=True,text=True);(OUT/'run.log').write_text(r.stdout+r.stderr)
 print(r.stdout+r.stderr,end='');code=r.returncode
assert all(hashlib.sha256((ROOT/'Sources'/p).read_bytes()).hexdigest()==h for p,h in hashes.items())
(OUT/'result.json').write_text(json.dumps({'exitCode':code,'productionSHA256':hashes,'scope':'Actual controller/layout methods; fake OS boundaries; no physical hotplug'},indent=2))
print('RESULT_DIR='+str(OUT));raise SystemExit(code)
