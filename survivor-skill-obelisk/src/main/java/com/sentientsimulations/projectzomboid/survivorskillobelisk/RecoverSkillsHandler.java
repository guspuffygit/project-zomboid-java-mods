package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.OnClientCommand;
import java.util.List;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;
import zombie.network.GameServer;

/**
 * Handles the {@code SurvivorSkillObelisk:recoverSkills} client command. Validates that the
 * requesting player actually owns the death row, loads each tracked progression slice from the
 * SQLite DB, filters / scales it per {@link SurvivorSkillObeliskConfig}, and ships a {@code
 * recoveredData} payload back to the client that applies it locally via the standard PZ APIs.
 */
public final class RecoverSkillsHandler {

    private static final String MODULE = "SurvivorSkillObelisk";
    private static final String REPLY_COMMAND = "recoveredData";

    private RecoverSkillsHandler() {}

    @OnClientCommand
    public static void onRecoverSkills(RecoverSkillsCommand event) {
        IsoPlayer player = event.getPlayer();
        if (player == null) {
            LOGGER.warn("[SurvivorSkillObelisk] recoverSkills from null player; dropping");
            return;
        }
        Long deathId = event.getDeathId();
        if (deathId == null) {
            LOGGER.warn(
                    "[SurvivorSkillObelisk] recoverSkills from {} with no id; dropping",
                    player.getUsername());
            return;
        }
        long steamId = player.getSteamID();
        String username = player.getUsername();
        if (username == null || username.isBlank()) {
            LOGGER.warn(
                    "[SurvivorSkillObelisk] recoverSkills from {} with no username; dropping",
                    steamId);
            return;
        }

        try (SurvivorSkillObeliskDatabase db =
                new SurvivorSkillObeliskDatabase(DeathEventHandler.getDbPath())) {
            SurvivorSkillObeliskRepository repo =
                    new SurvivorSkillObeliskRepository(db.getConnection());

            SurvivorSkillObeliskRepository.DeathOwner owner = repo.findDeathOwner(deathId);
            if (owner == null) {
                LOGGER.warn(
                        "[SurvivorSkillObelisk] recoverSkills: death id={} not found (requested"
                                + " by {} / {})",
                        deathId,
                        username,
                        steamId);
                return;
            }
            if (owner.steamId() != steamId || !username.equals(owner.username())) {
                LOGGER.warn(
                        "[SurvivorSkillObelisk] recoverSkills: death id={} owner mismatch (db: {}"
                                + " / {} | request: {} / {})",
                        deathId,
                        owner.username(),
                        owner.steamId(),
                        username,
                        steamId);
                return;
            }

            KahluaTable reply = buildReply(repo, deathId);
            GameServer.sendServerCommand(player, MODULE, REPLY_COMMAND, reply);
        } catch (Exception e) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] recoverSkills failed for {} ({}) death id={}",
                    username,
                    steamId,
                    deathId,
                    e);
        }
    }

    /**
     * Build the payload the client will apply. Filtered server-side by the {@code SkillObelisk.*}
     * sandbox toggles, and XP is pre-scaled by {@code SkillObelisk.SkillRecoveryPercent} so the
     * client just adds whatever it receives.
     */
    private static KahluaTable buildReply(SurvivorSkillObeliskRepository repo, long deathId)
            throws Exception {
        KahluaTable reply = LuaManager.platform.newTable();

        if (SurvivorSkillObeliskConfig.isRecoverSkills()) {
            float percent = SurvivorSkillObeliskConfig.getSkillRecoveryPercent() / 100.0F;
            KahluaTable skills = LuaManager.platform.newTable();
            int i = 1;
            for (SurvivorSkillObeliskRepository.SkillRow row : repo.listSkillsByDeath(deathId)) {
                KahluaTable t = LuaManager.platform.newTable();
                t.rawset("perk", row.perk());
                t.rawset("xp", (double) (row.xp() * percent));
                skills.rawset(i++, t);
            }
            reply.rawset("skills", skills);
        }

        if (SurvivorSkillObeliskConfig.isRecoverRecipes()) {
            reply.rawset("recipes", stringList(repo.listRecipesByDeath(deathId)));
        }

        if (SurvivorSkillObeliskConfig.isRecoverSkillMagazines()) {
            reply.rawset("literature", stringList(repo.listReadLiteratureByDeath(deathId)));
        }

        if (SurvivorSkillObeliskConfig.isRecoverReadPrintMedia()) {
            reply.rawset("printMedia", stringList(repo.listReadPrintMediaByDeath(deathId)));
        }

        if (SurvivorSkillObeliskConfig.isRecoverWatchedMedia()) {
            KahluaTable media = LuaManager.platform.newTable();
            int i = 1;
            for (SurvivorSkillObeliskRepository.WatchedMediaRow row :
                    repo.listWatchedMediaByDeath(deathId)) {
                KahluaTable t = LuaManager.platform.newTable();
                t.rawset("mediaId", row.mediaId());
                t.rawset("mediaType", (double) row.mediaType());
                t.rawset("linesWatched", (double) row.linesWatched());
                t.rawset("lineCount", (double) row.lineCount());
                t.rawset("fullyWatched", row.fullyWatched());
                media.rawset(i++, t);
            }
            reply.rawset("watchedMedia", media);
        }

        if (SurvivorSkillObeliskConfig.isRecoverLearnedSongs()) {
            KahluaTable songs = LuaManager.platform.newTable();
            int i = 1;
            for (SurvivorSkillObeliskRepository.LearnedSongRow row :
                    repo.listLearnedSongsByDeath(deathId)) {
                KahluaTable t = LuaManager.platform.newTable();
                t.rawset("instrument", row.instrument());
                t.rawset("name", row.songName());
                if (row.sound() != null) {
                    t.rawset("sound", row.sound());
                }
                songs.rawset(i++, t);
            }
            reply.rawset("learnedSongs", songs);
        }

        if (SurvivorSkillObeliskConfig.isRecoverAmbitions()) {
            KahluaTable ambitions = LuaManager.platform.newTable();
            int i = 1;
            for (SurvivorSkillObeliskRepository.AmbitionRow row :
                    repo.listAmbitionsByDeath(deathId)) {
                KahluaTable t = LuaManager.platform.newTable();
                t.rawset("name", row.name());
                if (row.category() != null) {
                    t.rawset("cat", row.category());
                }
                t.rawset("completed", row.completed());
                t.rawset("isActive", row.isActive());
                t.rawset("isPassive", row.isPassive());
                for (int g = 0; g < 6; g++) {
                    if (row.goals()[g] != null) {
                        t.rawset("goal" + (g + 1), row.goals()[g]);
                    }
                    if (row.goalProgress()[g] != null) {
                        t.rawset("goal" + (g + 1) + "progress", row.goalProgress()[g]);
                    }
                }
                ambitions.rawset(i++, t);
            }
            reply.rawset("ambitions", ambitions);
        }

        return reply;
    }

    private static KahluaTable stringList(List<String> values) {
        KahluaTable t = LuaManager.platform.newTable();
        int i = 1;
        for (String v : values) {
            if (v != null) {
                t.rawset(i++, v);
            }
        }
        return t;
    }
}
