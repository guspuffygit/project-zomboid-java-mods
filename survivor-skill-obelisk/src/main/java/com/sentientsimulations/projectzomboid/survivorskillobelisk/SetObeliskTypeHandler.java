package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.OnClientCommand;
import zombie.characters.IsoPlayer;
import zombie.characters.skills.PerkFactory;

/**
 * Handles the {@code SurvivorSkillObelisk:setObeliskType} client command. Admin-only: persists a
 * skill-type label for the obelisk at the given world coordinates. {@code "None"} clears the type.
 *
 * <p>The admin check is enforced server-side regardless of UI gating — the Lua menu hides the
 * option for non-admins, but a hand-crafted packet shouldn't be able to mutate state either.
 */
public final class SetObeliskTypeHandler {

    private static final String NONE = "None";

    private SetObeliskTypeHandler() {}

    @OnClientCommand
    public static void onSetObeliskType(SetObeliskTypeCommand event) {
        IsoPlayer player = event.getPlayer();
        if (player == null) {
            LOGGER.warn("[SurvivorSkillObelisk] setObeliskType from null player; dropping");
            return;
        }
        String username = player.getUsername();
        long steamId = player.getSteamID();
        String accessLevel = player.getAccessLevel();
        if (accessLevel == null || !"admin".equalsIgnoreCase(accessLevel)) {
            LOGGER.warn(
                    "[SurvivorSkillObelisk] setObeliskType from non-admin {} ({}, role={});"
                            + " dropping",
                    username,
                    steamId,
                    accessLevel);
            return;
        }
        Integer x = event.getX();
        Integer y = event.getY();
        Integer z = event.getZ();
        if (x == null || y == null || z == null) {
            LOGGER.warn(
                    "[SurvivorSkillObelisk] setObeliskType from {} with missing coords"
                            + " (x={}, y={}, z={}); dropping",
                    username,
                    x,
                    y,
                    z);
            return;
        }
        String type = event.getType();
        if (type == null || type.isBlank()) {
            type = NONE;
        }
        if (!NONE.equals(type) && PerkFactory.Perks.FromString(type) == null) {
            LOGGER.warn(
                    "[SurvivorSkillObelisk] setObeliskType from {} with unknown perk '{}';"
                            + " dropping",
                    username,
                    type);
            return;
        }

        try (SurvivorSkillObeliskDatabase db =
                new SurvivorSkillObeliskDatabase(DeathEventHandler.getDbPath())) {
            SurvivorSkillObeliskRepository repo =
                    new SurvivorSkillObeliskRepository(db.getConnection());
            repo.upsertObeliskType(x, y, z, type, username, steamId, System.currentTimeMillis());
            LOGGER.info(
                    "[SurvivorSkillObelisk] setObeliskType: {} ({}) set obelisk at"
                            + " ({}, {}, {}) -> '{}'",
                    username,
                    steamId,
                    x,
                    y,
                    z,
                    type);
            ObeliskBroadcast.obeliskUpdated(x, y, z, type);
        } catch (Exception e) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] setObeliskType failed for {} ({}) at ({}, {}, {})"
                            + " -> '{}'",
                    username,
                    steamId,
                    x,
                    y,
                    z,
                    type,
                    e);
        }
    }
}
