--[[
Talis New Music's server runtime dominates ATF's main-thread Lua budget (~95%
of all server Lua time, roughly 9-16% of the entire main thread; profiled live
2026-08-04). The cost is its zombie music-device subsystem:

- NMServerMPZombieAssignmentFlow.onTick: every 10th tick, for EVERY online
  player, scans radius 24 - a 49x49 getGridSquare()/getMovingObjects() sweep
  (2,401 squares per player) hunting zombies to hand music devices to, plus a
  radius-14 fallback sweep per player every 90 ticks.
- NMServerZombieVisualTargetPublisher.onTick: a second per-player zombie scan
  (collectTargetRecordsForPlayer/NearbyRadius) every 90 ticks.

This patch disables the zombie-device feature on the server entirely:

1. NMZombieLiveStrategy.getLiveVisualStrategy is overridden to return a
   strategy name no executor recognizes. The assignment flow's own shouldRun()
   gate consults it at call time, so both its onTick and the closure
   Events.OnZombieUpdate captured at registration early-out, and
   NMServerMain's getActiveZombieExecutor() resolves to nil.
2. The visual-target publisher's canPublish() does NOT consult the strategy,
   so its onTick is no-opped directly - NMServerMain looks it up on the
   global table every tick.
3. The flow's own table fields are no-opped as belt-and-suspenders in case a
   future Talis update changes its gate semantics.

Vehicle/world radio playback (the mod's actual purpose) is untouched: track
scheduling, source refresh, registry ticks and client commands keep running.
Zombies just never get music devices assigned.

Applied on the first server tick so every Talis module is guaranteed loaded.
Nothing can scan before then: the flow's cadence counters start at tick 1 and
only fire on multiples of 10/90.
]]

if isClient() and not isServer() then
	return
end

local DISABLED_STRATEGY = "atf_patches_zombie_scans_disabled"

local function applyPatch()
	if not NMZombieLiveStrategy then
		print("[ATFPatches] Talis New Music not loaded; zombie-scan disable skipped.")
		return false
	end

	NMZombieLiveStrategy.getLiveVisualStrategy = function()
		return DISABLED_STRATEGY
	end

	if NMServerMPZombieAssignmentFlow then
		NMServerMPZombieAssignmentFlow.onTick = function() end
		NMServerMPZombieAssignmentFlow.onZombieUpdate = function() end
	end

	if NMServerZombieVisualTargetPublisher then
		NMServerZombieVisualTargetPublisher.onTick = function() end
	end

	print("[ATFPatches] Talis New Music server zombie scanning disabled (strategy=" .. DISABLED_STRATEGY .. ").")
	return true
end

local function onFirstTick()
	Events.OnTick.Remove(onFirstTick)
	applyPatch()
end

Events.OnTick.Add(onFirstTick)
