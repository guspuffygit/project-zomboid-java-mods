# AVCS claim management and window fixes

These changes belong to AVCS and can be deployed without Universal Admin Core or
ATF patches. They target Project Zomboid 42.20.4 and use the repository's Storm
dependency for the Java integration.

The claimed-vehicle window supports native drag resizing and a Size dialog. Its
toolbar, list, labels and preview are repositioned together; narrow windows stack
the information fields. Resizing back up restores the original proportions.
Admin and permission windows also receive screen fitting and saved geometry.

Only the owner or an admin may unclaim a vehicle or change its public permissions.
Shared faction/safehouse access still controls vehicle use. Permission updates
accept only the ten known boolean fields, validate the whole update before writing,
and cannot replace ownership metadata. Invalid command payloads and stale vehicle
IDs are rejected; rebuilding the database tolerates incomplete player records.

Admin Untow detaches a currently loaded claimed vehicle through the native tow
constraint operation. It requires the admin role on the server and logs the action.
It is Lua-only. It does not load a distant vehicle's area.

The existing Storm admin teleport gains cancellation when the requester disconnects
or loses the admin role, plus authority/interpolation reset and an AVCS-owned warp
notification. Its optional client Java helper validates both the runtime vehicle ID
and persistent claim ID before applying the server position. The server still
rejects occupied or attached vehicles and retains its existing unloaded-area logic.

Lua UI, claim permissions and Untow do not require client Java. The explicit
client physics resynchronization requires Storm and the updated AVCS Java module on
each client; clients without that helper retain native vehicle synchronization.
This is not a claim that client Java runs through ordinary Lua mod distribution.

## Validation

Claim-cache recovery now publishes the vehicle and owner indexes together. Partial
or inconsistent snapshots fail closed and trigger coalesced retries. A generation
identifier rejects older replies; the server rate-limits full snapshots per player.
Permission saves send the desired state and wait for a matching server acknowledgment,
with visible retry after timeout. Revision checks ignore older permission deltas.

Persistent vehicle identity uses the native vehicle-part ModData stream, which
survives unloading. It does not send generic world-object ModData for vehicles or
retain delayed runtime-ID assignments. Vehicles without the configured mule part
retain the legacy loaded-only hint and newly spawned vehicle ModData; verify unusual
mod vehicles separately. Claim-use authorization remains server-owned.

The map caches group claim metadata and label widths, removes duplicate group markers,
and culls offscreen labels. Claim revisions, faction/safehouse changes and locale
changes invalidate it; a two-second fallback catches missed events.

Lua regressions now also cover partial/stale snapshots, permission acknowledgments,
native vehicle identity and map cache/viewport behavior. These pass in Lua 5.1 and the
installed game Kahlua interpreter. Current upstream changes, including container
permission checks, are retained. Local Java validation used installed Storm 2.10.1
because upstream's Maven 2.10.0 coordinate could not resolve; the substitution lives
outside the repository and is not a production dependency change.

From the repository root, using Java 25 and `gameDir` in `local.properties`:

```powershell
.\gradlew.bat :another-vehicle-claim-system:test :another-vehicle-claim-system:spotlessCheck :another-vehicle-claim-system:jar -x :another-vehicle-claim-system:jacocoTestReport
powershell -NoProfile -ExecutionPolicy Bypass -File another-vehicle-claim-system/Verify-Lua.ps1 -GameDir 'C:/path/to/ProjectZomboid' -Kahlua
```

The module compiles against the installed `projectzomboid.jar`, excluding unrelated
shadow classes from `B42MP.jar`. The Lua fixtures cover management rejection,
layout at different fonts/memberships, native resize/Size callbacks and warp queue
expiry. The optional Kahlua run uses the game's interpreter with a stub UI backend;
it does not launch or modify a game.

Before live rollout, validate Untow and permissions with owner, faction member and
admin accounts. Check resizing visually, then use two clients to verify loaded and
unloaded vehicle relocation, reconnect and driving after a teleport. Repeat with a
mod vehicle. Those in-game acceptance checks remain pending.
