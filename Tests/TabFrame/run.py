#!/usr/bin/env python3
"""Run selected real production methods against fake OS boundaries; never inject OS input."""
from pathlib import Path
import re,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
SELECTED={'Group/TabGroupController+GroupOperations.swift': ('Controller', ['positionPanel', 'applyLayout', 'parkOffscreen', 'selectTab', 'dissolve']), 'Group/TabGroupController+AXSync.swift': ('Controller', ['handleWindowNotification', 'beginTrackingActiveMove', 'tickActiveMove', 'endTrackingActiveMove']), 'Group/TabGroupController+PanelZOrder.swift': ('Controller', ['reassertPanelZOrder']), 'Group/TabGroupController+Workspace.swift': ('Controller', ['isGroupOnActiveSpace']), 'Accessibility/AXWindowEngine.swift': ('AXWindowEngine', ['setFrame']), 'UI/TabBarPanel.swift': ('Panel', ['applyLayout', 'cancelCollapseWatch'])}
def method(source,name):
 hit=re.search(r'(?m)^    (?:@objc )?(?:private )?func '+name+r'\(',source)
 assert hit,name
 opening=source.index('{',hit.end());depth=1
 for end in range(opening+1,len(source)):
  if source[end]=='{':depth+=1
  elif source[end]=='}':depth-=1
  if depth==0:return source[hit.start():end+1].replace('private func ','func ',1).replace('@objc ','',1)
 raise AssertionError(name)
with tempfile.TemporaryDirectory(prefix='tabbed-topic-') as tmp:
 out=Path(tmp);parts=['import Foundation\nimport CoreGraphics']
 for path,(owner,names) in SELECTED.items():
  source=(ROOT/'Sources'/path).read_text()
  parts += ['extension '+owner+' {'] + [method(source,n) for n in names] + ['}']
  if owner=='Controller' and path.endswith('+AXSync.swift') and 'func adoptTrackedFrame(' in source and 'adoptTrackedFrame' not in names:
   parts += ['extension Controller {',method(source,'adoptTrackedFrame'),'}']
  if owner=='Panel' and 'func collapseAfterSelection(' in source:
   extra=[n for n in ['setExpanded','collapseAfterSelection','beginCollapseWatch','tickCollapseWatch','cancelCollapseWatch'] if n not in names]
   parts += ['extension Panel {']+[method(source,n) for n in extra]+['}']
 (out/'ProductionMethods.swift').write_text('\n'.join(parts))
 (out/'main.swift').write_bytes((HERE/'main.swift').read_bytes())
 diagnostic=ROOT/'Sources/App/WindowDiagnostics.swift'
 cmd=['/usr/bin/xcrun','swiftc','-swift-version','5','-target','arm64-apple-macosx14.0','-sdk','/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk','-module-cache-path',str(out/'cache')]
 if diagnostic.is_file():cmd.append(str(diagnostic))
 subprocess.run(cmd+[str(HERE/'Support.swift'),str(out/'ProductionMethods.swift'),str(out/'main.swift'),'-o',str(out/'tests')],check=True)
 subprocess.run([str(out/'tests')],check=True)
