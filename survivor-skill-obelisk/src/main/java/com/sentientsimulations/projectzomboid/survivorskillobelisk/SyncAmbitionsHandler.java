package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.OnClientCommand;
import java.util.ArrayList;
import java.util.List;
import java.util.function.Supplier;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaTableIterator;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;

/**
 * Handles the {@code SurvivorSkillObelisk:syncAmbitions} client command. Mirrors the goal-progress
 * fields of Lifestyles' {@code Ambitions} table from the client onto the server-side {@link
 * IsoPlayer} modData.
 *
 * <p>Why this exists: same gap as {@link SyncLearnedSongsHandler} / {@link
 * SyncHiddenSkillsHandler}. Lifestyles' per-ambition handlers mutate {@code goalNprogress}
 * client-side continuously (LSTerminator recomputes kill progress every game minute), but its
 * {@code LS:SavePlayerData} mirror only fires on discrete events (complete, unlock, assign, reset)
 * plus a configurable timer — so in-progress goal counts on the server are stale by up to that
 * interval, and {@link DeathEventHandler#snapshotAmbitions} snapshots the stale copy at death. The
 * companion client script (SurvivorSkillObeliskAmbitionSync.lua) sends this command within a game
 * minute of any flag/progress change.
 *
 * <p>Unlike the songs / hidden-skills mirrors, this MERGES per-field instead of replacing the
 * table: ambition entries carry sidecar state the progress math depends on (LSTerminator's {@code
 * ogKills} kill baseline, {@code ogFireKR}, etc.) that only Lifestyles' own full mirror writes.
 * Replacing an entry with our allowlisted subset would strip those and corrupt progress after the
 * next reload. Entry removal (ambition disable/reset) is also left to Lifestyles — its own paths
 * push a full {@code SavePlayerData} immediately.
 *
 * <p>Trust model matches Lifestyles' own {@code SavePlayerData} (which lets the owning client write
 * its whole modData unvalidated): this data is client-authoritative by design. We still constrain
 * the write to the {@code Ambitions} key, cap the entry count, and copy only the allowlisted
 * primitive fields the death snapshot reads, so the packet can't plant arbitrary server-side state.
 *
 * <p>Runs on the main thread (client command dispatch) — Kahlua tables are not thread-safe, and
 * this is a plain in-memory write with no I/O, so no worker split is needed.
 */
public final class SyncAmbitionsHandler {

    /** Lifestyles ships a few dozen ambitions; anything past this is a hostile payload. */
    private static final int MAX_AMBITIONS = 200;

    /**
     * Exactly the fields {@link DeathEventHandler#snapshotAmbitions} reads. Sidecar fields (ogKills
     * and friends) are deliberately absent — see the class javadoc.
     */
    private static final List<String> ALLOWED_FIELDS = buildAllowedFields();

    private static List<String> buildAllowedFields() {
        List<String> fields = new ArrayList<>();
        fields.add("name");
        fields.add("cat");
        fields.add("completed");
        fields.add("isActive");
        fields.add("isPassive");
        for (int i = 1; i <= 6; i++) {
            fields.add("goal" + i);
            fields.add("goal" + i + "progress");
        }
        return List.copyOf(fields);
    }

    private SyncAmbitionsHandler() {}

    @OnClientCommand
    public static void onSyncAmbitions(SyncAmbitionsCommand event) {
        IsoPlayer player = event.getPlayer();
        if (player == null) {
            LOGGER.warn("[SurvivorSkillObelisk] syncAmbitions from null player; dropping");
            return;
        }
        KahluaTable ambitions = event.getAmbitions();
        if (ambitions == null) {
            LOGGER.warn(
                    "[SurvivorSkillObelisk] syncAmbitions from {} with no ambitions table;"
                            + " dropping",
                    player.getUsername());
            return;
        }
        KahluaTable modData = player.getModData();
        if (modData == null) {
            return;
        }
        int merged = mergeAmbitions(ambitions, modData, LuaManager.platform::newTable);
        LOGGER.debug(
                "[SurvivorSkillObelisk] syncAmbitions: merged {} ambitions for {}",
                merged,
                player.getUsername());
    }

    /**
     * Merge each client-sent ambition's allowlisted primitive fields into {@code
     * modData.Ambitions}, creating the table / entries when missing. Fields outside the allowlist
     * and non-primitive values are ignored; fields absent from the client entry are left untouched
     * on the server entry. Returns the number of ambition entries merged.
     */
    static int mergeAmbitions(
            KahluaTable ambitions, KahluaTable modData, Supplier<KahluaTable> newTable) {
        KahluaTable target;
        Object existing = modData.rawget("Ambitions");
        if (existing instanceof KahluaTable existingTable) {
            target = existingTable;
        } else {
            target = newTable.get();
            modData.rawset("Ambitions", target);
        }
        int merged = 0;
        KahluaTableIterator it = ambitions.iterator();
        while (it.advance() && merged < MAX_AMBITIONS) {
            if (!(it.getKey() instanceof String name)
                    || !(it.getValue() instanceof KahluaTable sent)) {
                continue;
            }
            KahluaTable entry;
            Object entryObj = target.rawget(name);
            if (entryObj instanceof KahluaTable existingEntry) {
                entry = existingEntry;
            } else {
                entry = newTable.get();
                target.rawset(name, entry);
            }
            for (String field : ALLOWED_FIELDS) {
                Object value = sent.rawget(field);
                if (value instanceof String
                        || value instanceof Double
                        || value instanceof Boolean) {
                    entry.rawset(field, value);
                }
            }
            merged++;
        }
        return merged;
    }
}
