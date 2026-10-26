#!/usr/bin/env python3
"""Exercise actual compact-hover methods with simulated clock/UI boundaries.

No real windows, input synthesis, or accessibility permission changes are used.
Pass a source root to test the same patch integrated with later feature branches.
"""
from pathlib import Path
import hashlib
import json
import os
import platform
import re
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else HERE.parents[1]
OUT = Path(tempfile.mkdtemp(prefix='tabbed-compact-'))
methods = {'Sources/UI/TabBarPanel.swift': ('TabBarPanel', ['applyLayout', 'handleHover', 'expandAfterHoverDelay', 'cancelPendingExpansion', 'setExpanded', 'collapseAfterSelection', 'beginCollapseWatch', 'tickCollapseWatch', 'cancelCollapseWatch', 'hide'])}

def extract(source, name):
    match = re.search(r'(?m)^    (?:private )?(?:static )?func ' + name + r'\(', source)
    if match is None:
        raise RuntimeError('Missing production method: ' + name)
    opening = source.index('{', match.end())
    depth = 1
    for end in range(opening + 1, len(source)):
        if source[end] == '{': depth += 1
        elif source[end] == '}': depth -= 1
        if depth == 0: return source[match.start():end+1]
    raise RuntimeError('Unbalanced method: ' + name)

pieces = ['import Foundation\nimport CoreGraphics\n']
hashes = {}
for path, (owner, names) in methods.items():
    data = (ROOT/path).read_bytes()
    hashes[path] = hashlib.sha256(data).hexdigest()
    pieces += ['extension ' + owner + ' {\n']
    pieces += [extract(data.decode(), name).replace('private func ', 'func ') + '\n' for name in names]
    pieces += ['}\n']
(OUT/'ProductionMethods.swift').write_text(''.join(pieces))
for name in ['Support.swift', 'main.swift']:
    (OUT/name).write_bytes((HERE/name).read_bytes())
flags = []
sdk = os.environ.get('SDKROOT') or subprocess.check_output(
    ['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
compile_cmd = ['xcrun', 'swiftc', '-swift-version', '5', '-sdk', sdk,
               '-module-cache-path', str(OUT/'module-cache'),
               '-target', platform.machine() + '-apple-macosx14.0'] + flags + [str(OUT/name) for name in
               ['Support.swift', 'ProductionMethods.swift', 'main.swift']] + ['-o', str(OUT/'tests')]
result = subprocess.run(compile_cmd, capture_output=True, text=True)
(OUT/'compile.log').write_text(result.stdout + result.stderr)
print(result.stdout + result.stderr, end='')
code = result.returncode
if code == 0:
    result = subprocess.run([OUT/'tests'], capture_output=True, text=True)
    (OUT/'run.log').write_text(result.stdout + result.stderr)
    print(result.stdout + result.stderr, end='')
    code = result.returncode
assert all(hashlib.sha256((ROOT/path).read_bytes()).hexdigest() == digest for path, digest in hashes.items())
(OUT/'result.json').write_text(json.dumps({'exitCode': code, 'sourceRoot': str(ROOT),
    'productionSHA256': hashes, 'scope': 'Actual production methods; simulated boundaries; no real OS/UI integration test'}, indent=2)+'\n')
print('RESULT_DIR=' + str(OUT))
raise SystemExit(code)
