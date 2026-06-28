package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.OnClientCommand;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.OnTickEvent;
import java.sql.Connection;
import java.util.List;
import java.util.Map;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.LinkedBlockingQueue;
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
 *
 * <p>Same two-thread split as {@link ListDeathsHandler}: the main thread validates basic packet
 * fields and enqueues, a daemon worker checks ownership and reads all recovery data, and the next
 * tick applies XP authoritatively to the live {@code IsoPlayer}, builds the Kahlua reply, and ships
 * it. XP application and Kahlua construction stay on the main thread; the worker only handles plain
 * Java records.
 */
public final class RecoverSkillsHandler {

    private static final String MODULE = "SurvivorSkillObelisk";
    private static final String REPLY_COMMAND = "recoveredData";
    private static final String NONE_TYPE = "None";

    private record PendingRequest(
            IsoPlayer player,
            long steamId,
            String username,
            long deathId,
            Integer obeliskX,
            Integer obeliskY,
            Integer obeliskZ) {}

    private record QueryResult(
            String obeliskType,
            List<SurvivorSkillObeliskRepository.SkillRow> skills,
            List<String> recipes,
            List<String> literature,
            List<String> printMedia,
            List<SurvivorSkillObeliskRepository.WatchedMediaRow> watchedMedia,
            List<SurvivorSkillObeliskRepository.LearnedSongRow> learnedSongs,
            List<SurvivorSkillObeliskRepository.AmbitionRow> ambitions) {}

    private record CompletedRequest(
            IsoPlayer player, String username, long deathId, QueryResult result) {}

    private static final BlockingQueue<PendingRequest> PENDING = new LinkedBlockingQueue<>();
    private static final ConcurrentLinkedQueue<CompletedRequest> COMPLETED =
            new ConcurrentLinkedQueue<>();

