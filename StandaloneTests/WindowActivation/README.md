# External window activation regression checks

Run `python3 StandaloneTests/WindowActivation/run.py` from the repository root.
An optional source-root argument checks these tests against an integration tree.

The runner compiles the actual production focus reconciliation and panel-sync
methods with simulated workspace, AX, and selection/layout boundaries. It checks
same-app and cross-app activation, idempotence, stale/reentrant notifications,
unrelated windows, drag/layout/termination guards, and active-Space filtering.
It records production source hashes and compiler/test output in a temporary folder.

These checks do not launch Tabbed or synthesize input. They do not verify actual
macOS AX delivery, window restoration, panel stacking, or SwiftUI interactions.
Manually group two windows, activate the hidden member from its application's
Window menu, and repeat with windows from different apps. Confirm the selected
tab and visible window change while preserving the group's frame.
