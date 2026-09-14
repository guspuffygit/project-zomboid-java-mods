# Universal Admin Core

A reusable admin interface for Project Zomboid **42.20.4 with Storm**. This independently deployable Gradle module provides general administration tools. There is no dependency on ATF, its economy, AVCS, or private APIs.
"Universal" means reusable by other servers on this supported game API, not
compatibility with every Project Zomboid version.

The normal **Admin Panel** opens a server control center:

**Dashboard | World | Zones | Vehicles | Events | Server | Security | Logs | Mods | Settings**

Search matches action names and topics across every category. Dashboard contains
common shortcuts. Resizing, saved window geometry and pagination keep controls
reachable at smaller resolutions. Existing native buttons retain their callbacks,
permission state and tooltips. Additional buttons supplied by other mods appear in
Mods unless explicitly categorized.

The **User List** remains player-focused. Its selected-player menu groups teleport,
inventory, moderation, logs, safehouse and faction actions. Copy username/SteamID,
ping, and a direct stats/traits/skills shortcut are available there. Stats editing
uses the existing game dialog and requires the target to be loaded by the client.
The ordinary player's User Panel retains a visible safehouse entry, enabling it when membership arrives after the panel opens.

Version 0.1.1 adds a search field to the safehouse/safezone and faction **Add Player**
dialogs for every client, including ordinary owners. It matches usernames and display
names without case sensitivity, provides Clear and a result count, retains filters
when the online list updates, and preserves invitation/ownership restrictions.
Typing filters the received online list locally; it does not fetch private accounts
or send additional requests. The separate offline-account tool remains staff-only.

## Available now

Version 0.1.5 skips hidden User List rows before account/faction lookups and caches
formatted visible cells until their inputs change. Display caches are capped at
256 entries and refreshed within two seconds; faction events invalidate immediately.
Observe now waits for an earlier relocation to arrive before sending the next one,
with a six-second retry bound. Permission revocation is checked before that wait,
and stopping clears pending movement. This reduces repeated relocation requests
while the client is still loading, without weakening the server-owned return lease.

Version 0.1.3 fixes observe stopping after about 10–12 seconds. B42 encodes empty
client-command tables as nil; the server now accepts that for heartbeat and stop
commands while retaining payload validation for other actions. Observe updates run
independently of stats refresh, and server stop acknowledgements no longer echo a
stop command that could cancel a newly selected target. The lost-connection timeout
and server-owned return position remain in place.

Version 0.1.2 fixes offline safehouse membership and ownership changes by matching
the claim's bounds, as the game's synchronization packet does. The game's string
lookup matches titles, while its timestamp-based IDs differ between server and
client. Regressions cover duplicate/renamed titles, client/server identity, and deleted claims.

| Area | Working entry points |
| --- | --- |
| Dashboard | User List, own stats, admin powers, scoreboard, native performance statistics; quick links to server settings, safehouses and announcements |
| World | Item catalog, weather/climate, coordinate teleport/copy, native area item-removal tool |
| Zones | Safehouses, factions, No-PvP management, native multiplayer zone editor, world drag-select safehouse creation |
| Vehicles | Native vehicle spawner |
| Events | Native zombie/horde manager, including its area spawn/removal controls |
| Server | Native server options editor, confirmed broadcast announcement, confirmed world-save request |
| Security | Native role/permission management |
| Logs | Native tickets and PvP log viewer; player logs and suspicion activity stay in the selected-player menu |
| Mods | Client active-mod list, other mods' Admin Panel buttons, registered extensions |
| Settings | Native sandbox settings editor |

The player tools also retain inventory inspection/item giving, offline-account
pickers for safehouses and factions, ownership transfer with server revalidation,
claim release, inspection return teleport and report export. The User List shows
faction and tracked connected time without an economy column. Time starts when
this module is installed; it is not historical lifetime playtime.