    static {
        Thread worker =
                new Thread(
                        RecoverSkillsHandler::workerLoop,
                        "SurvivorSkillObelisk-RecoverSkills-Worker");
        worker.setDaemon(true);
        worker.start();
    }

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
        PENDING.offer(
                new PendingRequest(
                        player,
                        steamId,
                        username,
                        deathId,
                        event.getX(),
                        event.getY(),
                        event.getZ()));
    }

    @SubscribeEvent
    public static void onTick(OnTickEvent event) {
        CompletedRequest done;
        while ((done = COMPLETED.poll()) != null) {
            applyAndReply(done);
        }
    }

    private static void workerLoop() {
        while (true) {
            PendingRequest req;
            try {
                req = PENDING.take();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            }
            try {
                QueryResult result = runQuery(req);
                if (result != null) {
                    COMPLETED.offer(
                            new CompletedRequest(
                                    req.player(), req.username(), req.deathId(), result));
                }
            } catch (Throwable t) {
                LOGGER.error(
                        "[SurvivorSkillObelisk] worker loop iteration failed for {} ({}) death"
                                + " id={}: {}",
                        req.username(),
                        req.steamId(),
                        req.deathId(),
                        t.getMessage(),
                        t);
            }
        }
    }

    private static QueryResult runQuery(PendingRequest req) {
        try (SurvivorSkillObeliskDatabase db =
                new SurvivorSkillObeliskDatabase(DeathEventHandler.getDbPath())) {
            Connection conn = db.getConnection();
            // Bracket all reads in one transaction so SQLite skips the implicit BEGIN/COMMIT
            // (and SHARED-lock acquire/release) it would otherwise run per statement.
            conn.setAutoCommit(false);
            SurvivorSkillObeliskRepository repo = new SurvivorSkillObeliskRepository(conn);

            SurvivorSkillObeliskRepository.DeathOwner owner = repo.findDeathOwner(req.deathId());
            if (owner == null) {
                LOGGER.warn(
                        "[SurvivorSkillObelisk] recoverSkills: death id={} not found (requested"
                                + " by {} / {})",
                        req.deathId(),
                        req.username(),
                        req.steamId());
                conn.commit();
                return null;
            }
            if (owner.steamId() != req.steamId() || !req.username().equals(owner.username())) {
                LOGGER.warn(
                        "[SurvivorSkillObelisk] recoverSkills: death id={} owner mismatch (db: {}"
                                + " / {} | request: {} / {})",
                        req.deathId(),
                        owner.username(),
                        owner.steamId(),
                        req.username(),
                        req.steamId());
                conn.commit();
                return null;
            }

            String obeliskType = resolveObeliskType(repo, req);
            List<SurvivorSkillObeliskRepository.SkillRow> skills =
                    SurvivorSkillObeliskConfig.isRecoverSkills()
                            ? repo.listSkillsByDeath(req.deathId())
                            : List.of();
            List<String> recipes =
                    SurvivorSkillObeliskConfig.isRecoverRecipes()
                            ? repo.listRecipesByDeath(req.deathId())
                            : null;
            List<String> literature =
                    SurvivorSkillObeliskConfig.isRecoverSkillMagazines()
                            ? repo.listReadLiteratureByDeath(req.deathId())
                            : null;
            List<String> printMedia =
                    SurvivorSkillObeliskConfig.isRecoverReadPrintMedia()
                            ? repo.listReadPrintMediaByDeath(req.deathId())
                            : null;
            List<SurvivorSkillObeliskRepository.WatchedMediaRow> watchedMedia =
                    SurvivorSkillObeliskConfig.isRecoverWatchedMedia()
                            ? repo.listWatchedMediaByDeath(req.deathId())
                            : null;
            List<SurvivorSkillObeliskRepository.LearnedSongRow> learnedSongs =
                    SurvivorSkillObeliskConfig.isRecoverLearnedSongs()
                            ? repo.listLearnedSongsByDeath(req.deathId())
                            : null;
            List<SurvivorSkillObeliskRepository.AmbitionRow> ambitions =
                    SurvivorSkillObeliskConfig.isRecoverAmbitions()
                            ? repo.listAmbitionsByDeath(req.deathId())
                            : null;
            conn.commit();
            return new QueryResult(
                    obeliskType,
                    skills,
                    recipes,
                    literature,
                    printMedia,
                    watchedMedia,
                    learnedSongs,
                    ambitions);
        } catch (Exception e) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] recoverSkills failed for {} ({}) death id={}",
                    req.username(),
                    req.steamId(),
                    req.deathId(),
                    e);
            return null;
        }
    }

    private static String resolveObeliskType(
            SurvivorSkillObeliskRepository repo, PendingRequest req) throws Exception {
        if (req.obeliskX() == null || req.obeliskY() == null || req.obeliskZ() == null) {
            return NONE_TYPE;
        }
        String stored = repo.findObeliskType(req.obeliskX(), req.obeliskY(), req.obeliskZ());
        return (stored == null || stored.isBlank()) ? NONE_TYPE : stored;
    }

    private static void applyAndReply(CompletedRequest done) {
        try {
            applySkillsAuthoritatively(done.player(), done.result(), done.deathId());
            KahluaTable reply = buildReply(done.result());
            // If the player disconnected while the query was in-flight, sendServerCommand is a
            // no-op (it gates on PlayerToAddressMap).
            GameServer.sendServerCommand(done.player(), MODULE, REPLY_COMMAND, reply);
        } catch (Throwable t) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] recoverSkills apply/reply failed for {} death id={}: {}",
                    done.username(),
                    done.deathId(),
                    t.getMessage(),
                    t);
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
            IsoPlayer player, QueryResult result, long deathId) {
        if (!SurvivorSkillObeliskConfig.isRecoverSkills()) {
            LOGGER.info(
                    "[SurvivorSkillObelisk] recoverSkills: skill recovery disabled, skipping XP"
                            + " application for {} (death id={})",
                    player.getUsername(),
                    deathId);
            return;
        }
        float configPercent = SurvivorSkillObeliskConfig.getSkillRecoveryPercent() / 100.0F;
        Map<PerkFactory.Perk, Integer> grantedLevels =
                DeathEventHandler.grantedLevelsAtCreation(player);
        String obeliskType = result.obeliskType();
        float totalDelta = 0f;
        int applied = 0;
        for (SurvivorSkillObeliskRepository.SkillRow row : result.skills()) {
            PerkFactory.Perk perk = PerkFactory.Perks.FromString(row.perk());
            if (perk == null || perk == PerkFactory.Perks.MAX) {
                LOGGER.debug(
                        "[SurvivorSkillObelisk] recoverSkills: skipping unknown perk '{}' for {}",
                        row.perk(),
                        player.getUsername());
                continue;
            }
            boolean obeliskMatch = isObeliskTypeMatch(obeliskType, perk.getId());
            float percent = obeliskMatch ? 1.0F : configPercent;
            int grantedLevel = grantedLevels.getOrDefault(perk, 0);
            float targetXp = computeRecoveryTargetXp(perk, row.xp(), grantedLevel, percent);

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
                            + " delta={}) (stored earned={}, percent={}%{}, baseline grant"
                            + " level={})",
                    player.getUsername(),
                    perk.getName(),
                    beforeLevel,
                    afterLevel,
                    beforeXp,
                    afterXp,
                    delta,
                    row.xp(),
                    Math.round(percent * 100),
                    obeliskMatch ? " [obelisk type override]" : "",
                    grantedLevel);
        }
        LOGGER.info(
                "[SurvivorSkillObelisk] recoverSkills: applied {} perks, net {} XP delta for"
                        + " {} (death id={}, obelisk type={})",
                applied,
                totalDelta,
                player.getUsername(),
                deathId,
                obeliskType);
    }

    /**
     * Pure math: the XP we drive the live character's perk to. For {@code savedXp = 0} this returns
     * the live baseline grant XP, which is the reset behavior — a perk the dead character never
     * earned anything in walks back to the live character's creation-grant level (typically 0 for
     * non-baseline perks, 5 for Strength/Fitness, plus any trait/profession boosts on top). For
     * {@code savedXp > 0} the recovered amount is added on top, scaled by {@code percent} and
     * clamped at level 10.
     */
    static float computeRecoveryTargetXp(
            PerkFactory.Perk perk, float savedXp, int grantedLevel, float percent) {
        float baselineXp = grantedLevel > 0 ? perk.getTotalXpForLevel(grantedLevel) : 0f;
        float maxXp = perk.getTotalXpForLevel(10);
        return Math.min(baselineXp + savedXp * percent, maxXp);
    }

    /**
     * True when the obelisk is bound to this specific perk — recovery uses 100% for the matched
     * perk regardless of the {@code Storm.SkillRecoveryPercent} config. A blank or {@code "None"}
     * obelisk type never matches.
     */
    static boolean isObeliskTypeMatch(String obeliskType, String perkId) {
        if (obeliskType == null || NONE_TYPE.equals(obeliskType)) {
            return false;
        }
        return obeliskType.equals(perkId);
    }

    /**
     * Build the payload the client will apply. Filtered server-side by the {@code SkillObelisk.*}
     * sandbox toggles (the worker leaves disabled slices as {@code null}). Skills are not in the
     * payload — they're applied server-side and synced down via the periodic {@code PlayerXp}
     * packet.
     */
    private static KahluaTable buildReply(QueryResult result) {
        KahluaTable reply = LuaManager.platform.newTable();

        if (result.recipes() != null) {
            reply.rawset("recipes", stringList(result.recipes()));
        }

        if (result.literature() != null) {
            reply.rawset("literature", stringList(result.literature()));
        }

        if (result.printMedia() != null) {
            reply.rawset("printMedia", stringList(result.printMedia()));
        }

        if (result.watchedMedia() != null) {
            KahluaTable media = LuaManager.platform.newTable();
            int i = 1;
            for (SurvivorSkillObeliskRepository.WatchedMediaRow row : result.watchedMedia()) {
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

        if (result.learnedSongs() != null) {
            KahluaTable songs = LuaManager.platform.newTable();
            int i = 1;
            for (SurvivorSkillObeliskRepository.LearnedSongRow row : result.learnedSongs()) {
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

        if (result.ambitions() != null) {
            KahluaTable ambitions = LuaManager.platform.newTable();
            int i = 1;
            for (SurvivorSkillObeliskRepository.AmbitionRow row : result.ambitions()) {
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
