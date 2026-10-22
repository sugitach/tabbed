#!/bin/bash
# Explicit dispatch only: the default is non-GUI internal regression.
set -euo pipefail
TEST_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && /bin/pwd -P)
case "${1:-internal}" in
internal)
    [ "$#" -le 1 ] || exit 64
    exec /usr/bin/python3 "$TEST_ROOT/Regression/run.py"
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
