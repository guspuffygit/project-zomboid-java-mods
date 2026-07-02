package com.sentientsimulations.projectzomboid.survivorlootrespawn;

import zombie.SandboxOptions;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;
import zombie.iso.IsoWorld;
import zombie.iso.areas.SafeHouse;
import zombie.iso.objects.IsoCompost;
import zombie.iso.objects.IsoDeadBody;
import zombie.iso.objects.IsoThumpable;
import zombie.iso.zones.Zone;
import zombie.network.GameServer;
import zombie.network.ServerOptions;

/**
 * Mirrors the per-square and per-object eligibility checks that vanilla {@code
 * zombie.LootRespawn.respawnInChunk} applies before reroling a container. The mod fully replaces
 * vanilla's respawn loop (via the {@code getRespawnInterval}→0 advice in {@code LootRespawnPatch}),
 * so these gates must be re-asserted by the mod or they are gone.
 *
 * <p>Intentionally omitted: the {@code SeenHoursPreventLootRespawn} predicate (out of scope) and a
 * respawn-time re-check of the object class (the stored {@code containerType} string compare is the
 * accepted guard).
 */
public final class VanillaLootRespawnGate {

    private VanillaLootRespawnGate() {}

    public static boolean passesSquareGate(IsoGridSquare sq) {
        // Map zones exist only at z=0 (Zone.contains rejects any other z), and vanilla
        // respawnInChunk evaluates this gate on the ground-floor square then applies the verdict
        // to the whole column. Resolve the column's z=0 zone — sq.getZone() is null on every
        // square above (or below) ground, which silently exempted all non-ground floors.
        Zone zone = IsoWorld.instance.getMetaGrid().getZoneAt(sq.getX(), sq.getY(), 0);
        if (zone == null) {
            return false;
        }
        String type = zone.getType();
        if (!"TownZone".equals(type) && !"TownZones".equals(type) && !"TrailerPark".equals(type)) {
            return false;
        }
        if (SandboxOptions.instance.constructionPreventsLootRespawn.getValue()
                && zone.haveConstruction) {
            return false;
        }
        if (GameServer.server
                && ServerOptions.instance.safehousePreventsLootRespawn.getValue()
                && SafeHouse.getSafeHouse(sq) != null) {
            return false;
        }
        return true;
    }

    public static boolean isExcludedObject(IsoObject obj) {
        return obj instanceof IsoThumpable
                || obj instanceof IsoDeadBody
                || obj instanceof IsoCompost;
    }
}
