package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.lua.OnCharacterDeathEvent;
import java.io.File;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
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
 * learned instrument songs and ambition progress.
 */
public final class DeathEventHandler {

    private static final String DB_FILENAME = "survivor_skill_obelisk.db";

    /**
     * Instrument display name → Lifestyles per-instrument ModData key. Each value on {@code
     * player:getModData()} is a Lua array of song records.
     */
    private static final Map<String, String> LIFESTYLES_INSTRUMENT_KEYS;

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
            recordLearnedSongs(repo, deathId, player);
            recordAmbitions(repo, deathId, player);
        }
    }

    private static void recordSkills(
            SurvivorSkillObeliskRepository repo, long deathId, IsoPlayer player) throws Exception {
        Map<PerkFactory.Perk, Integer> grantedLevels = grantedLevelsAtCreation(player);
        for (PerkFactory.Perk perk : PerkFactory.PerkList) {
            int level = player.getPerkLevel(perk);
            float rawXp = player.getXp().getXP(perk);
            int granted = grantedLevels.getOrDefault(perk, 0);
            float xpToSave = computeXpToSave(rawXp, granted, perk);
            if (level > 0 || xpToSave > 0f) {
                repo.insertSkill(deathId, perk.getId(), level, xpToSave);
            }
        }
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
     * Replays {@code IsoGameCharacter#applyTraits}' summation against the live trait + profession
     * scripts so we can recover the per-perk LEVEL boost the character received at creation.
     * Vanilla writes {@code descriptor.xpBoostMap} capped at 3 and Lifestyles can mutate it
     * mid-game, so don't read it back from there — sum from the factories instead.
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
    private static void recordRecipes(
            SurvivorSkillObeliskRepository repo, long deathId, IsoPlayer player) throws Exception {
        for (String recipeName : player.getKnownRecipes()) {
            if (recipeName != null) {
                repo.insertRecipe(deathId, recipeName);
            }
        }
    }

    /**
     * Skill books / magazines the character has read. Keys are PZ's per-item {@code
     * literatureTitle} mod-data strings (built by {@code ItemCodeOnCreate}/{@code
     * RecipeCodeHelper}) — NOT item full-types. The map's value is a "last-read day" stamp used by
     * the literature cooldown sandbox option, not a pages-read count, so we store membership only.
     */
    private static void recordReadLiterature(
            SurvivorSkillObeliskRepository repo, long deathId, IsoPlayer player) throws Exception {
        for (String literatureTitle : player.getReadLiterature().keySet()) {
            if (literatureTitle != null) {
                repo.insertReadLiterature(deathId, literatureTitle);
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

    /**
     * Lifestyles-mod instrument songs the character has learned. Stored on {@code
     * player:getModData()} under per-instrument keys (e.g. {@code PianoLearnedTracks}), each a Lua
     * array of {@code {name, sound, level, length, isaddon}} entries. No-op if Lifestyles isn't
     * installed (keys absent).
     */
    private static void recordLearnedSongs(
            SurvivorSkillObeliskRepository repo, long deathId, IsoPlayer player) throws Exception {
        KahluaTable modData = player.getModData();
        if (modData == null) {
            return;
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
                repo.insertLearnedSong(
                        deathId, entry.getKey(), name, asString(song.rawget("sound")));
            }
        }
    }

    /**
     * Lifestyles-mod ambitions. Stored on {@code player:getModData().Ambitions} as a map keyed by
     * ambition name (e.g. {@code LSTerminator}) → object with {@code cat}, progress flags, and
     * goal1..goal6 targets / goal1progress..goal6progress values (goals can be numeric, string, or
     * boolean — stored as TEXT). No-op if Lifestyles isn't installed.
     */
    private static void recordAmbitions(
            SurvivorSkillObeliskRepository repo, long deathId, IsoPlayer player) throws Exception {
        KahluaTable modData = player.getModData();
        if (modData == null) {
            return;
        }
        if (!(modData.rawget("Ambitions") instanceof KahluaTable ambitions)) {
            return;
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
            repo.insertAmbition(
                    deathId,
                    name,
                    asString(ambition.rawget("cat")),
                    asBoolean(ambition.rawget("completed")),
                    asBoolean(ambition.rawget("isActive")),
                    asBoolean(ambition.rawget("isPassive")),
                    goals,
                    progress);
        }
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

    private static boolean asBoolean(Object o) {
        return o instanceof Boolean b && b;
    }
}
