package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.HashMap;
import java.util.function.Supplier;
import org.junit.jupiter.api.Test;
import se.krka.kahlua.j2se.KahluaTableImpl;
import se.krka.kahlua.vm.KahluaTable;

/**
 * Tests for the table-mirroring core of {@link SyncLearnedSongsHandler}: allowlisted keys only,
 * wholesale replacement (client is authoritative), primitive fields copied, junk skipped.
 */
class SyncLearnedSongsHandlerTest {

    private static final Supplier<KahluaTable> NEW_TABLE =
            () -> new KahluaTableImpl(new HashMap<>());

    private static KahluaTable table() {
        return NEW_TABLE.get();
    }

    private static KahluaTable song(String name, String sound, Double level) {
        KahluaTable song = table();
        song.rawset("name", name);
        song.rawset("sound", sound);
        if (level != null) {
            song.rawset("level", level);
        }
        return song;
    }

    @Test
    void mirrorsSongsWithAllPrimitiveFields() {
        KahluaTable list = table();
        KahluaTable song = song("ContextMenu_00_01_B", "Piano00LastPost", 3.0);
        song.rawset("length", 95.0);
        song.rawset("isaddon", 1.0);
        list.rawset(1.0, song);
        KahluaTable tracks = table();
        tracks.rawset("PianoLearnedTracks", list);
        KahluaTable modData = table();

        int mirrored = SyncLearnedSongsHandler.mirrorTracks(tracks, modData, NEW_TABLE);

        assertEquals(1, mirrored);
        KahluaTable mirroredList = (KahluaTable) modData.rawget("PianoLearnedTracks");
        KahluaTable mirroredSong = (KahluaTable) mirroredList.rawget(1.0);
        assertEquals("ContextMenu_00_01_B", mirroredSong.rawget("name"));
        assertEquals("Piano00LastPost", mirroredSong.rawget("sound"));
        assertEquals(3.0, mirroredSong.rawget("level"));
        assertEquals(95.0, mirroredSong.rawget("length"));
        assertEquals(1.0, mirroredSong.rawget("isaddon"));
    }

    @Test
    void replacesExistingListWholesale() {
        // The client list is the source of truth: entries that vanished client-side (character
        // reset) must vanish from the mirror too, not merge with stale server state.
        KahluaTable modData = table();
        KahluaTable stale = table();
        stale.rawset(1.0, song("OldSong", "OldSound", 1.0));
        stale.rawset(2.0, song("OldSong2", "OldSound2", 2.0));
        modData.rawset("ViolinLearnedTracks", stale);

        KahluaTable list = table();
        list.rawset(1.0, song("NewSong", "NewSound", 4.0));
        KahluaTable tracks = table();
        tracks.rawset("ViolinLearnedTracks", list);

        SyncLearnedSongsHandler.mirrorTracks(tracks, modData, NEW_TABLE);

        KahluaTable mirroredList = (KahluaTable) modData.rawget("ViolinLearnedTracks");
        assertEquals(1, mirroredList.len());
        assertEquals("NewSong", ((KahluaTable) mirroredList.rawget(1.0)).rawget("name"));
    }

    @Test
    void emptyClientListClearsMirror() {
        KahluaTable modData = table();
        KahluaTable stale = table();
        stale.rawset(1.0, song("OldSong", "OldSound", 1.0));
        modData.rawset("FluteLearnedTracks", stale);

        KahluaTable tracks = table();
        tracks.rawset("FluteLearnedTracks", table());

        int mirrored = SyncLearnedSongsHandler.mirrorTracks(tracks, modData, NEW_TABLE);

        assertEquals(0, mirrored);
        assertEquals(0, ((KahluaTable) modData.rawget("FluteLearnedTracks")).len());
    }

    @Test
    void ignoresKeysOutsideTheInstrumentAllowlist() {
        KahluaTable list = table();
        list.rawset(1.0, song("Song", "Sound", 1.0));
        KahluaTable tracks = table();
        tracks.rawset("Ambitions", list);
        tracks.rawset("KnownRecipes", list);
        tracks.rawset(1.0, list);
        KahluaTable modData = table();

        int mirrored = SyncLearnedSongsHandler.mirrorTracks(tracks, modData, NEW_TABLE);

        assertEquals(0, mirrored);
        assertNull(modData.rawget("Ambitions"));
        assertNull(modData.rawget("KnownRecipes"));
        assertTrue(modData.isEmpty());
    }

    @Test
    void skipsEntriesWithoutANameAndNonPrimitiveFields() {
        KahluaTable list = table();
        KahluaTable nameless = table();
        nameless.rawset("sound", "Sound");
        list.rawset(1.0, nameless);
        list.rawset(2.0, "not a table");
        KahluaTable valid = song("Song", "Sound", 2.0);
        valid.rawset("nested", table());
        valid.rawset(1.0, "numeric-keyed junk");
        list.rawset(3.0, valid);
        KahluaTable tracks = table();
        tracks.rawset("BanjoLearnedTracks", list);
        KahluaTable modData = table();

        int mirrored = SyncLearnedSongsHandler.mirrorTracks(tracks, modData, NEW_TABLE);

        assertEquals(1, mirrored);
        KahluaTable mirroredList = (KahluaTable) modData.rawget("BanjoLearnedTracks");
        assertEquals(1, mirroredList.len());
        KahluaTable mirroredSong = (KahluaTable) mirroredList.rawget(1.0);
        assertEquals("Song", mirroredSong.rawget("name"));
        assertNull(mirroredSong.rawget("nested"));
        assertNull(mirroredSong.rawget(1.0));
    }

    @Test
    void compactsSparseIndicesIntoAContiguousArray() {
        // The mirror is rebuilt 1..n so KahluaTable.len() (used by the death snapshot's iterator
        // and Lifestyles' # operator) sees every surviving entry even if the client list had holes.
        KahluaTable list = table();
        list.rawset(1.0, song("A", "SoundA", 1.0));
        list.rawset(2.0, "junk");
        list.rawset(3.0, song("B", "SoundB", 2.0));
        KahluaTable tracks = table();
        tracks.rawset("TrumpetLearnedTracks", list);
        KahluaTable modData = table();

        int mirrored = SyncLearnedSongsHandler.mirrorTracks(tracks, modData, NEW_TABLE);

        assertEquals(2, mirrored);
        KahluaTable mirroredList = (KahluaTable) modData.rawget("TrumpetLearnedTracks");
        assertEquals(2, mirroredList.len());
    }
}
