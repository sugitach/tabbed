#!/usr/bin/env python3
"""Sign copies, package and verify an ISO without launching or mounting anything."""
from pathlib import Path
import hashlib, json, os, stat, subprocess, sys

ROOT = Path(__file__).resolve().parents[1]
if len(sys.argv) != 2: raise SystemExit('usage: python3 scripts/package.py exports/<build timestamp>')
OUT = Path(sys.argv[1]).resolve()
if OUT.parent != (ROOT/'exports').resolve(): raise SystemExit('Not a local build output')
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def inventory(folder):
    result = {}
    for p in sorted(folder.rglob('*')):
        if p.is_symlink(): raise SystemExit('Unexpected build/snapshot symlink')
        if p.is_file(): result[str(p.relative_to(folder))] = {'sha256': digest(p), 'mode': p.stat().st_mode & 0o777}
    return result
success = json.loads((OUT/'build-success.json').read_text())
if success.get('status') != 'PASS' or success.get('schema') != 1:
    raise SystemExit('No successful build/test record')
if not success.get('build') or success['build'] != inventory(OUT/'build'):
    raise SystemExit('Build artifact inventory/hash/mode changed')
if not success.get('source') or success['source'] != inventory(OUT/'source'):
    raise SystemExit('Build source snapshot changed')
if success['sourceSHA256'] != json.loads((OUT/'source-sha256.json').read_text()):
    raise SystemExit('Source manifest changed')
if success['sourceSHA256'] != {p: v['sha256'] for p, v in success['source'].items()}:
    raise SystemExit('Source hash manifests disagree')
SNAPSHOT = OUT/'source'
if (OUT/'signed').exists() or (OUT/'payload').exists(): raise SystemExit('Packaging already attempted; do not overwrite')
commands = []
def run(label, argv):
    commands.append({'label': label, 'argv': list(map(str, argv))})
    (OUT/'packaging-commands.json').write_text(json.dumps(commands, indent=2))
    with (OUT/(label+'.log')).open('w') as f:
        result = subprocess.run(list(map(str, argv)), stdout=f, stderr=subprocess.STDOUT)
    print(label, result.returncode, flush=True)
    if result.returncode: raise SystemExit('Stopped at '+label+'; see log. Do not overwrite/retry in same output.')
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()

name = 'Tabbed Guest Harness.app'
app = OUT/'signed'/name
fixture = app/'Contents/Helpers/Tabbed Guest Fixture.app'
run('copy-driver', ['/usr/bin/ditto', OUT/'build'/name, app])
run('copy-fixture', ['/usr/bin/ditto', OUT/'build/Tabbed Guest Fixture.app', fixture])
run('sign-fixture', ['/usr/bin/codesign', '--sign', '-', '--options', 'runtime', '--timestamp=none', fixture])
(app/'Contents/Resources/fixture.sha256').write_text(digest(fixture/'Contents/MacOS/Fixture')+'\n')
for rel in ['README.md', 'docs/test-scope.md', 'docs/review.md']:
    (app/'Contents/Resources'/Path(rel).name).write_bytes((SNAPSHOT/rel).read_bytes())
run('sign-driver', ['/usr/bin/codesign', '--sign', '-', '--options', 'runtime', '--timestamp=none', app])
for label, path in [('fixture', fixture), ('driver', app)]:
    run('verify-'+label, ['/usr/bin/codesign', '--verify', '--strict', '--verbose=2', path])
    run('display-'+label, ['/usr/bin/codesign', '-dvv', path])
