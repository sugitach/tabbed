#!/bin/bash
set -euo pipefail
TEST_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && /bin/pwd -P)
case "${1:-internal}" in
internal)
 [ "$#" -le 1 ] || exit 64
 for suite in WindowDiagnostics KeyboardShortcuts DragGesture Regression TabSwitch Compact TabFrame GroupTransfer PanelVisibility MovementVisibility; do
  if [ -f "$TEST_ROOT/$suite/run.py" ]; then /usr/bin/python3 "$TEST_ROOT/$suite/run.py"; fi
 done
 ;;
*) exit 64 ;;
esac
