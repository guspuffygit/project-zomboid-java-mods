package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.lua.OnCharacterDeathEvent;
import java.io.File;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaTableIterator;
import zombie.ZomboidFileSystem;
import zombie.characters.IsoPlayer;
import zombie.characters.professions.CharacterProfessionDefinition;
import zombie.characters.skills.PerkFactory;
import zombie.characters.traits.CharacterTraitDefinition;
import zombie.radio.ZomboidRadio;
import zombie.radio.media.MediaData;
import zombie.radio.media.RecordedMedia;
import zombie.scripting.objects.CharacterProfession;
import zombie.scripting.objects.CharacterTrait;

/**
 * Persists a snapshot of a player's progression to SQLite when they die. Mirrors the
 * attacker-attribution / extraction approach used by the extra-logging mod's DeathEventHandler, but
 * writes to a database rather than a log file.
 *
 * <p>Captured per death: identity + perk levels/XP, known recipes, read literature (titles), read
 * print media, watched recorded media (VHS tapes / CDs), and — if the Lifestyles mod is installed —
 * learned instrument songs, ambition progress, and hidden-skill progress (Yoga, Inventing).
 *
 * <p>Same two-thread split as {@link ListDeathsHandler}: the main thread snapshots all per-player
 * state (IsoPlayer, ZomboidRadio, and Kahlua mod-data tables are not thread-safe) into plain Java
 * records, and a daemon worker writes the death + all related rows to SQLite. No client reply, so
 * there's no completion-tick handler.
 */
public final class DeathEventHandler {

    private static final String DB_FILENAME = "survivor_skill_obelisk.db";

    /**
     * Instrument display name → Lifestyles per-instrument ModData key. Each value on {@code
     * player:getModData()} is a Lua array of song records. Package-visible so {@link
     * SyncLearnedSongsHandler} allowlists the same keys.
     */
    static final Map<String, String> LIFESTYLES_INSTRUMENT_KEYS;

    static {
        Map<String, String> keys = new LinkedHashMap<>();
        keys.put("Trumpet", "TrumpetLearnedTracks");
        keys.put("GuitarA", "GuitarALearnedTracks");
        keys.put("Banjo", "BanjoLearnedTracks");
        keys.put("Keytar", "KeytarLearnedTracks");
        keys.put("Saxophone", "SaxophoneLearnedTracks");
        keys.put("GuitarEB", "GuitarEBLearnedTracks");
        keys.put("GuitarE", "GuitarELearnedTracks");
        keys.put("Flute", "FluteLearnedTracks");
        keys.put("Piano", "PianoLearnedTracks");
        keys.put("Violin", "ViolinLearnedTracks");
        keys.put("Harmonica", "HarmonicaLearnedTracks");
        LIFESTYLES_INSTRUMENT_KEYS = keys;
    }

    /**
     * {@code rawXp} is the perk's XP as read off the dying character; {@code fallbackEarnedXp} is
     * the trait-replay estimate of earned XP, used only when no creation baseline exists for the
     * character (created before {@link CharacterBaselineHandler} shipped). The baseline itself is
     * read from SQLite at write time, not snapshot time — see {@link #writeDeath}.
     */
    private record SkillSnapshot(String perkId, int level, float rawXp, float fallbackEarnedXp) {}

    private record WatchedMediaSnapshot(
            String mediaId,
            int mediaIndex,
            String category,
            byte mediaType,
            String title,
            int linesWatched,
            int lineCount,
            boolean fullyListened) {}

    private record LearnedSongSnapshot(
            String instrument,
            String name,
            String sound,
            Double level,
            Double length,
            Double isaddon) {}

    private record HiddenSkillSnapshot(String skill, int level, double xp, double xpForNextLevel) {}

    private record AmbitionSnapshot(
            String name,
            String category,
            boolean completed,
            boolean isActive,
            boolean isPassive,
            String[] goals,
            String[] progress) {}

