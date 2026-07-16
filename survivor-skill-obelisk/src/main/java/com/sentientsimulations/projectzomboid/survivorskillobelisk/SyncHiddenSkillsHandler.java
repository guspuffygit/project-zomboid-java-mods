package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.OnClientCommand;
import java.util.function.Supplier;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaTableIterator;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;

/**
 * Handles the {@code SurvivorSkillObelisk:syncHiddenSkills} client command. Mirrors Lifestyles'
 * {@code LSHiddenSkills} hidden-skill table (Yoga, Inventing) from the client onto the server-side
 * {@link IsoPlayer} modData.
 *
 * <p>Why this exists: same gap as {@link SyncLearnedSongsHandler} — Lifestyles earns hidden-skill
 * XP in client Lua only (HSMng.lua), B42 player persistence is server-authoritative, and
 * Lifestyles' own daily {@code LS:SavePlayerData} mirror leaves everything earned since the last
 * game-midnight invisible to {@link DeathEventHandler#snapshotHiddenSkills} at death. The companion
 * client script (SurvivorSkillObeliskHiddenSkillSync.lua) sends this command within a game minute
 * of any level/XP change.
 *
 * <p>Trust model matches the songs sync: this data is client-authoritative by design. The write is
 * constrained to the {@code LSHiddenSkills} key, entry count is capped, and only the three numeric
 * slots of each entry are copied, so the packet can't plant arbitrary server-side state.
 *
 * <p>Runs on the main thread (client command dispatch) — Kahlua tables are not thread-safe, and
 * this is a plain in-memory write with no I/O, so no worker split is needed.
 */
public final class SyncHiddenSkillsHandler {

    /** Lifestyles defines two hidden skills; anything past this is a hostile payload. */
    private static final int MAX_HIDDEN_SKILLS = 100;

    private SyncHiddenSkillsHandler() {}

    @OnClientCommand
    public static void onSyncHiddenSkills(SyncHiddenSkillsCommand event) {
        IsoPlayer player = event.getPlayer();
        if (player == null) {
            LOGGER.warn("[SurvivorSkillObelisk] syncHiddenSkills from null player; dropping");
            return;
        }
        KahluaTable skills = event.getSkills();
        if (skills == null) {
            LOGGER.warn(
                    "[SurvivorSkillObelisk] syncHiddenSkills from {} with no skills table;"
                            + " dropping",
                    player.getUsername());
            return;
        }
        KahluaTable modData = player.getModData();
        if (modData == null) {
            return;
        }
        int mirrored = mirrorHiddenSkills(skills, modData, LuaManager.platform::newTable);
        LOGGER.debug(
                "[SurvivorSkillObelisk] syncHiddenSkills: mirrored {} skills for {}",
                mirrored,
                player.getUsername());
    }

    /**
     * Replace {@code modData.LSHiddenSkills} with a sanitized copy of the client-sent table.
     * Replacement (not merge) is deliberate: the client is the source of truth for this Lifestyles
     * data, and a reset skill (Lifestyles' resetSkill writes {@code {0, 0, 100}}) must overwrite
     * the server mirror too. Each surviving entry is rebuilt with exactly the three numeric slots
     * of Lifestyles' {@code {level, xp, xpForNextLevel}} shape; entries whose slots aren't all
     * numbers are skipped. Returns the number of skill entries written.
     */
    static int mirrorHiddenSkills(
            KahluaTable skills, KahluaTable modData, Supplier<KahluaTable> newTable) {
        KahluaTable mirror = newTable.get();
        int mirrored = 0;
        KahluaTableIterator it = skills.iterator();
        while (it.advance() && mirrored < MAX_HIDDEN_SKILLS) {
            if (!(it.getKey() instanceof String skill)
                    || !(it.getValue() instanceof KahluaTable entry)) {
                continue;
            }
            if (!(entry.rawget(1) instanceof Double level)
                    || !(entry.rawget(2) instanceof Double xp)
                    || !(entry.rawget(3) instanceof Double xpForNextLevel)) {
                continue;
            }
            KahluaTable copy = newTable.get();
            copy.rawset(1, level);
            copy.rawset(2, xp);
            copy.rawset(3, xpForNextLevel);
            mirror.rawset(skill, copy);
            mirrored++;
        }
        modData.rawset("LSHiddenSkills", mirror);
        return mirrored;
    }
}
