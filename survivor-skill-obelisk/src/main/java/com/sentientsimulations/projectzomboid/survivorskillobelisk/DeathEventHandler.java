package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.lua.OnCharacterDeathEvent;
import java.io.File;
import zombie.ZomboidFileSystem;
import zombie.characters.IsoPlayer;
import zombie.characters.skills.PerkFactory;

/**
 * Persists a snapshot of a player's progression to SQLite when they die. Mirrors the
 * attacker-attribution / extraction approach used by the extra-logging mod's DeathEventHandler, but
 * writes to a database rather than a log file.
 *
 * <p>Today it records identity + perk levels/XP. Journals read and VHS watched are tracked
 * separately once the source data on {@link IsoPlayer} is mapped out.
 */
public final class DeathEventHandler {

    private static final String DB_FILENAME = "survivor_skill_obelisk.db";

    private DeathEventHandler() {}

    static String getDbPath() {
        File dbFile = ZomboidFileSystem.instance.getFileInCurrentSave(DB_FILENAME);
        return dbFile.getAbsolutePath();
    }

    public static void onCharacterDeath(OnCharacterDeathEvent event) {
        if (!(event.character instanceof IsoPlayer player)) {
            return;
        }
        try {
            recordDeath(player);
            LOGGER.info(
                    "[SurvivorSkillObelisk] Recorded death of player: {}", player.getUsername());
        } catch (Exception e) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] Failed to record death for player: {}",
                    player.getUsername(),
                    e);
        }
    }

    private static void recordDeath(IsoPlayer player) throws Exception {
        try (SurvivorSkillObeliskDatabase db = new SurvivorSkillObeliskDatabase(getDbPath())) {
            SurvivorSkillObeliskRepository repo =
                    new SurvivorSkillObeliskRepository(db.getConnection());

            long deathId =
                    repo.insertDeath(
                            System.currentTimeMillis(),
                            player.getUsername(),
                            player.getSteamID(),
                            player.getDescriptor().getForename(),
                            player.getDescriptor().getSurname(),
                            player.getHoursSurvived(),
                            player.getZombieKills(),
                            player.getX(),
                            player.getY(),
                            player.getZ());

            for (PerkFactory.Perk perk : PerkFactory.PerkList) {
                int level = player.getPerkLevel(perk);
                float xp = player.getXp().getXP(perk);
                if (level > 0 || xp > 0) {
                    repo.insertSkill(deathId, perk.getName(), level, xp);
                }
            }
        }
    }
}