    private record DeathSnapshot(
            String username,
            long steamId,
            String forename,
            String surname,
            double hoursSurvived,
            int zombieKills,
            float x,
            float y,
            float z,
            List<SkillSnapshot> skills,
            List<String> recipes,
            List<String> readLiterature,
            List<String> readPrintMedia,
            List<WatchedMediaSnapshot> watchedMedia,
            List<LearnedSongSnapshot> learnedSongs,
            List<AmbitionSnapshot> ambitions,
            List<HiddenSkillSnapshot> hiddenSkills) {}

    /**
     * Shared single-thread write queue for death snapshots and character baselines. FIFO order is
     * load-bearing: a death is enqueued at {@code OnCharacterDeath} while the respawn's baseline
     * replace is enqueued at {@code OnNewGame} (which the client can only reach after the
     * character-creation screen), so {@link #writeDeath} is guaranteed to read the dying
     * character's baseline before the respawn overwrites it.
     */
    private static final BlockingQueue<Runnable> DB_WORK = new LinkedBlockingQueue<>();

    static {
        Thread worker =
                new Thread(DeathEventHandler::workerLoop, "SurvivorSkillObelisk-DbWrite-Worker");
        worker.setDaemon(true);
        worker.start();
    }

    private DeathEventHandler() {}

    static String getDbPath() {
        File dbFile = ZomboidFileSystem.instance.getFileInCurrentSave(DB_FILENAME);
        return dbFile.getAbsolutePath();
    }

    /** Run a SQLite write on the shared FIFO worker — see the ordering note on {@code DB_WORK}. */
    static void submitDbWrite(Runnable task) {
        DB_WORK.offer(task);
    }

