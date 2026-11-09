package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import org.jetbrains.annotations.Nullable;
import zombie.characters.skills.PerkFactory;
import zombie.core.random.Rand;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;
import zombie.iso.IsoWorld;
import zombie.iso.objects.IsoThumpable;
import zombie.iso.sprite.IsoSprite;
import zombie.iso.sprite.IsoSpriteManager;
import zombie.network.GameServer;

/**
 * Places an obelisk from server Java, the way the brush tool places a solid moveable, and stores
 * its type in the same step; {@link #remove} undoes both. Other mods call them by reflection, so
 * their signatures are part of the mod's public surface; they return one of the {@code STATUS_*}
 * strings rather than an enum.
 *
 * <p>Main thread only. The type row is written before the method returns and no {@code
 * OnObjectAdded} event is fired, because {@link ObeliskLifecycleHandler} answers that event by
 * marking the square's row {@code None} on a worker thread, which would overwrite the type.
 */
public final class ObeliskPlacement {

    public static final String STATUS_PLACED = "placed";
    public static final String STATUS_PRESENT = "present";
    public static final String STATUS_UNLOADED = "unloaded";
    public static final String STATUS_NO_SPRITE = "no-sprite";
    public static final String STATUS_BAD_TYPE = "bad-type";
    public static final String STATUS_FAILED = "failed";
    public static final String STATUS_REMOVED = "removed";
    public static final String STATUS_ABSENT = "absent";

    public static final String SPRITE_PREFIX = "atf_obelisks_";
    public static final String SHEET = "atf_obelisks_lg_01_";
    public static final int COLOURS = 14;
    private static final int HEALTH = 1000;

    private ObeliskPlacement() {}

    /**
     * Makes sure the square at {@code x, y, z} holds an obelisk of {@code type}. A missing obelisk
     * is placed with a random colour; an obelisk already there keeps its colour. The type row is
     * upserted either way and every client is told. {@code type} is {@code None}, {@code Blessing}
     * {@code Extraction} or a perk id. Answers {@link #STATUS_UNLOADED} while the square's chunk is
     * not loaded, so the caller tries again later.
     */
    public static String ensure(int x, int y, int z, String type, String by) {
        String cleanType = type == null || type.isBlank() ? ObeliskTypes.NONE : type.trim();
        if (!isKnownType(cleanType)) {
            return STATUS_BAD_TYPE;
        }
        if (IsoWorld.instance == null || IsoWorld.instance.currentCell == null) {
            return STATUS_UNLOADED;
        }
        IsoGridSquare square = IsoWorld.instance.currentCell.getGridSquare(x, y, z);
        if (square == null) {
            return STATUS_UNLOADED;
        }
        boolean placed = false;
        if (findObelisk(square) == null) {
            String sprite = SHEET + Rand.Next(COLOURS);
            if (!IsoSpriteManager.instance.getNamedMap().containsKey(sprite)) {
                return STATUS_NO_SPRITE;
            }
            try {
                place(square, sprite);
            } catch (Throwable t) {
                LOGGER.error(
                        "[SurvivorSkillObelisk] placing {} at ({}, {}, {}) failed",
                        sprite,
                        x,
                        y,
                        z,
                        t);
                return STATUS_FAILED;
            }
            placed = true;
        }
        if (!storeType(x, y, z, cleanType, by)) {
            return STATUS_FAILED;
        }
        ObeliskBroadcast.obeliskUpdated(x, y, z, cleanType);
        LOGGER.info(
                "[SurvivorSkillObelisk] {} obelisk at ({}, {}, {}) typed '{}' by {}",
                placed ? "placed" : "kept",
                x,
                y,
                z,
                cleanType,
                by);
        return placed ? STATUS_PLACED : STATUS_PRESENT;
    }