Experimental observe/follow is shown only when the optional client Java camera
helper is loaded. It moves an invisible, god-mode, noclip admin near the target for
chunk streaming and returns them on stop/timeout. It is not the target's own screen.
Ordinary administration does not need this camera feature. Its live behavior still
needs a two-client acceptance test.

## Scope of this first extraction

The long admin wishlist is a roadmap, not an implemented feature checklist.
Restart/shutdown orchestration, backups/status, scheduled announcements, remote
health/revive workflows, bulk player actions, temporary bans, unified admin notes,
complete login/logout history, vehicle cleanup/heatmaps, loot/building resets,
spawn/respawn management and anomaly dashboards are **not implemented here**.
Other requested operations may be available inside native dialogs; no new guarantee
is made for them. No placeholder button claims to perform an unsupported action.

Safehouse creation retains the previous inclusive world rectangle selector.
No-PvP creation currently retains the game's walking-based dialog; drag-select
No-PvP creation is still pending. A world save is not a separate backup. The active
mod list describes this client, not the server's private Java modules. Suspicion
information is investigative data, not an automatic cheat verdict.

## Build and verify

From the repository root, with Java 25 and `gameDir` configured in `local.properties`:

```powershell
.\gradlew.bat :universal-admin-core:test :universal-admin-core:spotlessCheck :universal-admin-core:packageLocal -Penv=prod -x :universal-admin-core:jacocoTestReport
powershell -NoProfile -ExecutionPolicy Bypass -File universal-admin-core/Verify-Lua.ps1 -GameDir 'C:/Program Files (x86)/Steam/steamapps/common/ProjectZomboid'
```

Output: `universal-admin-core/build/distributions/universal-admin-core.zip`.
This assembles a local artifact; it does not publish to Workshop or edit a running
server. `packageLocal` requires `-Penv=prod` so its folder, mod ID and Storm dependency
agree. The normal repository deployment task remains available for other environments.

For a clean test profile, extract the archive into the profile's `Zomboid/mods`
directory and enable `universal-admin-core-b42` alongside Storm on the server and
clients. Distribute the Lua files through the server's normal mod workflow.

When migrating from another admin overhaul, disable its replacement menus before enabling this module. AVCS tools and Extra Logging fixes are separate modules. Existing prototype playtime records are not imported automatically.

## Extension contract

Optional mods can register control-center actions without replacing the whole panel:

```lua
require "AdminCore/Registry"
AdminCore.registerAction({
    id = "example.vehicle-manager",
    title = "Vehicle manager...",
    category = "Vehicles",
    capability = Capability.ManipulateVehicle,
    available = function() return ExampleVehicleUI ~= nil end,
    run = function() ExampleVehicleUI.open() end,
})
```

Stable IDs replace registrations instead of stacking buttons. A capability or an
explicit `allowed` function is required, and checked again when invoked. The
implementation must enforce permissions on the server; UI gates are not security
boundaries. Native options continue through native server checks. Custom membership
and observe requests use the `UniversalAdminCore` protocol and repeat authorization
in the server Lua handler and Java bridge.

The control center does not poll server metrics in the background or scan world
entities. Player-detail requests cover visible rows, at most 50 names once per
second, with request backoff and a bounded cache. Zone tracking does no per-frame
position work when no selection tool is active. This is not a demonstrated fix for
the reported production admin crashes or visibility loss.

## Validation limits

Automated checks exercise the installed vanilla Admin Panel through UI stubs,
including pagination at 1280x720 and 800x600, large-font geometry, native and
third-party action preservation, permission changes, confirmation/input handling,
membership guards, playtime and observation expiry. A Java test weaves the camera
advice into the installed game class without loading the game runtime.

In-game visual acceptance, two-client observation/membership behavior and production
load testing remain pending. Before rollout, verify all categories and dialogs,
scroll/search the User List, try a restricted staff role, and use disposable claims
for membership/zone actions. No live-server changes or publishing are performed by
this build workflow.
