# Group session regression (#11)

Run `python3 StandaloneTests/GroupSession/run.py`. This compiles the production
session model/store and extracted controller methods against simulated process,
AX and panel boundaries. It does not operate real windows or request permissions.

Coverage includes ordered/selected member restoration, process-instance identity,
missing windows, changed Spaces, permission waiting, quit snapshot retention,
empty sessions, bounded AX retries and cancellation, malformed/versioned/oversize
state, private permissions and destination symlinks.

Manual verification:

1. Make two groups (including a mixed-application group), select a non-first tab,
   and quit Tabbed while keeping those application windows open.
2. Relaunch: the surviving groups, order and selection should return. Repeat in
   normal and Always Compact modes and on multiple displays/Spaces.
3. Between Quit/relaunch close one saved window: two survivors should regroup;
   a sole survivor should remain independent. New windows must not substitute.
4. Explicitly ungroup, Quit and relaunch: that group must stay ungrouped.
5. Quit before granting accessibility: the previous session should survive; grant
   access and relaunch/allow startup to complete, then verify restoration.
6. If quit restoration fails, cancel and retry Quit: the original group snapshot
   must survive. This uses existing quit recovery UI and is not automated here.

State is stored privately in Application Support/<bundle identifier>/window-groups.json.
It contains numeric window/process IDs, process launch times, bundle identifiers,
member order/selection and geometry; no titles or URLs. Only surviving windows in
unchanged owning process instances are eligible. Separate Spaces are not merged.
Startup uses an initial attempt plus up to three half-second AX retries; manual
Command-drag/ungroup cancels pending retries. No apps or windows are reopened.
