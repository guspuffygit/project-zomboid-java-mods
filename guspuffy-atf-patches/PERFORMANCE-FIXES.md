# Compatibility fixes

Client hooks bound Chunk List highlighting and safehouse HUD lookup, tolerate temporarily missing players and survive reload without duplicate callbacks. Native safehouse/chat synchronization uses the paired ATF Core patch. Talis global debug changes require the current SandboxOptions capability.

## Source integration

The [source patches](patches/README.md) repair ATF safehouse synchronization, Lifestyle rendering/actions/rewards, Error Magnifier retention and True Music Radio cleanup/ejection. They are not applied by installing this module alone. Integrate matching client/server files with the module and its native action helper. Original Workshop sources are not bundled or changed.

The reward migration stays inactive without the paired server routes, preventing parallel rewards when the module is installed alone.

Lifestyle XP is calculated from the existing formulas after a validated native action starts. The server checks the submitting connection, actor, current inputs and elapsed time. Cancellation closes the action; replay cannot repeat its final reward. Yoga poses are intents, not client XP amounts. One validated early pose can wait for its earned deadline; completion allows a bounded 30-unit timing grace. Neural Hat bonuses and Mindfulness/Terminator healing use server state. Staff XP diagnostics use a separate capability-checked command.

Resource scans run at most every 250 ms between rewards, with fresh checks before grants and completion. Snapshots update only the intended local player and preserve unsaved legacy skills.

Saved data uses a bounded schema. Yoga, Mindfulness, Neural Hat effects and Terminator progress are protected. Reviewed older Inventing/PingPong, other ambition and modifier fields, including lingering Dunce penalties, retain their client-owned behavior. This is not a complete Lifestyle authority migration: those legacy completion conditions, object metadata and native XP acceptance still have their existing trust boundaries. Server-approved custom invention overrides require a separate review; the hat validation covers the inspected stock definitions.

Radio ejection requires an accessible adjacent terminal, an enabled powered channel, approved media and a server stock/revision match. A persistent reservation prevents replay after reconnect or reload. Migration seeds bounded historical terminal stock once; it cannot establish whether that old stock was legitimate. Replacement terminals require a staff reset. Inventory and world saves are not one crash-atomic transaction.

## Verification

Use Lua 5.1 and luac on PATH, from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File guspuffy-atf-patches/Verify-Lua.ps1
```

For vendor checks, pass the patched manifest-layout folder and the original Lifestyle media/lua folder. Inventory composition can additionally use the native ISInventoryPane.lua and LivestockPanelPlusEggs.lua files. Talis checks take its original media/lua folder.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File guspuffy-atf-patches/Verify-Lua.ps1 -VendorFixtures 'path/to/patched/mods' -LifestyleLuaSource 'path/to/Lifestyle/common/media/lua' -PZInventoryPane 'path/to/ISInventoryPane.lua' -LivestockEggHook 'path/to/LivestockPanelPlusEggs.lua' -TalisLuaSource 'path/to/Talis/42/media/lua'
```

The suites also run with PZ 42.21.0 Kahlua through tests/RunKahlua.java. Java tests include native parser weaving in both Storm transformer orders and JVM linkage without game initialization. Local validation uses JDK 25 and audited Storm 2.13.1 through an external init script; no dependency substitution is committed.

Live two-client actions, cancellation/reconnect, travel, claim updates, device removal and stock migration remain gameplay acceptance checks. No live deployment, FPS measurement or general cure for disappearing world objects is claimed.
