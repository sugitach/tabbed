#!/bin/bash
# Explicit dispatch only: the default is non-GUI internal regression.
set -euo pipefail
TEST_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && /bin/pwd -P)
case "${1:-internal}" in
internal)
    [ "$#" -le 1 ] || exit 64
    /usr/bin/python3 "$TEST_ROOT/KeyboardShortcuts/run.py"
    /usr/bin/python3 "$TEST_ROOT/DragGesture/run.py"
    /usr/bin/python3 "$TEST_ROOT/Regression/run.py"
    for suite in WindowDiagnostics TabFrame GroupTransfer PanelVisibility MovementVisibility RestorationPolicy; do
        /usr/bin/python3 "$TEST_ROOT/$suite/run.py"
    done
    /usr/bin/python3 "$TEST_ROOT/TabSwitch/run.py"
    for suite in WindowActivation CompactHover WindowLifecycle GroupSession; do
        /usr/bin/python3 "$TEST_ROOT/../StandaloneTests/$suite/run.py"
    done
    ;;
guest)
    shift
    exec /bin/bash "$TEST_ROOT/guest-e2e/test.sh" "$@"
    ;;
help|-h|--help)
    printf '%s\n' 'bash Tests/test.sh [internal]  # non-GUI regression; no app or VM' \
        'bash Tests/test.sh guest help # explicit existing guest/build/package commands' \
        'Stages 2/3 require approved artifacts and guest setup; neither runs by default.'
    ;;
*) exit 64 ;;
esac
