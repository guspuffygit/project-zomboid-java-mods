# Performance and synchronization fixes

The client compatibility hooks activate with this module when their target mods are present:

- Chunk List keeps a full export selection but highlights only the nine neighboring chunks.
  Keyed coordinate lookup replaces growing duplicate scans. Stop, export and cancellation
  release transient data; a same-callback stop/export retains the complete selection.
- ATF safehouse HUD uses a coarse spatial index with the original inclusive boundaries.
  Giant claims use a fallback list instead of allocating unbounded index cells. Routine
  rebuilds no longer print every safehouse. Safety checks still use current claim data.
- Lifestyle and True Music Radio tick callbacks skip temporarily missing/dead players.
  Hooks survive reload without duplicate registration and resume when the player returns.

The optional server Java helper completes native safehouse/chat synchronization after
direct offline creation. It is called by the paired ATF Core source patch, validates that
the native safehouse still exists, and does not add a client command or permission bypass.

## Source integration required

The five Lua source diffs in [patches](patches/README.md) repair ATF safehouse identity,
unchanged broadcasts and member/respawn reconciliation; budget Lifestyle's startup scan;
bound Error Magnifier retention/work; and clean up invalid True Music Radio devices.
They are actual code patches, but are **not auto-loaded by this module**. The target mods
contain local functions and anonymous event callbacks that require source integration.
Use the hash-checked patch applicator and distribute the matching client/server files.
The original third-party sources are not included in this PR.

## Verification

From the repository root, Lua 5.1 and `luac` on PATH:

```powershell
powershell -NoProfile -File guspuffy-atf-patches/Verify-Lua.ps1
```

For the source-patch regressions, supply a folder containing the five patched files in
their manifest paths (the `mod-name/version/media/...` layout). Original files are not
fixtures in this repository:

```powershell
powershell -NoProfile -File guspuffy-atf-patches/Verify-Lua.ps1 -VendorFixtures 'path/to/patched/mods'
```

The same scripts were exercised with the installed B42.20.4 Kahlua engine using
`tests/RunKahlua.java`, `-Dtest.root=<repository>` and the game as working directory.
Java compilation and the existing module tests pass with Java 25 and the installed
Storm 2.10.1 distribution. The upstream Maven 2.10.0 coordinate was unavailable locally;
the local validation substitute is not a repository build change.

These changes address specific repeated work and stale state. Native/process RAM growth
has not been attributed to a component. No live server deployment, high-population
performance measurement or general cure for disappearing entities is claimed. Test
disconnect/reconnect, long travel, claim changes and radio removal before rollout.
