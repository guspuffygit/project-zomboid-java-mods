package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.lua.OnCharacterDeathEvent;
import java.io.File;
import java.util.ArrayList;
import java.util.List;
import zombie.ZomboidFileSystem;
import zombie.characters.IsoPlayer;
import zombie.characters.skills.PerkFactory;
import zombie.radio.ZomboidRadio;
import zombie.radio.media.MediaData;
import zombie.radio.media.RecordedMedia;

/**
 * Persists a snapshot of a player's progression to SQLite when they die. Mirrors the
 * attacker-attribution / extraction approach used by the extra-logging mod's DeathEventHandler, but
 * writes to a database rather than a log file.
 *
 * <p>Captured per death: identity + perk levels/XP, known recipes, read literature (with pages
 * read), read print media, and watched recorded media (VHS tapes / CDs).
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

            recordSkills(repo, deathId, player);
            recordRecipes(repo, deathId, player);
            recordReadLiterature(repo, deathId, player);
            recordReadPrintMedia(repo, deathId, player);
            recordWatchedMedia(repo, deathId, player);
        }
    }

    private static void recordSkills(
            SurvivorSkillObeliskRepository repo, long deathId, IsoPlayer player) throws Exception {
        for (PerkFactory.Perk perk : PerkFactory.PerkList) {
            int level = player.getPerkLevel(perk);
            float xp = player.getXp().getXP(perk);
            if (level > 0 || xp > 0) {
                repo.insertSkill(deathId, perk.getName(), level, xp);
            }
        }
    }

    /** Recipes the character has learned — most are taught by reading skill magazines. */
    private static void recordRecipes(
            SurvivorSkillObeliskRepository repo, long deathId, IsoPlayer player) throws Exception {
        for (String recipeName : player.getKnownRecipes()) {
            if (recipeName != null) {
                repo.insertRecipe(deathId, recipeName);
            }
        }
    }

    /** Skill books and recipe magazines the character has read, with pages-read progress. */
    private static void recordReadLiterature(
            SurvivorSkillObeliskRepository repo, long deathId, IsoPlayer player) throws Exception {
        for (String fullType : player.getReadLiterature()) {
            if (fullType != null) {
                repo.insertReadLiterature(deathId, fullType, player.getAlreadyReadPages(fullType));
            }
        }
    }

    /** Newspapers / print magazines the character has read. */
    private static void recordReadPrintMedia(
            SurvivorSkillObeliskRepository repo, long deathId, IsoPlayer player) throws Exception {
        for (String mediaId : player.getReadPrintMedia()) {
            if (mediaId != null) {
                repo.insertReadPrintMedia(deathId, mediaId);
            }
        }
    }

    /**
     * Recorded media (VHS tapes / CDs) the character has watched. Consumption is tracked per media
     * line on the character ({@code knownMediaLines}); there is no public getter, so we iterate the
     * global catalog and test each tape's lines against the player.
     */
    private static void recordWatchedMedia(
            SurvivorSkillObeliskRepository repo, long deathId, IsoPlayer player) throws Exception {
        ZomboidRadio radio = ZomboidRadio.getInstance();
        if (radio == null) {
            return;
        }
        RecordedMedia recordedMedia = radio.getRecordedMedia();
        if (recordedMedia == null) {
            return;
        }

        List<MediaData> catalog = new ArrayList<>();
        catalog.addAll(recordedMedia.getAllMediaForType((byte) 0)); // CDs
        catalog.addAll(recordedMedia.getAllMediaForType((byte) 1)); // VHS

        for (MediaData media : catalog) {
            int lineCount = media.getLineCount();
            int linesWatched = 0;
            for (int i = 0; i < lineCount; i++) {
                MediaData.MediaLineData line = media.getLine(i);
                if (line != null && player.isKnownMediaLine(line.getTextGuid())) {
                    linesWatched++;
                }
            }
            if (linesWatched == 0) {
                continue;
            }
            String title = media.hasTitle() ? media.getTranslatedTitle() : media.getTitleEN();
            repo.insertWatchedMedia(
                    deathId,
                    media.getId(),
                    media.getIndex(),
                    media.getCategory(),
                    media.getMediaType(),
                    title,
                    linesWatched,
                    lineCount,
                    recordedMedia.hasListenedToAll(player, media));
        }
    }
}
