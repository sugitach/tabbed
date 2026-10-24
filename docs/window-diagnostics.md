# Window diagnostics for tab switching

This diagnostic change records the boundaries needed to investigate unexpected resizing, visible inactive windows, stale tabs after closure, and movement toward the bottom-right corner. It does not fix those behaviors or establish that they are specific to Chrome Incognito. Recording is off at launch and starts only through the menu. The installed app and system permissions are not changed by preparing this build.

## Recording a controlled reproduction

1. Use the diagnostic build only after saving work and restoring or ungrouping existing test windows. Do not run two copies of Tabbed together. Ad-hoc signing may require manually registering this copy for Accessibility again.
2. Choose **Record Window Diagnostics**. The menu item is checked while recording. Start recording before creating the test group so that observer registration results are captured.
3. Use empty test windows: a normal Chrome window and an Incognito window, with one Chrome tab in each. Keep another empty normal window outside the group. Note which window is Incognito without putting page content into the log.
4. Form the group, switch its tabs once in each direction, and stop at the first unexpected resize, visible inactive window, or animation. If no earlier failure occurs, close the Incognito window's last Chrome tab and check whether its Tabbed tab disappears. Record which action produced the first symptom; do not repeat a failing operation.
5. Turn **Record Window Diagnostics** off. Choose **Show Window Diagnostic Logs…** and retain both JSONL files before starting a new session. Quit through the normal restoration flow; if restoration fails, use the existing recovery choices after checking window access.

The same check with two normal Chrome windows, and then with two windows from another app, is a subsequent comparison. It has not been performed by this change. No automated input, browser navigation, or live desktop reproduction is included in the non-GUI validation.

## What is captured

- Session UUID, monotonically increasing sequence, and process uptime for ordering events.
- Window IDs, PIDs, group IDs and membership, selected window, and the window that originally started move tracking.
- Requested geometry, group geometry before adoption, existing AX/WindowServer frame reads, and the WindowServer ID actually returned.
- Size/position write results, observer creation and registration results, notification categories, ignored-notification reasons, and closure checks.
- At activation boundaries only, extra read-only samples of identity, geometry, `AXMinimized`, and application-level `AXEnhancedUserInterface`.

There are no fields for window titles, URLs, page content, raw AX strings, or credentials. Unknown notification names become `other`. Geometry uses AppKit coordinates as `[x, y, width, height]`; omitted boolean or frame fields mean unavailable, not false or zero. `sizeStatus` and `positionStatus` preserve AX error numbers. A local AXValue encoding failure is separately marked `valueEncodingFailed` and normalized to AXError.failure.

The log directory is `~/Library/Logs/Tabbed/`. Two fixed files, `window-events.jsonl` and `window-events.previous.jsonl`, are retained, each up to 8 MiB. A new recording rotates the previous session; logs are not uploaded. New directories/files use permissions 0700/0600. Symlink or hard-link log targets are refused. IO/encoding failures stop recording and update the menu to show a log error. Stopping or normal termination closes the writer. Recording is not persisted across launches.

## Interpreting the evidence

Compare selection → layout → frame request/result → later notification/adoption → tracking samples. A tracker reading a different window from its origin is visible in `trackingWindowID` versus `windowID`; this instrumentation deliberately leaves the existing tracking behavior unchanged. A successful AX return alone does not prove that geometry has settled. AX/CG bounds are not required to match exactly: first establish window identity and changes over time.

For a stale tab, check registration results, notification receipt, ignored reasons, and later closure checks. Application notifications can refer to the application rather than a window, so a zero resolved ID there is not proof that a managed window closed. Unknown AX failures or absent CG metadata must not be treated as positive closure evidence.

The bottom-right destination is the existing parking policy. The app does not request minimization during tab selection. Read-only minimized/Enhanced UI samples can help distinguish actual minimization from animated movement, but no setting is toggled. Extra reads and synchronous log writes can affect timing; a symptom that disappears while recording is not proof of a fix.

## Validation scope

Run `bash Tests/test.sh internal` for existing regressions plus recorder tests. These exercise disabled recording, ordered JSON, error-code preservation, file permissions, byte limits/rotation, sample deduplication, unsafe paths, stop-on-failure, and normalization. They do not use the real Accessibility API or send desktop input. Full production typechecking and an optimized diagnostic build are separate checks. Real Chrome/Incognito reproduction and native menu behavior remain unverified.

Changes remain uncommitted while the reported behaviors are unresolved. No release, tag, push, VM test, or installed-app replacement is part of diagnostic preparation.
