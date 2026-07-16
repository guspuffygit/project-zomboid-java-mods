package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.OnClientCommand;
import java.util.Set;
import java.util.function.Supplier;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaTableIterator;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;

/**
 * Handles the {@code SurvivorSkillObelisk:syncLearnedSongs} client command. Mirrors Lifestyles'
 * per-instrument learned-song tables from the client onto the server-side {@link IsoPlayer}
 * modData.
 *
 * <p>Why this exists: Lifestyles learns songs in client Lua only, and B42 player persistence is
 * server-authoritative — the server never sees client modData unless something mirrors it.
 * Lifestyles' own mirror ({@code LS:SavePlayerData} in ZLSUpdate.lua) runs once per in-game day, so
 * every song learned since the last game-midnight is invisible to {@link
 * DeathEventHandler#snapshotLearnedSongs} at death and silently missing from the recovery DB. The
 * companion client script (SurvivorSkillObeliskSongSync.lua) sends this command within a game
 * minute of a track-list change, shrinking that loss window to seconds.
 *
 * <p>Trust model matches Lifestyles' own {@code SavePlayerData} (which lets the owning client write
 * its whole modData): this data is client-authoritative by design. We still constrain the write to
 * the known {@code *LearnedTracks} keys, cap entries per instrument, and copy only primitive
 * fields, so the packet can't be used to plant arbitrary server-side state.
 *
 * <p>Runs on the main thread (client command dispatch) — Kahlua tables are not thread-safe, and
 * this is a plain in-memory write with no I/O, so no worker split is needed.
 */
public final class SyncLearnedSongsHandler {

    /** Songs per instrument beyond this are dropped; Lifestyles ships ~40 tracks per instrument. */
    private static final int MAX_SONGS_PER_INSTRUMENT = 500;

    private static final Set<String> ALLOWED_KEYS =
            Set.copyOf(DeathEventHandler.LIFESTYLES_INSTRUMENT_KEYS.values());

    private SyncLearnedSongsHandler() {}

    @OnClientCommand
    public static void onSyncLearnedSongs(SyncLearnedSongsCommand event) {
        IsoPlayer player = event.getPlayer();
        if (player == null) {
            LOGGER.warn("[SurvivorSkillObelisk] syncLearnedSongs from null player; dropping");
            return;
        }
        KahluaTable tracks = event.getTracks();
        if (tracks == null) {
            LOGGER.warn(
                    "[SurvivorSkillObelisk] syncLearnedSongs from {} with no tracks table;"
                            + " dropping",
                    player.getUsername());
            return;
        }
        KahluaTable modData = player.getModData();
        if (modData == null) {
            return;
        }
        int mirrored = mirrorTracks(tracks, modData, LuaManager.platform::newTable);
        LOGGER.debug(
                "[SurvivorSkillObelisk] syncLearnedSongs: mirrored {} songs for {}",
                mirrored,
                player.getUsername());
    }

    /**
     * Replace each allowlisted {@code *LearnedTracks} key in {@code modData} with a sanitized copy
     * of the client-sent list. Replacement (not merge) is deliberate: the client is the source of
     * truth for this Lifestyles data, and an empty client list must clear the server mirror too.
     * Returns the total number of song entries written.
     */
    static int mirrorTracks(
            KahluaTable tracks, KahluaTable modData, Supplier<KahluaTable> newTable) {
        int mirrored = 0;
        KahluaTableIterator it = tracks.iterator();
        while (it.advance()) {
            if (!(it.getKey() instanceof String key) || !ALLOWED_KEYS.contains(key)) {
                continue;
            }
            if (!(it.getValue() instanceof KahluaTable list)) {
                continue;
            }
            KahluaTable mirror = newTable.get();
            int next = 1;
            KahluaTableIterator songs = list.iterator();
            while (songs.advance() && next <= MAX_SONGS_PER_INSTRUMENT) {
                if (!(songs.getValue() instanceof KahluaTable song)
                        || !(song.rawget("name") instanceof String)) {
                    continue;
                }
                KahluaTable copy = newTable.get();
                KahluaTableIterator fields = song.iterator();
                while (fields.advance()) {
                    Object fieldKey = fields.getKey();
                    Object value = fields.getValue();
                    if (fieldKey instanceof String
                            && (value instanceof String
                                    || value instanceof Double
                                    || value instanceof Boolean)) {
                        copy.rawset(fieldKey, value);
                    }
                }
                mirror.rawset((double) next, copy);
                next++;
                mirrored++;
            }
            modData.rawset(key, mirror);
        }
        return mirrored;
    }
}
