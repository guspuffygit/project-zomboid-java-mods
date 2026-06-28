package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.OnDestroyIsoThumpableEvent;
import io.pzstorm.storm.event.lua.OnObjectAboutToBeRemovedEvent;
import io.pzstorm.storm.event.lua.OnObjectAddedEvent;
import io.pzstorm.storm.event.lua.OnTileRemovedEvent;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;
import zombie.iso.sprite.IsoSprite;

/**
 * Keeps the {@code obelisk_types} table in sync with the world: on placement, ensures a {@code
 * type='None'} row exists at the object's square; on any removal path, deletes the matching row so
 * an admin sledgehammer or destruction doesn't leave orphan rows. Subscribed to all four candidate
 * lifecycle events — they overlap (sledgehammer fires both {@code OnDestroyIsoThumpable} and a
 * subsequent {@code OnObjectAboutToBeRemoved}; in-place destruction fires both that and {@code
 * OnTileRemoved}) but the underlying DB ops are idempotent.
 */
public final class ObeliskLifecycleHandler {

    private static final String SPRITE_PREFIX = "survivor_skill_obelisk_";

    private ObeliskLifecycleHandler() {}

    @SubscribeEvent
    public static void onObjectAdded(OnObjectAddedEvent event) {
        handlePlacement(event.object);
    }

    @SubscribeEvent
    public static void onObjectAboutToBeRemoved(OnObjectAboutToBeRemovedEvent event) {
        handleRemoval(event.object);
    }

    @SubscribeEvent
    public static void onTileRemoved(OnTileRemovedEvent event) {
        handleRemoval(event.object);
    }

    @SubscribeEvent
    public static void onDestroyIsoThumpable(OnDestroyIsoThumpableEvent event) {
        handleRemoval(event.thumpableObject);
    }

    private static void handlePlacement(IsoObject obj) {
        if (!isObelisk(obj)) {
            return;
        }
        IsoGridSquare sq = obj.getSquare();
        if (sq == null) {
            LOGGER.warn(
                    "[SurvivorSkillObelisk] Obelisk placed but square is null; skipping DB upsert");
            return;
        }
        int x = sq.getX();
        int y = sq.getY();
        int z = sq.getZ();
        try (SurvivorSkillObeliskDatabase db =
                new SurvivorSkillObeliskDatabase(DeathEventHandler.getDbPath())) {
            SurvivorSkillObeliskRepository repo =
                    new SurvivorSkillObeliskRepository(db.getConnection());
            repo.markObeliskNone(x, y, z, System.currentTimeMillis());
            LOGGER.info(
                    "[SurvivorSkillObelisk] Obelisk placed at ({}, {}, {}); recorded as 'None'",
                    x,
                    y,
                    z);
            ObeliskBroadcast.obeliskUpdated(x, y, z, "None");
        } catch (Exception e) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] Failed to record obelisk placement at ({}, {}, {})",
                    x,
                    y,
                    z,
                    e);
        }
    }

    private static void handleRemoval(IsoObject obj) {
        if (!isObelisk(obj)) {
            return;
        }
        IsoGridSquare sq = obj.getSquare();
        if (sq == null) {
            LOGGER.warn(
                    "[SurvivorSkillObelisk] Obelisk removed but square is null; skipping DB"
                            + " delete");
            return;
        }
        int x = sq.getX();
        int y = sq.getY();
        int z = sq.getZ();
        try (SurvivorSkillObeliskDatabase db =
                new SurvivorSkillObeliskDatabase(DeathEventHandler.getDbPath())) {
            SurvivorSkillObeliskRepository repo =
                    new SurvivorSkillObeliskRepository(db.getConnection());
            repo.deleteObeliskType(x, y, z);
            LOGGER.info(
                    "[SurvivorSkillObelisk] Obelisk removed at ({}, {}, {}); DB row cleared",
                    x,
                    y,
                    z);
            ObeliskBroadcast.obeliskRemoved(x, y, z);
        } catch (Exception e) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] Failed to delete obelisk row at ({}, {}, {})",
                    x,
                    y,
                    z,
                    e);
        }
    }

    private static boolean isObelisk(IsoObject obj) {
        if (obj == null) {
            return false;
        }
        IsoSprite sprite = obj.getSprite();
        if (sprite == null) {
            return false;
        }
        String name = sprite.getName();
        return name != null && name.startsWith(SPRITE_PREFIX);
    }
}
