# Compact hover regression checks

Run `python3 StandaloneTests/CompactHover/run.py` from the repository root.
An optional source-root argument checks these tests against an integration tree.

The runner compiles actual production panel methods with a deterministic clock
and simulated UI boundaries. It checks the three-second delay, cancellation on
exit/hide/mode change, direct-selection continuity, selection collapse, pointer
exit rearming, stale tracking, and legacy immediate expansion. Production source
hashes and compiler/test output are recorded in a temporary folder.

This suite replaces the older `Tests/Compact` fixture. Keep standalone `main.swift`
entry points outside `Tests`, which is discovered by the Xcode unit-test target.

These checks do not launch Tabbed or synthesize input. Actual SwiftUI hit testing,
animation, tracking delivery, and macOS panel ordering require manual validation:

1. Enable Always Compact, group two windows, and click each compact icon. Verify
   that the selected window changes while the strip remains compact.
2. Hover continuously for over three seconds. Verify that the full bar appears.
3. Leave before three seconds and return. Verify that a fresh delay is required.
4. Change modes or hide/move the panel during the delay. Verify no late expansion.
5. Disable Always Compact and move a group against the top edge. Verify that its
   space-constrained compact strip still expands immediately on hover.
