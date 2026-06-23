package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.OnClientCommand;
import java.util.List;
import java.util.Map;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;
import zombie.characters.skills.PerkFactory;
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
            applySkillsAuthoritatively(player, repo, deathId);
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
     * Drive each perk's XP to {@code (this character's creation-grant baseline XP) + (recovered
     * earned XP × recovery%)} by computing the delta from current and feeding it to {@code AddXP}.
     * The delta is negative when the live character has out-earned the recovery target — recovery
     * is a SET, not an ADD, so we walk the XP back down to the grant + recovered amount.
     *
     * <p>PZ's {@code NetworkPlayerManager} pushes a full {@code PlayerXp} packet to the owning
     * client every ~1s, which calls {@code IsoGameCharacter.XP.load()} (clears and rebuilds {@code
     * xpMap} + {@code perkList}) — so this single server-side write is enough; no client mirror
     * needed.
     *
     * <p>Why delta-via-AddXP instead of direct map writes: AddXP runs the level-up / level-down
     * loops that fire {@code LevelPerk} Lua events, which Lifestyles and other mods listen to for
     * downstream state (ambition progress, fitness/strength stat sync, etc). Direct {@code
     * xpMap.put} would skip those.
     *
     * <p>Why set instead of add-recovered: the DB stores XP with the dead character's creation
     * grant already subtracted (see {@link DeathEventHandler#computeXpToSave}). Adding the stored
     * amount on top of the live XP map double-counts whatever this character has earned since
     * respawn — a player who farmed some skill before reaching the obelisk would over-level.
     */
    private static void applySkillsAuthoritatively(
            IsoPlayer player, SurvivorSkillObeliskRepository repo, long deathId) throws Exception {
        if (!SurvivorSkillObeliskConfig.isRecoverSkills()) {
            LOGGER.info(
                    "[SurvivorSkillObelisk] recoverSkills: skill recovery disabled, skipping XP"
                            + " application for {} (death id={})",
                    player.getUsername(),
                    deathId);
            return;
        }
        float percent = SurvivorSkillObeliskConfig.getSkillRecoveryPercent() / 100.0F;
        Map<PerkFactory.Perk, Integer> grantedLevels =
                DeathEventHandler.grantedLevelsAtCreation(player);
        float totalDelta = 0f;
        int applied = 0;
        for (SurvivorSkillObeliskRepository.SkillRow row : repo.listSkillsByDeath(deathId)) {
            PerkFactory.Perk perk = PerkFactory.Perks.FromString(row.perk());
            if (perk == null || perk == PerkFactory.Perks.MAX) {
                LOGGER.debug(
                        "[SurvivorSkillObelisk] recoverSkills: skipping unknown perk '{}' for {}",
                        row.perk(),
                        player.getUsername());
                continue;
            }
            int grantedLevel = grantedLevels.getOrDefault(perk, 0);
            float baselineXp = grantedLevel > 0 ? perk.getTotalXpForLevel(grantedLevel) : 0f;
            float maxXp = perk.getTotalXpForLevel(10);
            float targetXp = Math.min(baselineXp + row.xp() * percent, maxXp);

            float beforeXp = player.getXp().getXP(perk);
            int beforeLevel = player.getPerkLevel(perk);
            float delta = targetXp - beforeXp;
            // Sub-XP noise isn't worth firing a LevelPerk pass over.
            if (Math.abs(delta) < 0.5f) {
                continue;
            }

            // doXPBoost=false bypasses trait/profession rate multipliers so the delta is applied
            // as a literal XP change (modulo the protein/strength tweak inside AddXP, which we
            // accept since recovery% is already a fudgeable knob). callLua/remote/haloText all
            // false: this is a restore, not earned XP — no Lua hooks, no halo floaters.
            player.getXp().AddXP(perk, delta, false, false, false, false);
            float afterXp = player.getXp().getXP(perk);
            int afterLevel = player.getPerkLevel(perk);
            totalDelta += afterXp - beforeXp;
            applied++;
            LOGGER.info(
                    "[SurvivorSkillObelisk] recoverSkills: {} {} -> level {}->{} ({} -> {} XP,"
                            + " delta={}) (stored earned={}, percent={}%, baseline grant level={})",
                    player.getUsername(),
                    perk.getName(),
                    beforeLevel,
                    afterLevel,
                    beforeXp,
                    afterXp,
                    delta,
                    row.xp(),
                    SurvivorSkillObeliskConfig.getSkillRecoveryPercent(),
                    grantedLevel);
        }
        LOGGER.info(
                "[SurvivorSkillObelisk] recoverSkills: applied {} perks, net {} XP delta for"
                        + " {} (death id={})",
                applied,
                totalDelta,
                player.getUsername(),
                deathId);
    }

    /**
     * Build the payload the client will apply. Filtered server-side by the {@code SkillObelisk.*}
     * sandbox toggles. Skills are not in the payload — they're applied server-side and synced down
     * via the periodic {@code PlayerXp} packet.
     */
    private static KahluaTable buildReply(SurvivorSkillObeliskRepository repo, long deathId)
            throws Exception {
        KahluaTable reply = LuaManager.platform.newTable();

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
                        t.rawset("goal" + (g + 1), decodeAmbitionValue(row.goals()[g]));
                    }
                    if (row.goalProgress()[g] != null) {
                        t.rawset(
                                "goal" + (g + 1) + "progress",
                                decodeAmbitionValue(row.goalProgress()[g]));
                    }
                }
                ambitions.rawset(i++, t);
            }
            reply.rawset("ambitions", ambitions);
        }

        return reply;
    }

    /**
     * Goals/progress are stored as TEXT to handle Lifestyles' heterogeneous slot types (number,
     * string flag, boolean). Restore the original Lua type so comparisons like {@code
     * ambt.goal1progress >= ambt.goal1} in LSAmbtActiveIncomplete don't blow up with {@code __le
     * not defined for operand} when the slot was numeric.
     */
    private static Object decodeAmbitionValue(String stored) {
        if ("true".equals(stored)) {
            return Boolean.TRUE;
        }
        if ("false".equals(stored)) {
            return Boolean.FALSE;
        }
        try {
            return Double.valueOf(stored);
        } catch (NumberFormatException ignored) {
            return stored;
        }
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
