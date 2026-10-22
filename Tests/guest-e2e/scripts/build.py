#!/usr/bin/env python3
"""Host-only build/pure tests. App bundles are NEVER launched."""
from pathlib import Path
import argparse, datetime, hashlib, json, plistlib, subprocess

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--output-path-file', type=Path)
arguments = parser.parse_args()
SDK = Path('/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk')
OUT = ROOT / 'exports' / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
OUT.mkdir(parents=True, exist_ok=False)
commands = []
def run(label, argv):
    commands.append({'label': label, 'argv': list(map(str, argv))})
    (OUT/'commands.json').write_text(json.dumps(commands, indent=2))
    with (OUT/(label+'.log')).open('w') as log:
        result = subprocess.run(list(map(str, argv)), stdout=log, stderr=subprocess.STDOUT)
    print(label, result.returncode, flush=True)
    if result.returncode:
        print((OUT/(label+'.log')).read_text())
        raise SystemExit('Stopped; evidence retained at '+str(OUT))
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def inventory(folder):
    result = {}
    for p in sorted(folder.rglob('*')):
        if p.is_symlink(): raise SystemExit('Unexpected build/snapshot symlink')
        if p.is_file(): result[str(p.relative_to(folder))] = {'sha256': digest(p), 'mode': p.stat().st_mode & 0o777}
    return result
inputs = {str(p.relative_to(ROOT)): p for folder in ['Sources','Tests','scripts','docs']
          for p in (ROOT/folder).rglob('*') if p.is_file() and p.suffix in {'.swift','.py','.md','.sh'}}
for name in ['README.md','test.sh']: inputs[name] = ROOT/name
for p in (REPO/'Sources').rglob('*'):
    if p.is_file(): inputs['target-source/'+str(p.relative_to(REPO))] = p
for name in ['Resources/Info.plist','LICENSE']:
    inputs['target-source/'+name] = REPO/name
original = {name: digest(p) for name,p in inputs.items()}
(OUT/'original-input-sha256.json').write_text(json.dumps(original,sort_keys=True,indent=2)+'\n')
snapshot = OUT/'source'
for name,p in inputs.items():
    q=snapshot/name; q.parent.mkdir(parents=True,exist_ok=True); q.write_bytes(p.read_bytes())
base = ['/usr/bin/xcrun','--sdk',SDK,'swiftc','-swift-version','5','-target','arm64-apple-macosx14.0',
        '-sdk',SDK,'-module-cache-path',OUT/'module-cache']
# Compile the untouched production snapshot, sign a separate copy, then embed
# the exact signed executable hash into BOTH harness apps and their source ZIP.
targetfiles=sorted((snapshot/'target-source/Sources').rglob('*.swift'))
targetbase=base+['-module-name','Tabbed','-import-objc-header',snapshot/'target-source/Sources/Accessibility/Tabbed-Bridging-Header.h']
unsigned=OUT/'target-unsigned/Tabbed Quit Fix.app'
(unsigned/'Contents/MacOS').mkdir(parents=True)
(unsigned/'Contents/Resources').mkdir()
run('target-typecheck',targetbase+['-typecheck']+targetfiles)
run('target-build',targetbase+['-O','-o',unsigned/'Contents/MacOS/Tabbed']+targetfiles)
info=plistlib.loads((snapshot/'target-source/Resources/Info.plist').read_bytes())
info.update(CFBundleExecutable='Tabbed',CFBundleIdentifier='dev.local.TabbedReviewed',CFBundleName='Tabbed Quit Fix',
            CFBundleShortVersionString='0.1.2',CFBundleVersion='3',LSMinimumSystemVersion='14.0')
(unsigned/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
(unsigned/'Contents/Resources/LICENSE').write_bytes((snapshot/'target-source/LICENSE').read_bytes())
target=OUT/'build/Tabbed Quit Fix.app'
run('target-copy',['/usr/bin/ditto',unsigned,target])
run('target-sign',['/usr/bin/codesign','--sign','-','--identifier','dev.local.TabbedReviewed','--options','runtime','--timestamp=none',target])
run('target-verify',['/usr/bin/codesign','--verify','--strict','--verbose=2',target])
run('target-signature',['/usr/bin/codesign','-dvv',target])
run('target-load-commands',['/usr/bin/otool','-l',target/'Contents/MacOS/Tabbed'])
pin=digest(target/'Contents/MacOS/Tabbed')
generated=snapshot/'Generated/PinnedTarget.swift'; generated.parent.mkdir()
generated.write_text('// Generated from the strict-verified signed production copy; see commands.json.\n'
                     'enum PinnedTarget { static let sha256 = "'+pin+'" }\n')
shared=sorted((snapshot/'Sources/Shared').glob('*.swift'))+[generated]
apps=[('Tabbed Guest Fixture.app','Fixture','dev.local.TabbedGuestFixture','Fixture'),
      ('Tabbed Guest Harness.app','Harness','dev.local.TabbedGuestHarness','Driver')]
for name,exe,bundleid,folder in apps:
    files=shared+sorted((snapshot/'Sources'/folder).glob('*.swift'))
    app=OUT/'build'/name
    (app/'Contents/MacOS').mkdir(parents=True); (app/'Contents/Resources').mkdir()
    run(exe+'-typecheck',base+['-typecheck']+files)
    run(exe+'-build',base+['-O','-o',app/'Contents/MacOS'/exe]+files)
    info=dict(CFBundleExecutable=exe,CFBundleIdentifier=bundleid,CFBundleName=name.removesuffix('.app'),
              CFBundlePackageType='APPL',CFBundleShortVersionString='0.11.0',CFBundleVersion='11',
              LSMinimumSystemVersion='14.0',NSHighResolutionCapable=True,NSPrincipalClass='NSApplication')
    (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    (app/'Contents/Resources/target.sha256').write_text(pin+'\n')
    run(exe+'-load-commands',['/usr/bin/otool','-l',app/'Contents/MacOS'/exe])
    run(exe+'-architecture',['/usr/bin/file',app/'Contents/MacOS'/exe])
# Only this Shared-only executable is run on the host. No AppKit/AX/event code.
run('policy-build',base+['-O','-o',OUT/'policy-tests']+shared+[snapshot/'Tests/main.swift'])
run('policy-run',[OUT/'policy-tests'])
run('media-policy',['/bin/bash',snapshot/'Tests/media-policy.sh',snapshot/'test.sh'])
assert original=={name:digest(p) for name,p in inputs.items()},'Original inputs changed during build'
assert original=={name:digest(snapshot/name) for name in inputs},'Original snapshot changed during build'
hashes={p:v['sha256'] for p,v in inventory(snapshot).items()}
(OUT/'source-sha256.json').write_text(json.dumps(hashes,sort_keys=True,indent=2)+'\n')
(OUT/'source-verification.txt').write_text('All original production/harness inputs and snapshots unchanged. Generated/PinnedTarget.swift is the sole generated source. App bundles never launched.\n')
(OUT/'build-success.json').write_text(json.dumps({'status':'PASS','schema':1,'build':inventory(OUT/'build'),
    'source':inventory(snapshot),'sourceSHA256':hashes,'targetSHA256':pin},indent=2)+'\n')
print('BUILD_OUTPUT='+str(OUT))
if arguments.output_path_file: arguments.output_path_file.write_text(str(OUT)+'\n')
