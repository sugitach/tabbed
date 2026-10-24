#!/usr/bin/env python3
"""Exercise exact layout/tracking/z-order methods with simulated OS boundaries."""
from pathlib import Path
import datetime, hashlib, json, re, subprocess
ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT/'Tests/Regression/results'/('tab-switch-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
OUT.mkdir(parents=True)
def method(source, name):
    hit = re.search(r'(?m)^    (?:private )?func '+name+r'\(', source)
    assert hit, name
    opening = source.index('{',hit.end()); depth = 1
    for end in range(opening+1,len(source)):
        if source[end]=='{': depth+=1
        elif source[end]=='}': depth-=1
        if depth==0: return source[hit.start():end+1].replace('private func ','func ',1)
    raise AssertionError(name)
selected = {
    'Group/TabGroupController.swift':['formGroup'],
    'Group/TabGroupController+GroupOperations.swift':['positionPanel','applyLayout','parkOffscreen','selectTab','dissolve'],
    'Group/TabGroupController+AXSync.swift':['handleWindowNotification','beginTrackingActiveMove','adoptTrackedFrame','tickActiveMove','endTrackingActiveMove'],
    'Group/TabGroupController+PanelZOrder.swift':['mouseInteractionDidOccur','reassertPanelZOrder','syncPanelZOrderWithFrontmostGroupSoon'],
    'Group/TabGroupController+Workspace.swift':['isGroupOnActiveSpace'],
}
parts=['import Foundation\nimport CoreGraphics\nextension Controller {']
hashes={}
for path,names in selected.items():
    raw=(ROOT/'Sources'/path).read_text(); hashes[path]=hashlib.sha256(raw.encode()).hexdigest()
    (OUT/Path(path).name).write_text(raw)
    parts.extend(method(raw,name) for name in names)
parts.append('}')
frame_source=(ROOT/'Sources/Accessibility/AXWindowEngine.swift').read_text()
hashes['Accessibility/AXWindowEngine.swift']=hashlib.sha256(frame_source.encode()).hexdigest()
(OUT/'AXWindowEngine.swift').write_text(frame_source)
parts += ['extension AXWindowEngine {',method(frame_source,'setFrame'),'}']
panel_source=(ROOT/'Sources/UI/TabBarPanel.swift').read_text()
hashes['UI/TabBarPanel.swift']=hashlib.sha256(panel_source.encode()).hexdigest()
(OUT/'TabBarPanel.swift').write_text(panel_source)
parts += ['extension Panel {'] + [method(panel_source,n) for n in ['applyLayout','handleHover','setExpanded','collapseAfterSelection','beginCollapseWatch','tickCollapseWatch','cancelCollapseWatch']] + ['}']
(OUT/'ProductionMethods.swift').write_text('\n'.join(parts))
for name in ['Support.swift','main.swift']:
    (OUT/name).write_bytes((HERE/name).read_bytes())
sdk='/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk'
command=['/usr/bin/xcrun','swiftc','-swift-version','5','-target','arm64-apple-macosx14.0','-sdk',sdk,'-module-cache-path',str(OUT/'module-cache'),str(ROOT/'Sources/App/WindowDiagnostics.swift'),str(OUT/'Support.swift'),str(OUT/'ProductionMethods.swift'),str(OUT/'main.swift'),'-o',str(OUT/'tests')]
(OUT/'source-sha256.json').write_text(json.dumps(hashes,indent=2))
(OUT/'command.json').write_text(json.dumps(command,indent=2))
result=subprocess.run(command,capture_output=True,text=True)
(OUT/'compile.log').write_text(result.stdout+result.stderr)
print(result.stdout+result.stderr,end='')
if result.returncode==0:
    result=subprocess.run([str(OUT/'tests')],capture_output=True,text=True)
    (OUT/'run.log').write_text(result.stdout+result.stderr)
    print(result.stdout+result.stderr,end='')
print('RESULT_DIR='+str(OUT))
raise SystemExit(result.returncode)
