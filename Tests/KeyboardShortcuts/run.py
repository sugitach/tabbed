#!/usr/bin/env python3
"""Real hotkey monitor + focused-group dispatch with fake OS registration.
No native hotkeys, event monitors, synthetic input, or GUI are started.
"""
from pathlib import Path
import re, subprocess, tempfile
ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent

def method(source, name):
    hit = re.search(r'(?m)^    (?:private )?func '+name+r'\(', source)
    assert hit, name
    opening = source.index('{', hit.end()); depth = 1
    for end in range(opening+1, len(source)):
        depth += (source[end]=='{')-(source[end]=='}')
        if depth == 0: return source[hit.start():end+1]
    raise AssertionError(name)

monitor = ROOT/'Sources/Input/KeyboardShortcutMonitor.swift'
assert 'CGEvent.tap' not in monitor.read_text()
with tempfile.TemporaryDirectory(prefix='tabbed-hotkeys-') as directory:
    out = Path(directory)
    panel = (ROOT/'Sources/Group/TabGroupController+PanelZOrder.swift').read_text()
    (out/'FocusedGroup.swift').write_text('import AppKit\nextension TabGroupController {\n'+method(panel,'effectiveFocusedWindowID')+'\n'+method(panel,'frontmostGroup')+'\n}')
    subprocess.run(['/usr/bin/xcrun','swiftc','-swift-version','5','-module-cache-path',str(out/'cache'),
        str(ROOT/'Sources/Config/TOML.swift'), str(ROOT/'Sources/Config/TabbedConfig.swift'),
        str(monitor), str(ROOT/'Sources/Group/TabGroupController+Keyboard.swift'),
        str(out/'FocusedGroup.swift'), str(HERE/'Support.swift'), str(HERE/'main.swift'),
        '-o',str(out/'tests')], check=True)
    subprocess.run([str(out/'tests')], check=True)
