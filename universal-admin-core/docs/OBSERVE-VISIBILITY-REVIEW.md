# Remote observation review

UAC 0.2.7-alpha includes bounded terrain streaming and server-approved replication
for Observe and Free Camera. Both peers need matching UAC and compatible Storm.
Native fixtures verify the integration. Local gameplay checks reported this
session confirmed observation and safehouse boundary editing working. Broader
multiplayer and engine cases still need the checks listed below.

The camera fixes address sprite movement without 3D camera movement and black
remote terrain. B42's projection now reads the observer coordinates. Render-only
lighting gates and room fade use bounded observer views; stored lighting flags,
colors and exploration are unchanged. The first interest request waits 250 ms
to avoid rejection during the new lease's movement-rate interval.

Follow now reads native interpolated player coordinates between replies. Soft
Follow acknowledges pan offsets separately, so moving targets do not add false
pan after a delayed reply. The observer header can minimize to a status bar.

Outdoor fallback light now matches native skylight brightness, tint packing and
8-bit precision. The native screen vision mask uses the stationary avatar's
facing and tree cover even after terrain renders. It is skipped only inside an
authorized observer render; expiry and revoked access restore native behavior.
Remote lamp shadows and interior lighting still need a separate native lighting
context. Streaming bounds remain finite and move with the accepted camera.

## Why players disappeared

PZ 42.21.0 `IsoPlayer.render` uses the physical avatar's distance, facing and sight
when checking a remote player's visibility. Terrain can render while that body
is hidden. The existing render-scoped player patch corrects that check for an
authorized observer. Invisible players still require `SeesInvisiblePlayers`.

That patch alone cannot create missing terrain, a player square or network
updates. Native `PlayerPacket.processClient` removes a remote player when its
predicted square is unavailable. The new streaming work supplies those inputs.

## Streaming and safety

| Component | Behavior |
|---|---|
| Client terrain | Viewport-sized region, from 7 by 7 to at most 19 by 19 chunks, within native capacity and centered on server-accepted coordinates. At most eight new requests per 100 ms. |
| Origin | The physical avatar keeps its original map. Rendering borrows the observer map and restores the original slot, including nested calls and failures. |
| Server terrain | Authorizes bounded chunk downloads and retains at most 16 intersecting native server cells per observer region. |
| Replication | Narrow outgoing patches include player, vehicle, zombie, animal and relative world updates inside the observer region. |
| Authorization | Current role, spectator/render capabilities, server policy, account connection and character identity are checked. Heartbeat renews a six-second lease. |
| Free Camera | Current floor only; server checks finite coordinates, speed and increasing request sequence. Soft follow stays within eight tiles of its target. |
| Cleanup | Stop, expiry, death, disconnect, character replacement, vehicle entry and revocation remove the lease and observer chunk references. |

The server does not widen `UdpConnection`'s physical relevance. Gameplay
authorization continues to use the avatar's normal position. Camera updates never
set avatar coordinates or send movement packets. Exploration and native LOS stay
unchanged. Native patch markers are required before remote streaming is granted.
Duplicate or older acknowledgements cannot renew the client lease.

Client interest requests run at most four times per second. Server centers drive
downloads; predicted panning cannot request arbitrary chunks. A loading timeout
stops observation with the origin intact. Teleport and Return are separate actions.
Free camera does not assign zombie simulation ownership in an otherwise empty
area. Following a live player receives the area's existing owned-zombie updates.

## Validation

Tests weave the installed native B42 methods and exercise visibility, map lookup,
chunk delivery, cleanup, render restoration, connection relevance, capability and
policy revocation, character replacement, malformed/replayed requests and lease
expiry. Lua tests exercise actual client/server handlers and legacy loaded-only
behavior when the streaming bridge is unavailable.
Native execution tests compare the observer projection to the same camera at
the selected coordinates and check the remote chunk lighting gates.
They also execute the native vision-mask entry and compare fallback skylight
against the installed game's packed sky calculation.

Generated evidence is under `build/test-results`, `build/reports` and
`build/validation`. Disposable server boots verify patch installation and restart
without opening the saved local world.

Interactive checks still required:

- Follow an account into a previously unloaded area and confirm its body remains visible.
- Pan Free Camera beyond the original region; confirm terrain and moving players update.
- Stop, revoke permissions, disconnect and restart; confirm the origin and input restore.
- Repeat with another local player, vehicles, zombies, animals and invisible staff.
- Cross a region boundary at normal and maximum zoom; check lighting and movement.
- Minimize, drag and restore while following and panning; confirm input and Stop work.
- Check mouse/focus, UI scale, roofs and weather restoration.

Some roof and cutaway behavior still follows the physical avatar. Observation is
an administrator's clear view, not the target's exact private view cone. These
changes do not establish production readiness or a measured FPS improvement.
