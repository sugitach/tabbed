#!/bin/bash
# One entry point; host build and guest execution remain explicitly separate.
set -euo pipefail
umask 077
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
INSTALL="$HOME/Tabbed-Guest-Harness-Test"
APP="$INSTALL/Tabbed Guest Harness.app"
TARGET_INSTALL="$HOME/Tabbed-Quit-Fix-Test"
TARGET_APP="$TARGET_INSTALL/Tabbed Quit Fix.app"
RUNS="$HOME/Library/Application Support/TabbedGuestHarness"

usage() {
    cat <<'EOF'
Host (never launches an app):
  ./test.sh host                   # build, pure tests, sign copies, package ISO
  ./test.sh build                  # build, pure tests, sign production copy for hash pin
  ./test.sh package exports/<UTC>  # package an unchanged build, no overwrite
Guest, after manual VM/login/permission setup and artifact approval:
  bash TEST.SH prepare /Volumes/Tabbed-Guest-Harness
  bash TEST.SH prepare-target /Volumes/Tabbed-Guest-Harness # no launch, no overwrite
  bash TEST.SH verify
  bash TEST.SH open                # open verified app, manual start only
  bash TEST.SH run e2e --confirm-isolated-guest # group / drag-out / regroup / normal Quit
  bash TEST.SH run smoke --confirm-isolated-guest
  bash TEST.SH run plain-click --confirm-isolated-guest
  bash TEST.SH run command-click --confirm-isolated-guest
  bash TEST.SH run command-drag --confirm-isolated-guest
  bash TEST.SH run diagnose-point --confirm-isolated-guest # no input, observation only
  bash TEST.SH results <run-UUID>
No account, password, TCC, lock, sharing, network or VM setup automation.
EOF
}
die() { printf '%s\n' "STOP: $*" >&2; exit 1; }
media_is_read_only() { [ "$1" = false ] && [ "$2" = false ]; }
guest_only() {
    [ "$(/usr/bin/uname -s)" = Darwin ] || die 'macOS guest required'
    [ "$(/usr/sbin/sysctl -n kern.hv_vmm_present 2>/dev/null || true)" = 1 ] || die 'VM flag is not 1; no override'
    [ "$(/usr/bin/id -u)" != 0 ] || die 'Use the dedicated guest user, not root'
}
verify_app() {
    [ -d "$INSTALL" ] && [ ! -L "$INSTALL" ] || die 'Fixed installation directory missing or symlinked'
    [ -f "$INSTALL/BUNDLE.SHA" ] && [ ! -L "$INSTALL/BUNDLE.SHA" ] || die 'Bundle manifest missing / symlinked'
    (cd "$INSTALL" && /usr/bin/shasum -a 256 -c BUNDLE.SHA)
    /usr/bin/codesign --verify --strict --verbose=2 "$APP/Contents/Helpers/Tabbed Guest Fixture.app"
    /usr/bin/codesign --verify --strict --verbose=2 "$APP"
}
verify_target() {
    [ -d "$TARGET_INSTALL" ] && [ ! -L "$TARGET_INSTALL" ] || die 'Fixed target directory missing / symlinked'
    [ -f "$TARGET_INSTALL/TARGET.SHA" ] && [ ! -L "$TARGET_INSTALL/TARGET.SHA" ] || die 'Target manifest missing / symlinked'
    (cd "$TARGET_INSTALL" && /usr/bin/shasum -a 256 -c TARGET.SHA)
    /usr/bin/codesign --verify --strict --verbose=2 "$TARGET_APP"
    identity=$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$TARGET_APP/Contents/Info.plist")
    [ "$identity" = dev.local.TabbedReviewed ] || die 'Target bundle identifier mismatch'
    IFS= read -r pin < "$APP/Contents/Resources/target.sha256"
    [[ "$pin" =~ ^[a-f0-9]{64}$ ]] || die 'Invalid embedded target hash'
    actual=$(/usr/bin/shasum -a 256 "$TARGET_APP/Contents/MacOS/Tabbed")
    [ "${actual%% *}" = "$pin" ] || die 'Pinned production executable mismatch'
}
valid_uuid() { [[ "$1" =~ ^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$ ]]; }
command=${1:-help}
case "$command" in
help|-h|--help) usage ;;
build) [ "$#" = 1 ] || die 'Unexpected arguments'; exec /usr/bin/python3 "$ROOT/scripts/build.py" ;;
package)
    [ "$#" = 2 ] || die 'Specify exactly one build directory'
    case "$2" in /*) output="$2" ;; *) output="$ROOT/$2" ;; esac
    exec /usr/bin/python3 "$ROOT/scripts/package.py" "$output"
    ;;
host)
    [ "$#" = 1 ] || die 'Unexpected arguments'
    mkdir -p "$ROOT/.local"
    pathfile=$(/usr/bin/mktemp "$ROOT/.local/build-path.XXXXXX")
    trap '/bin/rm -f "$pathfile"' EXIT
    /usr/bin/python3 "$ROOT/scripts/build.py" --output-path-file "$pathfile"
    IFS= read -r output < "$pathfile"
    /usr/bin/python3 "$ROOT/scripts/package.py" "$output"
    ;;
prepare|prepare-target)
    [ "$#" = 2 ] || die 'Specify the mounted read-only media directory'
    guest_only
    media=$(CDPATH= cd -- "$2" && /bin/pwd -P)
    case "$media" in /Volumes/*) ;; *) die 'Use a mounted volume under /Volumes' ;; esac
    info=$(/usr/bin/mktemp /tmp/tabbed-media.XXXXXX)
    trap '/bin/rm -f "$info"' EXIT
    /usr/sbin/diskutil info -plist "$media" > "$info"
    writablevolume=$(/usr/bin/plutil -extract WritableVolume raw -o - "$info" 2>/dev/null || true)
    writablemedia=$(/usr/bin/plutil -extract WritableMedia raw -o - "$info" 2>/dev/null || true)
    media_is_read_only "$writablevolume" "$writablemedia" || die 'Media and volume must both be explicitly non-writable'
    (cd "$media" && /usr/bin/shasum -a 256 -c SHA256SUMS)
    if [ "$command" = prepare-target ]; then
        verify_app
        [ ! -e "$TARGET_INSTALL" ] && [ ! -L "$TARGET_INSTALL" ] || die 'Target installation exists; preserve/archive it explicitly first'
        mkdir "$TARGET_INSTALL"
        /usr/bin/ditto -x -k "$media/TABBED.ZIP" "$TARGET_INSTALL"
        /bin/cp "$media/TARGET.SHA" "$TARGET_INSTALL/TARGET.SHA"
        verify_target
    else
        [ ! -e "$INSTALL" ] && [ ! -L "$INSTALL" ] || die 'Installation exists; do not overwrite. Inspect/archive it manually.'
        mkdir "$INSTALL"
        /usr/bin/ditto -x -k "$media/HARNESS.ZIP" "$INSTALL"
        /bin/cp "$media/BUNDLE.SHA" "$INSTALL/BUNDLE.SHA"
        verify_app
    fi
    printf '%s\n' 'VERIFIED_INSTALLATION_ONLY — no app launched / permissions changed'
    ;;
verify) [ "$#" = 1 ] || die 'Unexpected arguments'; guest_only; verify_app ;;
open)
    [ "$#" = 1 ] || die 'Unexpected arguments'; guest_only; verify_app
    /usr/bin/open -n "$APP"
    printf '%s\n' 'AWAITING_MANUAL_START — no test result is claimed'
    ;;
run)
    [ "$#" = 3 ] && [ "$3" = --confirm-isolated-guest ] || die 'Explicit scenario and isolated-guest confirmation required'
    case "$2" in
        e2e) expectedmode=E2E_GROUP_UNGROUP_QUIT ;;
        smoke) expectedmode=TRANSPORT_SMOKE ;;
        plain-click|command-click|command-drag) expectedmode="SESSION_INPUT_PROBE_$2" ;;
        diagnose-point) expectedmode=POINT_DIAGNOSTIC_NO_INPUT ;;
        *) die 'Unknown scenario; no app launched' ;;
    esac
    guest_only; verify_app
    if [ "$2" = e2e ]; then verify_target; fi
    runid=$(/usr/bin/uuidgen)
    valid_uuid "$runid" || die 'Unexpected UUID format'
    result="$RUNS/$runid/result.json"
    [ ! -e "$RUNS/$runid" ] && [ ! -L "$RUNS/$runid" ] || die 'Run ID already exists'
    printf 'Requested %s run: %s\n' "$2" "$runid"
    printf '%s\n' 'This requires a v0.2+ app. v0.1 opens only its manual UI and cannot pass this script.'
    /usr/bin/open -n "$APP" --args --scenario "$2" --execute --confirm-isolated-guest --run-id "$runid"
    for ((i=0; i<90; i++)); do
        if [ -f "$result" ] && [ ! -L "$result" ]; then
            found=$(/usr/bin/plutil -extract runID raw -o - "$result")
            mode=$(/usr/bin/plutil -extract mode raw -o - "$result")
            status=$(/usr/bin/plutil -extract result raw -o - "$result")
            [ "$found" = "$runid" ] && [ "$mode" = "$expectedmode" ] || die 'Result identity / scenario mismatch'
            /bin/cat "$result"
            if [ "$2" = diagnose-point ]; then
                [ "$status" = DIAGNOSTIC_ONLY_NO_INPUT ] || exit 1
                /bin/cat "$RUNS/$runid/point-diagnostic.json"
                printf '\nDIAGNOSTIC ONLY: no input delivery or Tabbed success claimed. Logs: %s\n' "$RUNS/$runid"
                exit 0
            fi
            [ "$status" = PASS ] || exit 1
            if [ "$2" = e2e ]; then
                # Only observe the recorded processes; never kill or repair on timeout.
                for field in driverPID fixturePID targetPID; do
                    pid=$(/usr/bin/plutil -extract "$field" raw -o - "$result")
                    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || die 'Invalid cleanup PID in E2E result'
                    for ((j=0; j<6; j++)); do
                        if ! /bin/ps -p "$pid" -o pid= >/dev/null; then break; fi
                        /bin/sleep 1
                    done
                    if /bin/ps -p "$pid" -o pid= >/dev/null; then die "E2E process remains: $field; NOT PASS"; fi
                done
            fi
            printf '\nPASS: this scenario/run only. Logs: %s\n' "$RUNS/$runid"
            exit 0
        fi
        /bin/sleep 1
    done
    die "No matching result within 90 seconds: NOT PASS. Inspect UI/logs at $RUNS/$runid; no kill/retry was performed."
    ;;
results)
    [ "$#" = 2 ] || die 'Specify one run UUID'; guest_only; valid_uuid "$2" || die 'Invalid run UUID'
    [ -f "$RUNS/$2/result.json" ] && [ ! -L "$RUNS/$2/result.json" ] || die 'No result for that run'
    /bin/cat "$RUNS/$2/result.json"
    ;;
*) usage >&2; exit 64 ;;
esac
