# Safehouse respawn selection

UAC 0.2.8-alpha for PZ 42.21.0. Install matching UAC and compatible Storm on the
server and clients, then enable `SafehouseAllowRespawn`.

Owners and current members can choose an eligible safehouse on the existing
character creation location/map screen. Its name, owner and coordinates appear
in the native description. The permanent Safehouse UI respawn checkbox is hidden
when the server confirms support. No future respawn preference is saved.

Normal/custom locations remain available. Safehouses are never automatically
selected or included in Random. Challenge modes keep their native flow. Faction
membership alone does not grant access. A configured fixed `SpawnPoint` remains
the ordinary default; an authorized safehouse choice overrides it for one attempt.

The server uses the authenticated connection and player slot, not a supplied
username or coordinates. It rechecks ownership/membership and claim identity at
selection, character creation and world join. Released claims, revoked access,
expired/replayed tokens and live-character requests are rejected. A small journal
protects the previous dead profile if an accepted creation is interrupted.

Post-death rejection returns to the existing choices with customization retained.
Rejection after initial-login loading starts aborts that connection safely; rejoin
to choose again. An existing secondary profile can use its verified account.
A new secondary slot keeps normal choices until an authenticated profile exists.

The vanilla flow was tested locally. Native Java and Lua fixtures cover token
validation, profile recovery and creation-screen integration. The live server's
custom map selector was unavailable, so its exact UI integration still needs a
test with those files. Existing custom region providers are preserved.

Remaining checks include removed members, released claims, multiple eligible
claims, reconnect/restart, revocation during loading, controller/split-screen
flow and the live custom selector.

This branch runs from main without PR #15. If both changes land, resolve shared
`AdminCoreMod` and version metadata conflicts by keeping both sets of transformer
registrations and bridge exposure. The observer and admin UI changes are separate.

Keep a full world backup when testing character creation. If an attempt is
interrupted, let the matching build complete recovery before removing it; restore
the complete backup rather than mixing an older players database with a newer world.