target = OUT/'signed/Tabbed Quit Fix.app'
run('copy-target', ['/usr/bin/ditto', OUT/'build/Tabbed Quit Fix.app', target])
run('verify-target', ['/usr/bin/codesign','--verify','--strict','--verbose=2',target])
assert digest(target/'Contents/MacOS/Tabbed') == success['targetSHA256']
assert (app/'Contents/Resources/target.sha256').read_text().strip() == success['targetSHA256']
payload = OUT/'payload'; payload.mkdir()
bundle_sha = ''.join(digest(p)+'  '+str(p.relative_to(app.parent))+'\n' for p in sorted(app.rglob('*')) if p.is_file())
(payload/'BUNDLE.SHA').write_text(bundle_sha)
run('zip-app', ['/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, payload/'HARNESS.ZIP'])
(payload/'TARGET.SHA').write_text(''.join(digest(p)+'  '+str(p.relative_to(target.parent))+'\n' for p in sorted(target.rglob('*')) if p.is_file()))
run('zip-target', ['/usr/bin/ditto','-c','-k','--sequesterRsrc','--keepParent',target,payload/'TABBED.ZIP'])
run('zip-source', ['/usr/bin/ditto', '-c', '-k', '--keepParent', OUT/'source', payload/'SOURCE.ZIP'])
(payload/'README.TXT').write_bytes((SNAPSHOT/'README.md').read_bytes())
(payload/'TEST.SH').write_bytes((SNAPSHOT/'test.sh').read_bytes())
(payload/'SHA256SUMS').write_text(''.join(digest(payload/n)+'  '+n+'\n' for n in ['HARNESS.ZIP','SOURCE.ZIP','TABBED.ZIP','BUNDLE.SHA','TARGET.SHA','README.TXT','TEST.SH']))
media = OUT/'Tabbed-Guest-Harness.iso'
run('iso', ['/usr/bin/hdiutil', 'makehybrid', '-hfs', '-iso', '-default-volume-name', 'Tabbed-Guest-Harness', '-o', media, payload])
roundtrip = OUT/'roundtrip'; roundtrip.mkdir()
for p in sorted(payload.iterdir()):
    data = subprocess.check_output(['/usr/bin/tar', '-xOf', str(media), p.name])
    assert data == p.read_bytes(), 'ISO mismatch: '+p.name
    (roundtrip/p.name).write_bytes(data)
run('unzip-app', ['/usr/bin/ditto','-x','-k',roundtrip/'HARNESS.ZIP',roundtrip/'extracted'])
restored = roundtrip/'extracted'/name
def tree(p):
    return {str(q.relative_to(p)): (q.is_dir(), stat.S_IMODE(q.stat().st_mode), digest(q) if q.is_file() else None) for q in p.rglob('*')}
assert tree(app) == tree(restored), 'App path/content/mode roundtrip mismatch'
run('roundtrip-driver', ['/usr/bin/codesign','--verify','--strict','--verbose=2',restored])
run('roundtrip-fixture', ['/usr/bin/codesign','--verify','--strict','--verbose=2',restored/'Contents/Helpers/Tabbed Guest Fixture.app'])
run('unzip-target', ['/usr/bin/ditto','-x','-k',roundtrip/'TABBED.ZIP',roundtrip/'target-extracted'])
restoredTarget = roundtrip/'target-extracted/Tabbed Quit Fix.app'
assert tree(target) == tree(restoredTarget), 'Target path/content/mode roundtrip mismatch'
run('roundtrip-target', ['/usr/bin/codesign','--verify','--strict','--verbose=2',restoredTarget])
run('unzip-source', ['/usr/bin/ditto','-x','-k',roundtrip/'SOURCE.ZIP',roundtrip/'source-extracted'])
assert tree(OUT/'source') == tree(roundtrip/'source-extracted/source'), 'Source roundtrip mismatch'
media.chmod(0o444)
hashes = {str(p.relative_to(OUT)): digest(p) for p in [media, payload/'HARNESS.ZIP', payload/'SOURCE.ZIP', payload/'TABBED.ZIP', target/'Contents/MacOS/Tabbed', app/'Contents/MacOS/Harness', fixture/'Contents/MacOS/Fixture']}
(OUT/'artifact-sha256.json').write_text(json.dumps(hashes,indent=2)+'\n')
(OUT/'media-sha256.txt').write_text(digest(media)+'  '+media.name+'\n')
(OUT/'roundtrip-result.txt').write_text('Actual ISO -> ZIP -> ditto: all payload bytes and app/source paths, file bytes, POSIX modes match. All three strict signatures reverified. No app launched, no mount or VM tested.\n')
print(json.dumps(hashes, indent=2))
