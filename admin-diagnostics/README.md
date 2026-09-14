# Admin Diagnostics

An opt-in, local incident recorder for Project Zomboid 42.20.4. Use it to investigate
admin client slowdowns, disappearing world/UI elements and memory spikes on the
existing server setup. It is independent of Universal Admin Core, AVCS and ATF.
It records evidence; it does not establish that admins are being throttled or fix
the reported production problem.

## Enable and mark an incident

Install and enable `admin-diagnostics-b42` through the server's normal Lua mod
distribution workflow. The mod starts **off** on every client/session and requires
the local player's role to have admin power before starting.

- **Ctrl+Shift+F10:** start/stop recording.
- **Ctrl+Shift+F11:** mark "the issue is happening now" while recording, including
  when the admin window disappears and keyboard input still works.
- The normal Admin Panel has a Diagnostics start/stop button. The world context
  menu includes start/stop, manual marking and status/help for staff.
- With Universal Admin Core enabled, these actions appear in its **Logs** category.

Start before approaching the problematic player count. On a visible failure, mark
it once, wait about 20 seconds if possible, then stop and copy the logs. A marker
does not take a screenshot or capture anyone's chat/inventory.

Logs are local to the affected client's active Zomboid profile:
`Zomboid/Lua/admin-diag-1.log` through `admin-diag-4.log`. Each line starts with
`[ADMIN-DIAG]` followed by JSON. UTC epoch milliseconds and a session ID allow
reports from different admins to be aligned. File slots rotate at approximately
2 MiB each (about 8 MiB total); copy an incident before further recording overwrites it.

## What gets recorded

Every two seconds while enabled, the recorder keeps a bounded snapshot containing:

- Tick and render/UI callback rates and the longest tick gap.
- Known network-player count; locally loaded vehicles, zombies, animals and remote
  player-list counts. These are **not** a guaranteed total server population or a
  count of entities successfully drawn on screen.
- Local coordinates, role, presence of the player/current square, death, vehicle,
  invisibility/god/noclip state and the local player's alpha value.
- Visible top-level UI count and up to 24 UI class names, including admin/debug
  panels where their Lua class is available. Traversal stops at 128 UI elements
  and marks truncation. It does not walk UI children or every world entity.
- Lua debugger error-count changes, connection-state events, disconnects and UI
  initialization. Native exception text is collected by the optional Windows
  monitor below, not by intercepting or replacing the game logger.
- The current Universal Admin Core observe target, if that optional module is active.

The optional client Storm Java helper adds **JVM heap used/committed/max**, garbage
collector count/time, latest connection ping, connection-ready state, shared chunk
count and the global UI visibility flag. Without that helper these measurements
remain unavailable; no zero values or stale cached memory readings are substituted.
Java heap is not total process RAM or GPU memory. The helper does not force garbage
collection, add bytecode transformers or change server/network behavior.

Incidents include the preceding 60 seconds and the next 20 seconds of samples.
Triggers include a tick stall of at least 1 second; sustained render callback rate
below 15/sec; a 256 MiB heap increase; heap above 90% of its maximum; increased GC
time; ping crossing 500 ms; Lua errors; UI loss/reinitialization; position jumps;
and large loaded-count drops while stationary. Teleports give a 15-second grace
period for entity-unload alarms. Normal hiding of UI, admin invisibility, travel,
death, alt-tabbing and expected teleports can explain some triggers: these are
signals to correlate, not conclusions about a defect or a cheat verdict.

Automatic reports have a global ten-second cooldown and a sixty-second cooldown
for the same reason combination. Manual markers have a five-second cooldown.
Quiet sessions write only a small checkpoint once a minute, plus start/stop records
and the remaining history when stopped;
this preserves a last known state if the client exits abruptly. A freeze cannot be
recorded by Lua until it resumes. Sampling hooks are removed on stop, disconnect,
Lua reset, loss of staff permission or an internal recorder/write failure.

## Optional Windows monitor: process RAM and native errors

Run `tools/Watch-AdminClient.ps1` separately on each affected admin's Windows PC.
It continues running if the game JVM stops responding and records process exit
without asserting whether the exit was a crash or a normal close.

Find the client PID (select the affected client, not the server or a second client):

```powershell
Get-Process ProjectZomboid64 | Select-Object Id, ProcessName
powershell -NoProfile -ExecutionPolicy Bypass -File tools/Watch-AdminClient.ps1 -ClientProcessId 12345 -ConsolePath "$env:USERPROFILE/Zomboid/console.txt"
```

Replace `12345` and the console path with the affected client's PID and active profile.
If your launcher uses a Java process name, select that client's PID in Task Manager.
The monitor checks working set, private bytes, CPU time, threads and handles every
five seconds, plus system available RAM and committed-memory/commit-limit counters.
It keeps 60 seconds of history, saves memory incidents with 20 seconds afterward,
and writes one quiet checkpoint per minute. Output defaults to
`Zomboid/AdminDiagnostics/admin-os-1.jsonl` through `admin-os-4.jsonl`, also bounded
to approximately 8 MiB. Use `-OutputDirectory` for a different active profile.

With `-ConsolePath`, it watches **new** native console output for timeout/desync,
exception, memory, chunk-failure/removal, vehicle-packet and correction warnings.
It reads at most 64 KiB per poll and retains at most 20 matching lines, each clipped
to 500 characters. Old console content is skipped; excessive output can be omitted.
Warning batches are limited to once per 15 seconds. Password/token/authorization
lines are omitted and IPv4 addresses are masked. Logs remain local and may still
contain names or coordinates: review them before sending them to another person.
Use Ctrl+C to stop. No admin/elevation prompt is required for your own process.

For a useful report, collect both logger outputs and the original native console
and fatal `hs_err_pid*.log` report, if one was produced. Note what you were doing,
the approximate server player count, whether regular players saw the same failure,
and which clients had Storm Java loaded. Compare timestamps across affected admins.
No automatic uploads, screenshots, dumps or messages to a developer are performed.

## Build and verification

From the repository root, Java 25 and `gameDir` in `local.properties`:

```powershell
.\gradlew.bat :admin-diagnostics:test :admin-diagnostics:spotlessCheck :admin-diagnostics:packageLocal -Penv=prod -x :admin-diagnostics:jacocoTestReport
powershell -NoProfile -ExecutionPolicy Bypass -File admin-diagnostics/Verify-Lua.ps1 -GameDir 'C:/path/to/ProjectZomboid' -Kahlua
python admin-diagnostics/tests/test_watch.py 'C:/path/to/new-test-output-folder'
```

Output: `admin-diagnostics/build/distributions/admin-diagnostics.zip`. The Lua
recorder works without client Java; enable this module's Java JAR through Storm's
client installation workflow for fresh JVM/connection counters. Merely downloading
the Lua mod does not load Java into a vanilla client. The server does not require
the Java helper. The build does not install, restart or publish anything.

Tests cover actual game Kahlua compatibility with stub game/UI objects, incident
history, rate limits, missing measurements, teleport suppression, bounded UI/log
storage, permission loss and recorder failure handling. The Windows integration
test uses disposable local processes and synthetic console errors. Live high-player-
count reproduction and performance impact measurements remain unverified.
