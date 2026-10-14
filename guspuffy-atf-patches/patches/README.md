# Vendor source fixes

These are executable source patches for the inspected ATF Core 42.14, Lifestyle common,
Error Magnifier 42.15 and True Music Radio 42.20 releases. They are **not auto-loaded** by
installing the ATF Patches jar. The affected Workshop sources have local functions and
anonymous event handlers that cannot safely be replaced by a normal late-loading hook.
Their maintainers must integrate the patches into those mods and distribute matching
server/client Lua. Only diffs are included; original third-party mods are not repackaged.

`apply.py` checks the exact original SHA-256 values, applies into a new output folder and
verifies every resulting file. The source folder remains unchanged. Requires Python 3 and git.

```powershell
python guspuffy-atf-patches/patches/apply.py --module atf-core --source 'path/to/ATF/42.14' --output 'new/atf-core/42.14'
python guspuffy-atf-patches/patches/apply.py --module lifestyle --source 'path/to/Lifestyle/common' --output 'new/lifestyle/common'
python guspuffy-atf-patches/patches/apply.py --module error-magnifier --source 'path/to/ErrorMagnifier/42.15' --output 'new/error-magnifier/42.15'
python guspuffy-atf-patches/patches/apply.py --module true-music-radio --source 'path/to/TrueMusicRadio/42.20' --output 'new/true-music-radio/42.20'
```

The output contains changed files only, preserving their `media/lua/...` paths. Apply them
to a copy of the corresponding mod before packaging; do not replace a complete mod with
these few files. A source-version mismatch requires a new review rather than bypassing hashes.

Changes:

- ATF safehouses use bounds keys (native `getId()` includes a local timestamp), retain duplicate
  titles, reject ambiguous legacy release requests and preserve membership/respawn/metadata
  during reconciliation. Unchanged full broadcasts are suppressed. Activity-only timer changes
  use native/on-demand updates. Install both ATF client and server patches together. The new
  ATF Patches server helper completes native/chat synchronization after direct offline creation.
  Staff release, assignment, forced release, diagnostic dumps and alerts require the current
  `CanSetupSafehouses` capability. Owners can still request release of their own claim.
  Role names alone do not grant access; missing capability support denies staff operations.
- Lifestyle budgets its startup scan and removes unloaded references. Inventory names delegate
  the native renderer, preserving Livestock overlays in either load order without an extra
  full-inventory scan. Neural Hat reading supports the actual invention schema. Repair,
  bathtub, toilet refill and mirror callbacks handle their inspected failure cases.
- Lifestyle reward actions use server lifecycles, connection/actor provenance and existing
  formulas. The paired module supplies reward helpers and native ownership validation.
  Install all Lifestyle client/shared/server patches together. Saved legacy progress has
  bounded fields; nonmigrated ambition, Inventing and object authority remains documented
  in [the compatibility notes](../PERFORMANCE-FIXES.md).
- Error Magnifier processes at most 32 new entries per callback, retains 256 unique errors,
  truncates retained entries at 16 KiB and refreshes its window at most four times per second.
  Old entries are evicted; full original logs remain the source for incident investigation.
  Fragment merging across batch boundaries may display adjacent stack fragments separately.
- True Music Radio guards missing players and device data and stops/removes stale sounds
  without dereferencing missing parents. The existing `whereAreYou` fix remains in place.
  Its sound helper uses `TrueMusicRadio/TMRSound`, so initialization no longer relies on
  automatic file loading after a failed bare-name require. The terminal menu uses the same
  explicit module path. Server-owned terminal stock/revisions prevent repeated ejection;
  normal walks complete before requests. Staff-only stock reset preserves the original
  additional-media feature. See the compatibility notes for migration/crash limits.
- ATF automatic safehouse safety removes an unused require of the removed ISSafetyUI file.

The native crash reports showed exhausted system commit capacity. These bounded workloads
and caches are concrete repairs; they do not identify or claim to fix the entire process's
native-memory growth or all disappearing-world incidents. High-player-count acceptance is pending.
