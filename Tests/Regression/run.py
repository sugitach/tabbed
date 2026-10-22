#!/usr/bin/env python3
"""Compile selected real production behavior with simulated AX/UI boundaries.

Optional termination callbacks are extracted only when production supplies them.
Without a callback, modeled normal termination performs no restoration. No test
substitute implements a missing production fix. No GUI or OS input is executed.
"""
from pathlib import Path
import datetime, hashlib, json, re, subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / 'Tests/Regression'
OUT = HERE / 'results' / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
OUT.mkdir(parents=True, exist_ok=False)
SDK = Path('/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk')
selected = {
    'Sources/Accessibility/AXWindowEngine.swift': ('AXWindowEngine', ['isAlive'], ['isKnownClosed']),
    'Sources/Group/TabGroupController.swift': ('TabGroupController', [], ['restoreWindowsForTermination']),
    'Sources/Group/TabGroupController+Workspace.swift': ('TabGroupController', ['pruneDeadWindows', 'applicationDidActivate', 'activeSpaceChanged'], []),
    'Sources/Group/TabGroupController+GroupOperations.swift': ('TabGroupController', ['remove', 'dissolve', 'untab'], []),
    'Sources/Group/TabGroupController+AXSync.swift': ('TabGroupController', ['handleWindowNotification'], []),
    'Sources/App/AppDelegate.swift': ('AppDelegate', [], ['applicationShouldTerminate', 'applicationWillTerminate']),
}

def method(source, name, optional=False):
    # Narrow extraction for these reviewed methods. Preserve exact method bodies.
    hits = list(re.finditer(r'(?m)^    (?:@objc )?func ' + re.escape(name) + r'\(', source))
    if not hits and optional:
        return None
    if len(hits) != 1:
        raise SystemExit('Expected exactly one production method: ' + name)
    start = hits[0].start()
    opening = source.index('{', hits[0].end())
    depth = 1
    for end in range(opening + 1, len(source)):
        if source[end] == '{': depth += 1
        elif source[end] == '}': depth -= 1
        if depth == 0: return source[start:end + 1].replace('@objc ', '', 1)
    raise SystemExit('Unbalanced method: ' + name)

inputs = sorted(p for p in (ROOT/'Sources').rglob('*') if p.is_file() and p.suffix in {'.swift', '.h'}) + [
    ROOT/'Tests/WindowRestorationTests.swift',
    HERE/'Support.swift', HERE/'main.swift', HERE/'run.py', ROOT/'Tests/test.sh',
]
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
hashes = {str(p.relative_to(ROOT)): digest(p) for p in inputs}
(OUT/'source-sha256.json').write_text(json.dumps(hashes, indent=2)+'\n')
for p in inputs:
    dest = OUT/'source'/p.relative_to(ROOT)
    dest.parent.mkdir(parents=True, exist_ok=True); dest.write_bytes(p.read_bytes())
SNAPSHOT = OUT/'source'
pieces = ['import Foundation\nimport CoreGraphics\n']
available = {}
for path, (owner, required, optional) in selected.items():
    text = (SNAPSHOT/path).read_text()
    pieces.append('// Exact production methods from ' + path + '\nextension ' + owner + ' {\n')
    for name in required + optional:
        body = method(text, name, name in optional)
        available[name] = body is not None
        if body is not None: pieces.append(body + '\n')
    pieces.append('}\n')
(OUT/'ProductionMethods.swift').write_text(''.join(pieces))
(OUT/'available-methods.json').write_text(json.dumps(available, indent=2)+'\n')
(OUT/'main.swift').write_bytes((SNAPSHOT/'Tests/Regression/main.swift').read_bytes())
flags = []
for name, flag in [('applicationShouldTerminate', 'HAS_SHOULD_TERMINATE'),
                   ('applicationWillTerminate', 'HAS_WILL_TERMINATE')]:
    if available[name]: flags += ['-D', flag]
commands = []
def run(label, argv):
    argv = list(map(str, argv)); commands.append({'label': label, 'argv': argv})
    (OUT/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
    with (OUT/(label+'.log')).open('w') as log:
        result = subprocess.run(argv, stdout=log, stderr=subprocess.STDOUT)
    print(label, result.returncode, flush=True)
    print((OUT/(label+'.log')).read_text(), end='', flush=True)
    return result.returncode

base = ['/usr/bin/xcrun', '--sdk', SDK, 'swiftc', '-swift-version', '5',
        '-target', 'arm64-apple-macosx14.0', '-sdk', SDK, '-module-cache-path', OUT/'module-cache']
production_policy = SNAPSHOT/'Sources/Group/WindowRestoration.swift'
policy_sources = [production_policy] if production_policy.is_file() else []
compile_code = run('compile', base + flags + policy_sources + [SNAPSHOT/'Tests/Regression/Support.swift',
                   OUT/'ProductionMethods.swift', OUT/'main.swift', '-o', OUT/'internal-tests'])
test_code = run('run', [OUT/'internal-tests']) if compile_code == 0 else None
# Check production even when a regression failed: a red test must not hide a build error.
typecheck_code = run('production-typecheck', base + ['-module-name', 'Tabbed',
    '-import-objc-header', SNAPSHOT/'Sources/Accessibility/Tabbed-Bridging-Header.h',
    '-typecheck'] + sorted((SNAPSHOT/'Sources').rglob('*.swift')))
# CLT has no XCTest framework. Typecheck the adapter with a declaration-only shim;
# never call this a full XCTest build/run. The actual regression assertions run above.
(OUT/'XCTestDeclarations.swift').write_text('class XCTestCase {}\nfunc XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "") {}\n')
(OUT/'XCTestAdapter.swift').write_text((SNAPSHOT/'Tests/WindowRestorationTests.swift').read_text().replace('import XCTest', ''))
adapter_code = run('xctest-adapter-typecheck', base + ['-typecheck', OUT/'XCTestDeclarations.swift', OUT/'XCTestAdapter.swift'])
assert hashes == {str(p.relative_to(ROOT)): digest(p) for p in inputs}, 'Inputs changed during test'
code = compile_code or typecheck_code or adapter_code or test_code or 0
(OUT/'result.json').write_text(json.dumps({'status': 'PASS' if code == 0 else 'FAIL',
    'exitCode': code, 'compileExitCode': compile_code, 'testExitCode': test_code,
    'productionTypecheckExitCode': typecheck_code, 'adapterTypecheckExitCode': adapter_code,
    'behaviorCases': 18, 'availableMethods': available,
    'scope': 'Actual selected methods and optional Quit hooks; simulated AX/UI and termination, not real OS E2E or XCTest runner',
    'sourceUnchanged': True}, indent=2)+'\n')
print('RESULT_DIR=' + str(OUT), flush=True)
raise SystemExit(code)
