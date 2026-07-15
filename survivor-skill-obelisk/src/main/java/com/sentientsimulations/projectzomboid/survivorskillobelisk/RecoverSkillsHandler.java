package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.OnClientCommand;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.OnTickEvent;
import java.sql.Connection;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.LinkedBlockingQueue;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;
import zombie.characters.skills.PerkFactory;
import zombie.network.GameServer;
import zombie.radio.ZomboidRadio;
import zombie.radio.media.MediaData;
import zombie.radio.media.RecordedMedia;

/**
 * Handles the {@code SurvivorSkillObelisk:recoverSkills} client command. Validates that the
 * requesting player actually owns the death row, loads each tracked progression slice from the
 * SQLite DB, filters / scales it per {@link SurvivorSkillObeliskConfig}, and ships a {@code
 * recoveredData} payload back to the client that applies it locally via the standard PZ APIs.
 *
 * <p>XP recovery is ADDITIVE with an anti-stacking ledger: the recovered earned XP (scaled by
 * recovery percent) is added on top of whatever the live character currently has, and the amounts
 * actually granted are persisted per player in the {@code recoveries} / {@code recovery_skills}
 * tables. Recovering a different death later first subtracts the previously granted amounts, so
 * chaining recoveries can never accumulate more than one death's worth of recovered XP — while XP
 * earned by playing since respawn (or since the last recovery) is always kept. Dying deletes the
 * ledger (see {@link DeathEventHandler}) because the new death snapshot already contains everything
 * the character held, recovered XP included.
 *
 * <p>Same two-thread split as {@link ListDeathsHandler}: the main thread validates basic packet
 * fields and enqueues, a daemon worker checks ownership and reads all recovery data, and the next
 * tick applies XP authoritatively to the live {@code IsoPlayer}, builds the Kahlua reply, and ships
 * it. The ledger write then goes back to the worker. A per-player in-flight guard rejects a second
 * recover request until the first one's ledger write lands, so two rapid requests can't both read
 * the pre-recovery ledger and double-grant.
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
            Integer obeliskZ,
            long deathEpoch) {}

    private record QueryResult(
            String obeliskType,
            List<SurvivorSkillObeliskRepository.SkillRow> skills,
            Map<String, Float> previousGrants,
            List<String> recipes,
            List<String> literature,
            List<String> printMedia,
            List<SurvivorSkillObeliskRepository.WatchedMediaRow> watchedMedia,
            List<SurvivorSkillObeliskRepository.LearnedSongRow> learnedSongs,
            List<SurvivorSkillObeliskRepository.AmbitionRow> ambitions) {}

    private record CompletedRequest(
            IsoPlayer player,
            long steamId,
            String username,
            long deathId,
            long deathEpoch,
            QueryResult result) {}

    private static final BlockingQueue<Runnable> WORK = new LinkedBlockingQueue<>();
    private static final ConcurrentLinkedQueue<CompletedRequest> COMPLETED =
            new ConcurrentLinkedQueue<>();

    /**
     * Players with a recovery mid-pipeline (query enqueued but ledger write not yet landed). A
     * request arriving while its owner is in here is dropped, otherwise both requests would read
     * the same pre-recovery ledger and each grant would be applied in full.
     */
    private static final Set<String> IN_FLIGHT = ConcurrentHashMap.newKeySet();

    /**
     * Bumped from the main thread on every player death ({@link #notifyDeath}). A recovery request
     * snapshots the epoch on arrival; if it changed by apply/write time the player died mid-flight,
     * so the XP apply and the ledger write are both dropped — the death handler is deleting the
     * ledger, and writing after that would charge the respawned character for XP it never received.
     */
    private static final ConcurrentHashMap<String, Long> DEATH_EPOCHS = new ConcurrentHashMap<>();

    static {
        Thread worker =
                new Thread(
                        RecoverSkillsHandler::workerLoop,
                        "SurvivorSkillObelisk-RecoverSkills-Worker");
        worker.setDaemon(true);
        worker.start();
    }

    private RecoverSkillsHandler() {}

    /** Called from the main thread when a player dies — invalidates any in-flight recovery. */
    static void notifyDeath(long steamId, String username) {
        DEATH_EPOCHS.merge(inFlightKey(steamId, username), 1L, Long::sum);
    }

    private static String inFlightKey(long steamId, String username) {
        return steamId + "|" + username;
    }

    private static long deathEpoch(long steamId, String username) {
        return DEATH_EPOCHS.getOrDefault(inFlightKey(steamId, username), 0L);
    }

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
        if (!IN_FLIGHT.add(inFlightKey(steamId, username))) {
            LOGGER.warn(
                    "[SurvivorSkillObelisk] recoverSkills from {} while a recovery is already in"
                            + " flight; dropping",
                    username);
            return;
        }
        PendingRequest req =
                new PendingRequest(
                        player,
                        steamId,
                        username,
                        deathId,
                        event.getX(),
                        event.getY(),
                        event.getZ(),
                        deathEpoch(steamId, username));
        WORK.offer(() -> queryTask(req));
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
            Runnable task;
            try {
                task = WORK.take();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            }
            try {
                task.run();
            } catch (Throwable t) {
                LOGGER.error(
                        "[SurvivorSkillObelisk] worker loop iteration failed: {}",
                        t.getMessage(),
                        t);
            }
        }
    }

    private static void queryTask(PendingRequest req) {
        QueryResult result = runQuery(req);
        if (result == null) {
            IN_FLIGHT.remove(inFlightKey(req.steamId(), req.username()));
            return;
        }
        COMPLETED.offer(
                new CompletedRequest(
                        req.player(),
                        req.steamId(),
                        req.username(),
                        req.deathId(),
                        req.deathEpoch(),
                        result));
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
            Map<String, Float> previousGrants =
                    SurvivorSkillObeliskConfig.isRecoverSkills()
                            ? repo.findRecoveryGrants(req.steamId(), req.username())
                            : Map.of();
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
                    previousGrants,
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
        String key = inFlightKey(done.steamId(), done.username());
        try {
            if (done.player().isDead()
                    || deathEpoch(done.steamId(), done.username()) != done.deathEpoch()) {
                LOGGER.info(
                        "[SurvivorSkillObelisk] recoverSkills: {} died while recovery of death"
                                + " id={} was in flight; dropping",
                        done.username(),
                        done.deathId());
                IN_FLIGHT.remove(key);
                return;
            }
            Map<String, Float> newGrants =
                    applySkillsAuthoritatively(done.player(), done.result(), done.deathId());
            applyRemainingAuthoritatively(done.player(), done.result());
            KahluaTable reply = buildReply(done.result());
            // If the player disconnected while the query was in-flight, sendServerCommand is a
            // no-op (it gates on PlayerToAddressMap).
            GameServer.sendServerCommand(done.player(), MODULE, REPLY_COMMAND, reply);
            if (newGrants != null) {
                WORK.offer(() -> writeGrantsTask(done, newGrants, key));
            } else {
                IN_FLIGHT.remove(key);
            }
        } catch (Throwable t) {
            IN_FLIGHT.remove(key);
            LOGGER.error(
                    "[SurvivorSkillObelisk] recoverSkills apply/reply failed for {} death id={}: {}",
                    done.username(),
                    done.deathId(),
                    t.getMessage(),
                    t);
        }
    }

    /**
     * Persist the ledger of what this recovery actually granted, replacing the previous one. The
     * epoch re-check narrows the window where a death lands between the main-thread apply and this
     * write: the death handler's worker is concurrently deleting the ledger, and writing ours after
     * its delete would charge the respawned character for XP it never received.
     */
    private static void writeGrantsTask(
            CompletedRequest done, Map<String, Float> newGrants, String key) {
        try {
            if (deathEpoch(done.steamId(), done.username()) != done.deathEpoch()) {
                LOGGER.info(
                        "[SurvivorSkillObelisk] recoverSkills: {} died before the recovery ledger"
                                + " for death id={} was written; dropping write",
                        done.username(),
                        done.deathId());
                return;
            }
            try (SurvivorSkillObeliskDatabase db =
                    new SurvivorSkillObeliskDatabase(DeathEventHandler.getDbPath())) {
                Connection conn = db.getConnection();
                conn.setAutoCommit(false);
                new SurvivorSkillObeliskRepository(conn)
                        .replaceRecovery(
                                done.steamId(),
                                done.username(),
                                done.deathId(),
                                System.currentTimeMillis(),
                                newGrants);
                conn.commit();
            }
        } catch (Exception e) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] recoverSkills: failed to write recovery ledger for {}"
                            + " death id={}",
                    done.username(),
                    done.deathId(),
                    e);
        } finally {
            IN_FLIGHT.remove(key);
        }
    }

    /**
     * Add each perk's recovered earned XP (scaled by recovery percent) on top of the live
     * character's current XP, minus whatever a previous recovery already granted, via {@code
     * AddXP}. XP earned by playing is never touched: for {@code previousGrant = 0} the delta is
     * pure addition; when switching to a different death the delta first walks back the old grant
     * (and can go negative for perks only the old death was strong in).
     *
     * <p>Returns the new ledger — per perk, the recovery-sourced XP now present in the character
     * (measured from what {@code AddXP} actually changed, so a level-10 clamp shrinks the recorded
     * grant too). {@code null} when skill recovery is disabled, meaning there is nothing to persist
     * and the existing ledger must be left alone.
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
     */
    private static Map<String, Float> applySkillsAuthoritatively(
            IsoPlayer player, QueryResult result, long deathId) {
        if (!SurvivorSkillObeliskConfig.isRecoverSkills()) {
            LOGGER.info(
                    "[SurvivorSkillObelisk] recoverSkills: skill recovery disabled, skipping XP"
                            + " application for {} (death id={})",
                    player.getUsername(),
                    deathId);
            return null;
        }
        float configPercent = SurvivorSkillObeliskConfig.getSkillRecoveryPercent() / 100.0F;
        String obeliskType = result.obeliskType();
        Map<String, Float> previousGrants = result.previousGrants();

        // Union of the death's saved perks and the previous ledger's perks: DeathEventHandler
        // saves every perk, but a ledger written under a different mod list can hold perks this
        // death lacks — their old grant still has to be walked back (savedXp = 0).
        Map<String, Float> savedByPerk = new LinkedHashMap<>();
        for (SurvivorSkillObeliskRepository.SkillRow row : result.skills()) {
            savedByPerk.put(row.perk(), row.xp());
        }
        for (String perkId : previousGrants.keySet()) {
            savedByPerk.putIfAbsent(perkId, 0f);
        }

        Map<String, Float> newGrants = new HashMap<>();
        float totalDelta = 0f;
        int applied = 0;
        for (Map.Entry<String, Float> saved : savedByPerk.entrySet()) {
            PerkFactory.Perk perk = PerkFactory.Perks.FromString(saved.getKey());
            if (perk == null || perk == PerkFactory.Perks.MAX) {
                LOGGER.debug(
                        "[SurvivorSkillObelisk] recoverSkills: skipping unknown perk '{}' for {}",
                        saved.getKey(),
                        player.getUsername());
                continue;
            }
            boolean obeliskMatch = isObeliskTypeMatch(obeliskType, perk.getId());
            float percent = obeliskMatch ? 1.0F : configPercent;
            float previousGrant = previousGrants.getOrDefault(saved.getKey(), 0f);

            float beforeXp = player.getXp().getXP(perk);
            int beforeLevel = player.getPerkLevel(perk);
            float targetXp =
                    computeAdditiveTargetXp(
                            perk, beforeXp, saved.getValue(), previousGrant, percent);
            float delta = targetXp - beforeXp;
            // Sub-XP noise isn't worth firing a LevelPerk pass over; the previous grant carries
            // forward unchanged so the ledger stays honest.
            if (Math.abs(delta) < 0.5f) {
                if (previousGrant > 0f) {
                    newGrants.put(saved.getKey(), previousGrant);
                }
                continue;
            }

            // doXPBoost=false bypasses trait/profession rate multipliers so the delta is applied
            // as a literal XP change (modulo the protein/strength tweak inside AddXP, which we
            // accept since recovery% is already a fudgeable knob). callLua/remote/haloText all
            // false: this is a restore, not earned XP — no Lua hooks, no halo floaters.
            player.getXp().AddXP(perk, delta, false, false, false, false);
            float afterXp = player.getXp().getXP(perk);
            int afterLevel = player.getPerkLevel(perk);
            // Ledger from the observed change, not the requested delta — if AddXP clamped or
            // tweaked it, the next recovery must subtract only what really landed.
            float newGrant = Math.max(0f, previousGrant + (afterXp - beforeXp));
            if (newGrant > 0f) {
                newGrants.put(saved.getKey(), newGrant);
            }
            totalDelta += afterXp - beforeXp;
            applied++;
            LOGGER.info(
                    "[SurvivorSkillObelisk] recoverSkills: {} {} -> level {}->{} ({} -> {} XP,"
                            + " delta={}) (stored earned={}, percent={}%{}, previous grant={})",
                    player.getUsername(),
                    perk.getName(),
                    beforeLevel,
                    afterLevel,
                    beforeXp,
                    afterXp,
                    delta,
                    saved.getValue(),
                    Math.round(percent * 100),
                    obeliskMatch ? " [obelisk type override]" : "",
                    previousGrant);
        }
        LOGGER.info(
                "[SurvivorSkillObelisk] recoverSkills: applied {} perks, net {} XP delta for"
                        + " {} (death id={}, obelisk type={})",
                applied,
                totalDelta,
                player.getUsername(),
                deathId,
                obeliskType);
        return newGrants;
    }

    /**
     * Apply every non-XP recovery slice to the live server-side {@link IsoPlayer}. Skills go
     * through {@link #applySkillsAuthoritatively} (and rely on the ~1s {@code PlayerXp} packet to
     * mirror to the client); this method covers the rest — recipes, read literature, read print
     * media, watched media, learned songs, and ambitions — writing to the fields that {@code
     * IsoPlayer.save()} persists so a server restart doesn't wipe them.
     *
     * <p>The client still applies the same payload in {@code SurvivorSkillObeliskClient.lua
     * onRecoveredData} for immediate UI feedback — magazines flip to "read" instantly, no wait for
     * the next full-player sync. This is the authoritative copy: {@code
     * ServerPlayerDB.NetworkCharacterData} snapshots the server-side player, so this is what
     * survives a reboot. {@code transmitModData()} is called at the end so the client's session
     * copy of modData matches the freshly-mutated server copy without waiting for a sync.
     *
     * <p>Per-slice failures are logged and skipped so a single bad DB row can't tank the whole
     * apply.
     */
    private static void applyRemainingAuthoritatively(IsoPlayer player, QueryResult result) {
        boolean modDataMutated = false;
        if (result.recipes() != null) {
            for (String recipe : result.recipes()) {
                if (recipe == null) {
                    continue;
                }
                try {
                    player.learnRecipe(recipe);
                } catch (Throwable t) {
                    LOGGER.warn(
                            "[SurvivorSkillObelisk] recoverSkills: learnRecipe({}) failed for {}:"
                                    + " {}",
                            recipe,
                            player.getUsername(),
                            t.getMessage());
                }
            }
        }
        if (result.literature() != null) {
            for (String title : result.literature()) {
                if (title == null) {
                    continue;
                }
                try {
                    player.addReadLiterature(title);
                } catch (Throwable t) {
                    LOGGER.warn(
                            "[SurvivorSkillObelisk] recoverSkills: addReadLiterature({}) failed for"
                                    + " {}: {}",
                            title,
                            player.getUsername(),
                            t.getMessage());
                }
            }
        }
        if (result.printMedia() != null) {
            for (String id : result.printMedia()) {
                if (id == null) {
                    continue;
                }
                try {
                    player.addReadPrintMedia(id);
                } catch (Throwable t) {
                    LOGGER.warn(
                            "[SurvivorSkillObelisk] recoverSkills: addReadPrintMedia({}) failed for"
                                    + " {}: {}",
                            id,
                            player.getUsername(),
                            t.getMessage());
                }
            }
        }
        if (result.watchedMedia() != null) {
            applyWatchedMediaAuthoritatively(player, result.watchedMedia());
        }
        if (result.learnedSongs() != null && !result.learnedSongs().isEmpty()) {
            if (applyLearnedSongsAuthoritatively(player, result.learnedSongs())) {
                modDataMutated = true;
            }
        }
        if (result.ambitions() != null && !result.ambitions().isEmpty()) {
            if (applyAmbitionsAuthoritatively(player, result.ambitions())) {
                modDataMutated = true;
            }
        }
        if (modDataMutated) {
            try {
                player.transmitModData();
            } catch (Throwable t) {
                LOGGER.warn(
                        "[SurvivorSkillObelisk] recoverSkills: transmitModData failed for {}: {}",
                        player.getUsername(),
                        t.getMessage());
            }
        }
    }

    /**
     * Mirror the client's {@code applyWatchedMedia}: only fully-watched entries restore, and each
     * one adds every line GUID from the resolved {@link MediaData} to {@code knownMediaLines}. We
     * don't snapshot per-line GUIDs at death time, so partial-watch state is intentionally lost.
     */
    private static void applyWatchedMediaAuthoritatively(
            IsoPlayer player, List<SurvivorSkillObeliskRepository.WatchedMediaRow> watched) {
        ZomboidRadio radio = ZomboidRadio.getInstance();
        if (radio == null) {
            return;
        }
        RecordedMedia recorded = radio.getRecordedMedia();
        if (recorded == null) {
            return;
        }
        for (SurvivorSkillObeliskRepository.WatchedMediaRow row : watched) {
            if (row.mediaId() == null || !row.fullyWatched()) {
                continue;
            }
            try {
                MediaData media = recorded.getMediaData(row.mediaId());
                if (media == null) {
                    continue;
                }
                for (int i = 0; i < media.getLineCount(); i++) {
                    MediaData.MediaLineData line = media.getLine(i);
                    if (line != null && line.getTextGuid() != null) {
                        player.addKnownMediaLine(line.getTextGuid());
                    }
                }
            } catch (Throwable t) {
                LOGGER.warn(
                        "[SurvivorSkillObelisk] recoverSkills: watched media {} failed for {}: {}",
                        row.mediaId(),
                        player.getUsername(),
                        t.getMessage());
            }
        }
    }

    /**
     * Mirror the client's {@code applyLearnedSongs}: for each row, upsert into {@code
     * modData[instrument .. "LearnedTracks"]}. The list is a Kahlua array of {@code {name, sound}}
     * tables; skip rows whose {@code name} is already present so re-recoveries don't duplicate.
     * Returns whether anything was written — the caller uses that to decide whether to {@code
     * transmitModData}.
     */
    private static boolean applyLearnedSongsAuthoritatively(
            IsoPlayer player, List<SurvivorSkillObeliskRepository.LearnedSongRow> songs) {
        KahluaTable modData = player.getModData();
        if (modData == null) {
            return false;
        }
        boolean mutated = false;
        for (SurvivorSkillObeliskRepository.LearnedSongRow row : songs) {
            if (row.instrument() == null || row.songName() == null) {
                continue;
            }
            try {
                String key = row.instrument() + "LearnedTracks";
                KahluaTable list;
                Object listObj = modData.rawget(key);
                if (listObj instanceof KahluaTable existingList) {
                    list = existingList;
                } else {
                    list = LuaManager.platform.newTable();
                    modData.rawset(key, list);
                    mutated = true;
                }
                boolean alreadyPresent = false;
                int len = list.len();
                for (int i = 1; i <= len; i++) {
                    Object entry = list.rawget(i);
                    if (entry instanceof KahluaTable existingRow
                            && row.songName().equals(existingRow.rawget("name"))) {
                        alreadyPresent = true;
                        break;
                    }
                }
                if (!alreadyPresent) {
                    KahluaTable newEntry = LuaManager.platform.newTable();
                    newEntry.rawset("name", row.songName());
                    if (row.sound() != null) {
                        newEntry.rawset("sound", row.sound());
                    }
                    list.rawset(list.len() + 1, newEntry);
                    mutated = true;
                }
            } catch (Throwable t) {
                LOGGER.warn(
                        "[SurvivorSkillObelisk] recoverSkills: learned song {}/{} failed for {}:"
                                + " {}",
                        row.instrument(),
                        row.songName(),
                        player.getUsername(),
                        t.getMessage());
            }
        }
        return mutated;
    }

    /**
     * Mirror the client's {@code applyAmbitions}: upsert each row into {@code
     * modData.Ambitions[row.name]}, keyed by name. Numeric goal-progress values are scaled by the
     * configured recovery percent (matching client behavior — see the note in
     * SurvivorSkillObeliskClient.lua). Booleans and string flags pass through verbatim. {@code
     * completed}/{@code isActive}/{@code isPassive} follow the client's OR-merge: true from the
     * saved row wins, otherwise fall back to what was already there (default false).
     */
    private static boolean applyAmbitionsAuthoritatively(
            IsoPlayer player, List<SurvivorSkillObeliskRepository.AmbitionRow> ambitions) {
        KahluaTable modData = player.getModData();
        if (modData == null) {
            return false;
        }
        KahluaTable ambitionsTable;
        Object ambitionsObj = modData.rawget("Ambitions");
        if (ambitionsObj instanceof KahluaTable existing) {
            ambitionsTable = existing;
        } else {
            ambitionsTable = LuaManager.platform.newTable();
            modData.rawset("Ambitions", ambitionsTable);
        }
        boolean mutated = false;
        float percent = SurvivorSkillObeliskConfig.getSkillRecoveryPercent() / 100.0F;
        for (SurvivorSkillObeliskRepository.AmbitionRow row : ambitions) {
            if (row.name() == null) {
                continue;
            }
            try {
                KahluaTable existingRow;
                Object existingObj = ambitionsTable.rawget(row.name());
                if (existingObj instanceof KahluaTable table) {
                    existingRow = table;
                } else {
                    existingRow = LuaManager.platform.newTable();
                }
                existingRow.rawset("name", row.name());
                if (row.category() != null) {
                    existingRow.rawset("cat", row.category());
                }
                existingRow.rawset(
                        "completed",
                        row.completed() || truthyBool(existingRow.rawget("completed")));
                existingRow.rawset(
                        "isActive", row.isActive() || truthyBool(existingRow.rawget("isActive")));
                existingRow.rawset(
                        "isPassive",
                        row.isPassive() || truthyBool(existingRow.rawget("isPassive")));
                for (int g = 0; g < 6; g++) {
                    String goalKey = "goal" + (g + 1);
                    String progressKey = goalKey + "progress";
                    if (row.goals()[g] != null) {
                        existingRow.rawset(goalKey, decodeAmbitionValue(row.goals()[g]));
                    }
                    if (row.goalProgress()[g] != null) {
                        Object value = decodeAmbitionValue(row.goalProgress()[g]);
                        if (value instanceof Double d) {
                            existingRow.rawset(progressKey, d * percent);
                        } else {
                            existingRow.rawset(progressKey, value);
                        }
                    }
                }
                ambitionsTable.rawset(row.name(), existingRow);
                mutated = true;
            } catch (Throwable t) {
                LOGGER.warn(
                        "[SurvivorSkillObelisk] recoverSkills: ambition {} failed for {}: {}",
                        row.name(),
                        player.getUsername(),
                        t.getMessage());
            }
        }
        return mutated;
    }

    private static boolean truthyBool(Object o) {
        return o instanceof Boolean b && b;
    }

    /**
     * Pure math: the XP we drive the live character's perk to. Additive — the recovered earned XP
     * (scaled by {@code percent}) lands on top of {@code currentXp}, after subtracting {@code
     * previousGrantXp} (what an earlier recovery already contributed, so switching deaths swaps the
     * grant instead of stacking it). Clamped to {@code [0, level-10 XP]}; XP the player earned by
     * playing always survives because it is part of {@code currentXp} and never subtracted.
     */
    static float computeAdditiveTargetXp(
            PerkFactory.Perk perk,
            float currentXp,
            float savedXp,
            float previousGrantXp,
            float percent) {
        float target = currentXp + savedXp * percent - previousGrantXp;
        float maxXp = perk.getTotalXpForLevel(10);
        return Math.max(0f, Math.min(target, maxXp));
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
     *
     * <p>Same slices are also written server-side by {@link #applyRemainingAuthoritatively}; this
     * reply is a client-only fast-path for immediate UI feedback ("Skills recovered" halo,
     * magazines flip to "read" without waiting for the next full player sync). The server-side
     * write is the authoritative one — it's what {@code ServerPlayerDB} snapshots on save.
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