    public static void onCharacterDeath(OnCharacterDeathEvent event) {
        if (!(event.character instanceof IsoPlayer player)) {
            return;
        }
        try {
            // Invalidate any recovery mid-pipeline for this player before the snapshot is queued —
            // its XP apply / ledger write must not land for the respawned character.
            RecoverSkillsHandler.notifyDeath(player.getSteamID(), player.getUsername());
            DeathSnapshot snapshot = snapshot(player);
            submitDbWrite(
                    () -> {
                        try {
                            writeDeath(snapshot);
                            LOGGER.info(
                                    "[SurvivorSkillObelisk] Recorded death of player: {}",
                                    snapshot.username());
                        } catch (Throwable t) {
                            LOGGER.error(
                                    "[SurvivorSkillObelisk] Failed to record death for player: {}",
                                    snapshot.username(),
                                    t);
                        }
                    });
        } catch (Exception e) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] Failed to snapshot death for player: {}",
                    player.getUsername(),
                    e);
        }
    }

    private static DeathSnapshot snapshot(IsoPlayer player) {
        return new DeathSnapshot(
                player.getUsername(),
                player.getSteamID(),
                player.getDescriptor().getForename(),
                player.getDescriptor().getSurname(),
                player.getHoursSurvived(),
                player.getZombieKills(),
                player.getX(),
                player.getY(),
                player.getZ(),
                snapshotSkills(player),
                snapshotRecipes(player),
                snapshotReadLiterature(player),
                snapshotReadPrintMedia(player),
                snapshotWatchedMedia(player),
                snapshotLearnedSongs(player),
                snapshotAmbitions(player),
                snapshotHiddenSkills(player));
    }

    private static void workerLoop() {
        while (true) {
            Runnable task;
            try {
                task = DB_WORK.take();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            }
            try {
                task.run();
            } catch (Throwable t) {
                LOGGER.error("[SurvivorSkillObelisk] DB write task failed: {}", t.getMessage(), t);
            }
        }
    }

    private static void writeDeath(DeathSnapshot s) throws Exception {
        try (SurvivorSkillObeliskDatabase db = new SurvivorSkillObeliskDatabase(getDbPath())) {
            SurvivorSkillObeliskRepository repo =
                    new SurvivorSkillObeliskRepository(db.getConnection());

            // The new snapshot below captures everything the character held, recovered XP
            // included, so the old recovery ledger is spent — deleting it lets the respawned
            // character recover any death at full value with nothing to subtract.
            repo.deleteRecovery(s.steamId(), s.username());

            // Creation-time XP recorded by CharacterBaselineHandler. Preferred over the snapshot's
            // trait-replay fallback because PZ swaps Strength/Fitness tier traits as those perks
            // level (server/XpSystem/XpUpdate.lua) — replaying the traits held at death would
            // charge e.g. a Weak-start character for the Strong trait it trained its way into.
            Map<String, Float> baseline = repo.findCharacterBaseline(s.steamId(), s.username());
            if (baseline == null) {
                LOGGER.info(
                        "[SurvivorSkillObelisk] No creation baseline for {} ({}) — character"
                                + " predates baseline tracking, using trait-replay estimate",
                        s.username(),
                        s.steamId());
            }

            long deathId =
                    repo.insertDeath(
                            System.currentTimeMillis(),
                            s.username(),
                            s.steamId(),
                            s.forename(),
                            s.surname(),
                            s.hoursSurvived(),
                            s.zombieKills(),
                            s.x(),
                            s.y(),
                            s.z());

            for (SkillSnapshot skill : s.skills()) {
                float xpToSave =
                        baseline != null
                                ? computeEarnedXp(skill.rawXp(), baseline.get(skill.perkId()))
                                : skill.fallbackEarnedXp();
                repo.insertSkill(deathId, skill.perkId(), skill.level(), xpToSave);
            }
            for (String recipe : s.recipes()) {
                repo.insertRecipe(deathId, recipe);
            }
            for (String title : s.readLiterature()) {
                repo.insertReadLiterature(deathId, title);
            }
            for (String mediaId : s.readPrintMedia()) {
                repo.insertReadPrintMedia(deathId, mediaId);
            }
            for (WatchedMediaSnapshot w : s.watchedMedia()) {
                repo.insertWatchedMedia(
                        deathId,
                        w.mediaId(),
                        w.mediaIndex(),
                        w.category(),
                        w.mediaType(),
                        w.title(),
                        w.linesWatched(),
                        w.lineCount(),
                        w.fullyListened());
            }
            for (LearnedSongSnapshot song : s.learnedSongs()) {
                repo.insertLearnedSong(
                        deathId,
                        song.instrument(),
                        song.name(),
                        song.sound(),
                        song.level(),
                        song.length(),
                        song.isaddon());
            }
            for (AmbitionSnapshot a : s.ambitions()) {
                repo.insertAmbition(
                        deathId,
                        a.name(),
                        a.category(),
                        a.completed(),
                        a.isActive(),
                        a.isPassive(),
                        a.goals(),
                        a.progress());
            }
            for (HiddenSkillSnapshot h : s.hiddenSkills()) {
                repo.insertHiddenSkill(deathId, h.skill(), h.level(), h.xp(), h.xpForNextLevel());
            }
        }
    }

    /**
     * Snapshot every perk in {@link PerkFactory#PerkList}, including ones the dead character left
     * at level 0 with no earned XP. Recovery is additive ({@link RecoverSkillsHandler}) but
     * subtracts what the previous recovery granted — the {@code xp=0} rows are what carry that
     * subtraction for perks the newly-recovered death never earned anything in. That's what blocks
     * the cumulative merge: chaining D1's high Running into D2's high Strength walks the Running
     * grant back out when D2 is recovered.
     *
     * <p>Carries both the raw XP (for subtraction against the creation baseline in {@link
     * #writeDeath}) and the trait-replay estimate as a fallback for characters created before
     * baselines were recorded.
     */
    private static List<SkillSnapshot> snapshotSkills(IsoPlayer player) {
        Map<PerkFactory.Perk, Integer> grantedLevels = grantedLevelsAtCreation(player);
        List<SkillSnapshot> result = new ArrayList<>(PerkFactory.PerkList.size());
        for (PerkFactory.Perk perk : PerkFactory.PerkList) {
            int level = player.getPerkLevel(perk);
            float rawXp = player.getXp().getXP(perk);
            int granted = grantedLevels.getOrDefault(perk, 0);
            float fallbackEarnedXp = computeXpToSave(rawXp, granted, perk);
            result.add(new SkillSnapshot(perk.getId(), level, rawXp, fallbackEarnedXp));
        }
        return result;
    }

    /**
     * Earned-only XP given the creation baseline: what the character gained through play on top of
     * what the character-creation flow granted. {@code baselineXp} is nullable for perks added to
     * the game (or by mods) after the character was created — nothing was granted, so everything
     * counts as earned. Clamped at 0 because Strength/Fitness XP can decay below the baseline
     * (vanilla's get-lazy timers in XpUpdate.lua drain passive-perk XP over time).
     */
    static float computeEarnedXp(float rawXp, Float baselineXp) {
        return Math.max(0f, rawXp - (baselineXp == null ? 0f : baselineXp));
    }

    /**
     * Convert raw XP and the per-perk creation-grant level to the "earned-only" XP we want to save.
     * Subtracts the cumulative XP the vanilla character-creation flow poured into {@code xpMap} for
     * the granted level so a player can't farm free-skill bonuses by dying immediately on a new
     * character. Clamps at 0 — sub-grant XP (Lifestyles can mutate the xpBoostMap mid-game, etc.)
     * just saves as nothing rather than going negative.
     */
    static float computeXpToSave(float rawXp, int grantedLevel, PerkFactory.Perk perk) {
        float grantedXp = grantedLevel > 0 ? perk.getTotalXpForLevel(grantedLevel) : 0f;
        return Math.max(0f, rawXp - grantedXp);
    }

    /**
     * FALLBACK ONLY — used when the character has no recorded creation baseline (predates {@link
     * CharacterBaselineHandler}). Replays {@code IsoGameCharacter#applyTraits}' summation against
     * the live trait + profession scripts so we can estimate the per-perk LEVEL boost the character
     * received at creation. Vanilla writes {@code descriptor.xpBoostMap} capped at 3 and Lifestyles
     * can mutate it mid-game, so don't read it back from there — sum from the factories instead.
     *
     * <p>Known inaccuracy (the reason baselines replaced this): PZ swaps the Strength/Fitness tier
     * traits (Weak/Feeble/Stout/Strong, Unfit/Out of Shape/Fit/Athletic) as those perks level, so
     * the traits held at death are not the traits picked at creation.
     */
    static Map<PerkFactory.Perk, Integer> grantedLevelsAtCreation(IsoPlayer player) {
        List<Map<PerkFactory.Perk, Integer>> traitBoosts = new ArrayList<>();
        for (CharacterTrait t : player.getCharacterTraits().getKnownTraits()) {
            CharacterTraitDefinition def = CharacterTraitDefinition.getCharacterTraitDefinition(t);
            if (def != null) {
                traitBoosts.add(def.getXpBoosts());
            }
        }
        Map<PerkFactory.Perk, Integer> professionBoosts = null;
        CharacterProfession profession = player.getDescriptor().getCharacterProfession();
        if (profession != null) {
            CharacterProfessionDefinition profDef =
                    CharacterProfessionDefinition.getCharacterProfessionDefinition(profession);
            if (profDef != null) {
                professionBoosts = profDef.getXpBoosts();
            }
        }
        return combineGrantedLevels(traitBoosts, professionBoosts);
    }

    /**
     * Pure math: combine the vanilla baseline (Strength=5, Fitness=5) with trait + profession boost
     * maps, then clamp every entry to {@code [0, 10]} — same algorithm as {@code
     * IsoGameCharacter#applyTraits} but taking boost maps directly so unit tests don't need to
     * stand up an {@code IsoPlayer} / texture system.
     */
    static Map<PerkFactory.Perk, Integer> combineGrantedLevels(
            List<Map<PerkFactory.Perk, Integer>> traitBoosts,
            Map<PerkFactory.Perk, Integer> professionBoosts) {
        HashMap<PerkFactory.Perk, Integer> levels = new HashMap<>();
        levels.put(PerkFactory.Perks.Strength, 5);
        levels.put(PerkFactory.Perks.Fitness, 5);
        if (traitBoosts != null) {
            for (Map<PerkFactory.Perk, Integer> boosts : traitBoosts) {
                if (boosts == null) {
                    continue;
                }
                for (Map.Entry<PerkFactory.Perk, Integer> e : boosts.entrySet()) {
                    levels.merge(e.getKey(), e.getValue(), Integer::sum);
                }
            }
        }
        if (professionBoosts != null) {
            for (Map.Entry<PerkFactory.Perk, Integer> e : professionBoosts.entrySet()) {
                levels.merge(e.getKey(), e.getValue(), Integer::sum);
            }
        }
        for (Map.Entry<PerkFactory.Perk, Integer> e : levels.entrySet()) {
            e.setValue(Math.max(0, Math.min(10, e.getValue())));
        }
        return levels;
    }

    /** Recipes the character has learned — most are taught by reading skill magazines. */
    private static List<String> snapshotRecipes(IsoPlayer player) {
        List<String> result = new ArrayList<>();
        for (String recipeName : player.getKnownRecipes()) {
            if (recipeName != null) {
                result.add(recipeName);
            }
        }
        return result;
    }

    /**
     * Skill books / magazines the character has read. Keys are PZ's per-item {@code
     * literatureTitle} mod-data strings (built by {@code ItemCodeOnCreate}/{@code
     * RecipeCodeHelper}) — NOT item full-types. The map's value is a "last-read day" stamp used by
     * the literature cooldown sandbox option, not a pages-read count, so we store membership only.
     */
    private static List<String> snapshotReadLiterature(IsoPlayer player) {
        List<String> result = new ArrayList<>();
        for (String literatureTitle : player.getReadLiterature().keySet()) {
            if (literatureTitle != null) {
                result.add(literatureTitle);
            }
        }
        return result;
    }

    /** Newspapers / print magazines the character has read. */
    private static List<String> snapshotReadPrintMedia(IsoPlayer player) {
        List<String> result = new ArrayList<>();
        for (String mediaId : player.getReadPrintMedia()) {
            if (mediaId != null) {
                result.add(mediaId);
            }
        }
        return result;
    }

    /**
     * Recorded media (VHS tapes / CDs) the character has watched. Consumption is tracked per media
     * line on the character ({@code knownMediaLines}); there is no public getter, so we iterate the
     * global catalog and test each tape's lines against the player.
     */
    private static List<WatchedMediaSnapshot> snapshotWatchedMedia(IsoPlayer player) {
        List<WatchedMediaSnapshot> result = new ArrayList<>();
        ZomboidRadio radio = ZomboidRadio.getInstance();
        if (radio == null) {
            return result;
        }
        RecordedMedia recordedMedia = radio.getRecordedMedia();
        if (recordedMedia == null) {
            return result;
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
            result.add(
                    new WatchedMediaSnapshot(
                            media.getId(),
                            media.getIndex(),
                            media.getCategory(),
                            media.getMediaType(),
                            title,
                            linesWatched,
                            lineCount,
                            recordedMedia.hasListenedToAll(player, media)));
        }
        return result;
    }

    /**
     * Lifestyles-mod instrument songs the character has learned. Stored on {@code
     * player:getModData()} under per-instrument keys (e.g. {@code PianoLearnedTracks}), each a Lua
     * array of {@code {name, sound, level, length, isaddon}} entries. No-op if Lifestyles isn't
     * installed (keys absent).
     */
    private static List<LearnedSongSnapshot> snapshotLearnedSongs(IsoPlayer player) {
        List<LearnedSongSnapshot> result = new ArrayList<>();
        KahluaTable modData = player.getModData();
        if (modData == null) {
            return result;
        }
        for (Map.Entry<String, String> entry : LIFESTYLES_INSTRUMENT_KEYS.entrySet()) {
            if (!(modData.rawget(entry.getValue()) instanceof KahluaTable songs)) {
                continue;
            }
            KahluaTableIterator it = songs.iterator();
            while (it.advance()) {
                if (!(it.getValue() instanceof KahluaTable song)) {
                    continue;
                }
                String name = asString(song.rawget("name"));
                if (name == null) {
                    continue;
                }
                result.add(
                        new LearnedSongSnapshot(
                                entry.getKey(),
                                name,
                                asString(song.rawget("sound")),
                                asDouble(song.rawget("level")),
                                asDouble(song.rawget("length")),
                                asDouble(song.rawget("isaddon"))));
            }
        }
        return result;
    }

    /**
     * Lifestyles-mod ambitions. Stored on {@code player:getModData().Ambitions} as a map keyed by
     * ambition name (e.g. {@code LSTerminator}) → object with {@code cat}, progress flags, and
     * goal1..goal6 targets / goal1progress..goal6progress values (goals can be numeric, string, or
     * boolean — stored as TEXT). No-op if Lifestyles isn't installed.
     */
    private static List<AmbitionSnapshot> snapshotAmbitions(IsoPlayer player) {
        List<AmbitionSnapshot> result = new ArrayList<>();
        KahluaTable modData = player.getModData();
        if (modData == null) {
            return result;
        }
        if (!(modData.rawget("Ambitions") instanceof KahluaTable ambitions)) {
            return result;
        }
        KahluaTableIterator it = ambitions.iterator();
        while (it.advance()) {
            if (!(it.getValue() instanceof KahluaTable ambition)) {
                continue;
            }
            String name = asString(ambition.rawget("name"));
            if (name == null) {
                name = asString(it.getKey());
            }
            if (name == null) {
                continue;
            }
            String[] goals = new String[6];
            String[] progress = new String[6];
            for (int i = 0; i < 6; i++) {
                goals[i] = asString(ambition.rawget("goal" + (i + 1)));
                progress[i] = asString(ambition.rawget("goal" + (i + 1) + "progress"));
            }
            result.add(
                    new AmbitionSnapshot(
                            name,
                            asString(ambition.rawget("cat")),
                            asBoolean(ambition.rawget("completed")),
                            asBoolean(ambition.rawget("isActive")),
                            asBoolean(ambition.rawget("isPassive")),
                            goals,
                            progress));
        }
        return result;
    }

    /**
     * Lifestyles-mod hidden skills (Yoga, Inventing). Stored on {@code
     * player:getModData().LSHiddenSkills} as a map keyed by skill name → Lua array of {@code
     * {level, xp, xpForNextLevel}} (see Lifestyles' HSMng.lua). Iterates whatever keys are present
     * rather than allowlisting the two known names so hidden skills Lifestyles adds later are
     * captured without a code change. No-op if Lifestyles isn't installed (key absent).
     */
    private static List<HiddenSkillSnapshot> snapshotHiddenSkills(IsoPlayer player) {
        List<HiddenSkillSnapshot> result = new ArrayList<>();
        KahluaTable modData = player.getModData();
        if (modData == null) {
            return result;
        }
        if (!(modData.rawget("LSHiddenSkills") instanceof KahluaTable skills)) {
            return result;
        }
        KahluaTableIterator it = skills.iterator();
        while (it.advance()) {
            if (!(it.getKey() instanceof String skill)
                    || !(it.getValue() instanceof KahluaTable values)) {
                continue;
            }
            Double level = asDouble(values.rawget(1));
            if (level == null) {
                continue;
            }
            Double xp = asDouble(values.rawget(2));
            Double xpForNextLevel = asDouble(values.rawget(3));
            result.add(
                    new HiddenSkillSnapshot(
                            skill,
                            level.intValue(),
                            xp == null ? 0.0 : xp,
                            xpForNextLevel == null ? 0.0 : xpForNextLevel));
        }
        return result;
    }

    /**
     * Render an arbitrary Lua value as a stable string for SQLite storage. Integers come back as
     * {@code Double} from Kahlua; format whole numbers without trailing {@code .0} so consumers see
     * e.g. {@code "5000"} instead of {@code "5000.0"}.
     */
    private static String asString(Object o) {
        if (o == null) {
            return null;
        }
        if (o instanceof String s) {
            return s;
        }
        if (o instanceof Double d) {
            if (!Double.isInfinite(d) && !Double.isNaN(d) && d == Math.floor(d)) {
                return Long.toString(d.longValue());
            }
            return d.toString();
        }
        if (o instanceof Boolean b) {
            return b.toString();
        }
        return o.toString();
    }

    private static Double asDouble(Object o) {
        return o instanceof Double d ? d : null;
    }

    private static boolean asBoolean(Object o) {
        return o instanceof Boolean b && b;
    }
}
