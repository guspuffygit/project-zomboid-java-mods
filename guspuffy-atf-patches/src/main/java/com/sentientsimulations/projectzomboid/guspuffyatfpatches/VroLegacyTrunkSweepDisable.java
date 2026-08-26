package com.sentientsimulations.projectzomboid.guspuffyatfpatches;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.EveryOneMinuteEvent;
import java.util.ArrayList;
import se.krka.kahlua.vm.LuaClosure;
import zombie.Lua.LuaEventManager;
import zombie.network.GameServer;

/**
 * Unregisters the Vehicle Repair Overhaul "SFC Fix Pack" legacy trunk-capacity sweep from {@code
 * EveryOneMinute}.
 *
 * <p>{@code VRO_TrunkCapacity.lua} ships two things. The live fix — reapplying {@code
 * doInventoryItemStats} after each VRO {@code doFix}, which VRO itself omits — is what the file
 * exists for and stays fully intact. Bolted onto it is a one-time migration for vehicles whose
 * container capacity was already frozen in the save before that fix landed, guarded by a {@code
 * local ENABLE_LEGACY_SWEEP = true} the author left switched on.
 *
 * <p>The migration has long since converged on ATF, but it still runs every in-game minute (~6.2 s
 * of wall clock) and walks every loaded vehicle and every one of its parts: at 1,742 loaded
 * vehicles that is roughly half a million Lua-to-Java calls per pass. Profiled live on ATF prod
 * 2026-08-25 at <b>13.89% of the entire server main thread</b> — and it is not steady overhead but
 * a stall, with main thread over 60% Lua for about a second every 6.2 seconds. Nearly all of that
 * cost is Kahlua's reflective dispatch bridge, not the getters being called, so it does not shrink
 * as the sweep finds less work to do.
 *
 * <p>Everything in that file is {@code local}, so there is no global table to monkey-patch from Lua
 * and no way to reach the {@code ENABLE_LEGACY_SWEEP} upvalue by a stable index. What is reachable
 * is the registration itself: drop the closure out of the event's callback list.
 *
 * <p><b>Removing it costs nothing.</b> The minute handler does exactly two things — call {@code
 * drainQueue()} and then run the sweep — and {@code drainQueue} is separately registered on {@code
 * Events.OnTick} by the same file, so the post-repair correction keeps running every tick either
 * way. Verified against the live server: {@code EveryOneMinute[1] = onEveryOneMinute} and {@code
 * OnTick[1] = drainQueue}, both from {@code VRO_TrunkCapacity.lua}.
 *
 * <p>Timing: Storm bridges Lua events from {@code TriggerEventAdvice}, an {@code OnMethodEnter}
 * advice on {@code LuaEventManager.triggerEvent}, so this handler runs before {@code Event.trigger}
 * walks the callback list. The list is not being iterated when we mutate it, and the sweep never
 * gets a single pass in. Re-checking on every trigger rather than once at startup means a Lua
 * hot-reload that re-runs the file's {@code Events.EveryOneMinute.Add} is caught on the next
 * minute; steady-state cost is one scan of a five-element list per 6.2 s.
 *
 * <p>If VRO ever ships the sweep disabled or drops it, this becomes a no-op scan and can be
 * deleted.
 */
public final class VroLegacyTrunkSweepDisable {

    private static final String EVENT = "EveryOneMinute";
    private static final String SOURCE_FILE = "VRO_TrunkCapacity.lua";
    private static final String CALLBACK_NAME = "onEveryOneMinute";

    private static int removalCount;

    private VroLegacyTrunkSweepDisable() {}

    @SubscribeEvent
    public static void onEveryOneMinute(EveryOneMinuteEvent event) {
        if (!GameServer.server) {
            return;
        }
        ArrayList<LuaClosure> callbacks = LuaEventManager.AddEvent(EVENT).callbacks;
        for (int n = callbacks.size() - 1; n >= 0; n--) {
            if (!isLegacySweep(callbacks.get(n))) {
                continue;
            }
            callbacks.remove(n);
            removalCount++;
            LOGGER.info(
                    "[GuspuffyAtfPatches] Removed VRO legacy trunk-capacity sweep ({}:{}) from {}"
                            + " (removal #{}); VRO's post-repair fix is unaffected and still runs"
                            + " on OnTick.",
                    SOURCE_FILE,
                    CALLBACK_NAME,
                    EVENT,
                    removalCount);
        }
    }

    private static boolean isLegacySweep(LuaClosure closure) {
        if (closure == null || closure.prototype == null) {
            return false;
        }
        return SOURCE_FILE.equals(closure.prototype.file)
                && CALLBACK_NAME.equals(closure.prototype.name);
    }
}
