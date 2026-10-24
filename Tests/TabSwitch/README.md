# Tab switching regression checks

`python3 Tests/TabSwitch/run.py` extracts the actual production layout, selection,
tracking, panel-ordering, and AX frame-setting methods into a deterministic test.
It also runs through `bash Tests/test.sh internal`.

The checks cover cancelling tracking at tab selection, rejecting a changed tracked
window identity, retaining user resizing, ignoring unrelated notifications,
anchoring the panel after showing/activating, background-group anchoring, and
moving a parked window before resizing it. Source snapshots, hashes, compiler
commands, and output are retained under the ignored `Tests/Regression/results/`.

AX, WindowServer, panels, and timers are simulated. Passing does not establish
real macOS/Chrome behavior. A retained failure characterization explicitly shows
that a persistently rejected resize can still be adopted by a delayed notification.
The position-size-position change therefore requires real multi-display testing.
