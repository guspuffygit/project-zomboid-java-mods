# Safehouse boundary compatibility

UAC edits the existing native safehouse in place. Ownership, members, existing
respawn preferences, creation metadata and chat linkage are retained. Boundary
editing has been accepted in the local test build. It does not include the
separate one-shot respawn selection feature.

ATF Community and ATF Garage historically identify safehouses by
`x:y:creationTimestamp`. Moving the minimum X or Y would otherwise change their
property/tax or garage sponsorship identity. UAC records the original identity
in persisted `ModData["UniversalAdminCore.SafehouseBoundaries.v1"].aliases`.
Repeated edits map directly to the original key. The two companion readers
accept only aliases with the same creation timestamp; newly recreated claims
keep their own identity. Membership and proximity still use the current claim.

## Operators using Community or Garage

Install the companion readers in those modules before enabling boundary edits:

- [Community patch](community-safehouse-boundary-alias.patch):
  `CommunityWorld.safehouseIdentity`.
- [Garage patch](garage-safehouse-boundary-alias.patch): `GarageSafehouses.Home.key`.
  The local Garage 0.10.1-alpha build already contains this reader.

These are source-only patches for the existing modules, not runtime components
of UAC. UAC works independently when neither integration is installed. An older
Community/Garage build without its reader must not be used with boundary edits.
Keep the world ModData alongside the safehouse save and module databases when
backing up or restoring. Do not remove aliases after edits or roll those readers
back independently; restore the coordinated backup if rollback is necessary.

Apply each patch from its module repository root, first checking that it matches:

```text
git apply --check /path/to/community-safehouse-boundary-alias.patch
git apply /path/to/community-safehouse-boundary-alias.patch
```

Use the Garage filename from the Garage source root. Rebuild and install through
the module's normal procedure. If `--check` fails, review the method manually;
the reader may already be present. Do not force a patch onto an unknown revision.

## Verification and limits

Both patches were checked forward and backward against exact local preimages,
then compared byte-for-byte after LF normalization with the working readers.
The preimages were reconstructed by removing only the reader and its imports
from the local source; they are not a claim of a published upstream revision.

| Module | Preimage SHA-256 | Postimage SHA-256 |
| --- | --- | --- |
| Community | `78f027ed50ff4a694ef22cd8b6d550d7631937bd52dcec306b733756c793cd69` | `733eba899477ba769263cd55648101d0f7bfc59c5f8161b49296c4e9928eea48` |
| Garage | `d800a83a5775e398a644e8fe9b1febc57fd0ea30320b1e6f79ca2c6bf743e874` | `87587e0306571b52f88cf7cec8ccd426ee63d07daf92bb60ba0911e4c0faf340` |

Existing focused local tests cover native safehouse/ModData save-load with the
original Community database identity, and Garage binding preservation while
rejecting removed membership, out-of-range kiosks and recreated claims. Those
modules' tests and binaries are not bundled into UAC.

When adapting another revision, test an unedited claim, west/north expansion,
repeated edits, save/restart, removed membership and recreation at the same
coordinates. Verify that Community keeps the original tax/property identity and
Garage keeps the original sponsor binding. Geometry changes can legitimately
move a claim outside a town or a kiosk's permitted distance; identity retention
does not waive those current-boundary rules. Unknown integrations that derive
identity from coordinates need their own compatibility review.