    /**
     * Takes the obelisk off the square at {@code x, y, z}, drops its type row and tells every
     * client. A square without an obelisk only loses a stale type row. Answers {@link
     * #STATUS_REMOVED}, {@link #STATUS_ABSENT}, {@link #STATUS_UNLOADED} while the chunk is not
     * loaded, or {@link #STATUS_FAILED}. Main thread only, like {@link #ensure}.
     */
    public static String remove(int x, int y, int z, String by) {
        if (IsoWorld.instance == null || IsoWorld.instance.currentCell == null) {
            return STATUS_UNLOADED;
        }
        IsoGridSquare square = IsoWorld.instance.currentCell.getGridSquare(x, y, z);
        if (square == null) {
            return STATUS_UNLOADED;
        }
        IsoObject obelisk = findObelisk(square);
        if (obelisk != null) {
            try {
                square.transmitRemoveItemFromSquare(obelisk);
            } catch (Throwable t) {
                LOGGER.error(
                        "[SurvivorSkillObelisk] removing the obelisk at ({}, {}, {}) failed",
                        x,
                        y,
                        z,
                        t);
                return STATUS_FAILED;
            }
        }
        if (!dropType(x, y, z)) {
            return STATUS_FAILED;
        }
        ObeliskBroadcast.obeliskRemoved(x, y, z);
        LOGGER.info(
                "[SurvivorSkillObelisk] {} obelisk at ({}, {}, {}) by {}",
                obelisk != null ? "removed" : "no",
                x,
                y,
                z,
                by);
        return obelisk != null ? STATUS_REMOVED : STATUS_ABSENT;
    }

    public static boolean isKnownType(String type) {
        if (ObeliskTypes.NONE.equals(type)
                || ObeliskTypes.BLESSING.equals(type)
                || ObeliskTypes.EXTRACTION.equals(type)) {
            return true;
        }
        PerkFactory.Perk perk = PerkFactory.Perks.FromString(type);
        return perk != null && perk != PerkFactory.Perks.MAX && type.equals(perk.getId());
    }

    /** True for an obelisk object, lit or not. */
    public static boolean isObelisk(@Nullable IsoObject obj) {
        if (obj == null) {
            return false;
        }
        IsoSprite sprite = obj.getSprite();
        String name = sprite == null ? null : sprite.getName();
        return name != null && name.startsWith(SPRITE_PREFIX) && !name.contains("_on_");
    }

    public static @Nullable IsoObject findObelisk(IsoGridSquare square) {
        for (int i = 0; i < square.getObjects().size(); i++) {
            IsoObject obj = square.getObjects().get(i);
            if (isObelisk(obj)) {
                return obj;
            }
        }
        return null;
    }

    private static void place(IsoGridSquare square, String sprite) {
        IsoThumpable obj = new IsoThumpable(square.getCell(), square, sprite, false);
        obj.setMaxHealth(HEALTH);
        obj.setHealth(HEALTH);
        obj.setThumpDmg(1);
        obj.setIsThumpable(true);
        obj.setBlockAllTheSquare(true);
        obj.setCanPassThrough(false);
        obj.setHoppable(false);
        obj.setBreakSound(IsoThumpable.GetBreakFurnitureSound(sprite));
        square.AddSpecialObject(obj);
        if (GameServer.server) {
            obj.transmitCompleteItemToClients();
        }
    }

    private static boolean dropType(int x, int y, int z) {
        try (SurvivorSkillObeliskDatabase db =
                new SurvivorSkillObeliskDatabase(DeathEventHandler.getDbPath())) {
            new SurvivorSkillObeliskRepository(db.getConnection()).deleteObeliskType(x, y, z);
            return true;
        } catch (Exception e) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] dropping the type row at ({}, {}, {}) failed",
                    x,
                    y,
                    z,
                    e);
            return false;
        }
    }

    private static boolean storeType(int x, int y, int z, String type, String by) {
        try (SurvivorSkillObeliskDatabase db =
                new SurvivorSkillObeliskDatabase(DeathEventHandler.getDbPath())) {
            new SurvivorSkillObeliskRepository(db.getConnection())
                    .upsertObeliskType(x, y, z, type, by, 0L, System.currentTimeMillis());
            return true;
        } catch (Exception e) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] storing type '{}' at ({}, {}, {}) failed",
                    type,
                    x,
                    y,
                    z,
                    e);
            return false;
        }
    }
}
