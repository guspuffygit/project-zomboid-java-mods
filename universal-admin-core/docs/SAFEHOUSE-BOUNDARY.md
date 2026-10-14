# Edit safehouse boundaries

Open a safehouse's native detail window, then choose **Edit Boundary**. The
button requires a current server grant for `ADMIN_SAFEHOUSE_EDIT` and the native
`CanSetupSafehouses` capability. The server checks both again on submission.

1. Keep **Expand** to retain every currently claimed tile, or switch to
   **Redraw** to replace the rectangle, which can remove claimed tiles.
2. Choose **Draw boundary in world** and drag two corners. Blue shows the
   existing claim; green is valid, red overlaps another claim, and yellow means
   another claim is within three tiles. Nearby claims do not block a valid edit.
3. Review the current/proposed areas and change in area. Add an optional reason
   of up to 160 characters, then **Confirm Boundary**.

The server rejects stale snapshots, released claims, missing authorization,
invalid coordinates, overlap and native network identity collisions. Rectangles
must have whole-tile sides between 2 and 200 tiles and fit the available world
map. The edit session expires after two minutes; reopen it if rejected as stale.
Client preview is advisory, and touching edges are allowed.

**Boundary history** shows the latest 25 edits. The server retains a bounded
history of 100 edits with the admin, original and new bounds, mode, reason and
time. History and integration identity aliases persist in world ModData.

Changes update the same native safehouse object without delete/recreate. Owner,
members, existing respawn preferences, creation metadata and chat linkage remain
intact. The coordinate-derived network ID updates on the server and connected
clients. This does not add a new respawn-selection system.

Boundary editing has been accepted in the local test build. Native tests also
cover preservation through save/load; Lua fixtures cover stale/malicious
requests, consumed tokens, alias rollback and bounded history.

Servers running ATF Community or Garage must include their optional identity
readers before enabling edits. See the
[companion patches and backup requirements](compatibility/SAFEHOUSE-BOUNDARIES.md).
Other mods that key claims by coordinates need separate review. Current town
containment and garage distance rules still apply after a boundary changes.
