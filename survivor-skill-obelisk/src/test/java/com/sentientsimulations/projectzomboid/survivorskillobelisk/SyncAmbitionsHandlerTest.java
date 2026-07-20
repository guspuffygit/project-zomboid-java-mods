package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

import java.util.HashMap;
import java.util.function.Supplier;
import org.junit.jupiter.api.Test;
import se.krka.kahlua.j2se.KahluaTableImpl;
import se.krka.kahlua.vm.KahluaTable;

/**
 * Tests for the table-merging core of {@link SyncAmbitionsHandler}: allowlisted primitive fields
 * merged per-field (NOT wholesale replacement — Lifestyles' sidecar state like {@code ogKills} must
 * survive), junk skipped.
 */
class SyncAmbitionsHandlerTest {

    private static final Supplier<KahluaTable> NEW_TABLE =
            () -> new KahluaTableImpl(new HashMap<>());

    private static KahluaTable table() {
        return NEW_TABLE.get();
    }

    private static KahluaTable ambitions(KahluaTable modData) {
        return (KahluaTable) modData.rawget("Ambitions");
    }

    @Test
    void createsTableAndEntriesWithAllowlistedFields() {
        KahluaTable sent = table();
        KahluaTable terminator = table();
        terminator.rawset("name", "LSTerminator");
        terminator.rawset("cat", "Combat");
        terminator.rawset("texture", "LSTerminator");
        terminator.rawset("disable", Boolean.FALSE);
        terminator.rawset("completed", Boolean.FALSE);
        terminator.rawset("isActive", Boolean.TRUE);
        terminator.rawset("isPassive", Boolean.FALSE);
        terminator.rawset("goal1", 5000.0);
        terminator.rawset("goal1progress", 137.0);
        terminator.rawset("goal2", "pain");
        terminator.rawset("goal2progress", Boolean.TRUE);
        sent.rawset("LSTerminator", terminator);
        KahluaTable modData = table();

        int merged = SyncAmbitionsHandler.mergeAmbitions(sent, modData, NEW_TABLE);

        assertEquals(1, merged);
        KahluaTable entry = (KahluaTable) ambitions(modData).rawget("LSTerminator");
        assertEquals("LSTerminator", entry.rawget("name"));
        assertEquals("Combat", entry.rawget("cat"));
        // Definition fields mirror through so the server-side entry survives Lifestyles'
        // once-per-session consistency check, which treats a nil texture/disable as a
        // changed definition and deep-copy resets the entry.
        assertEquals("LSTerminator", entry.rawget("texture"));
        assertEquals(Boolean.FALSE, entry.rawget("disable"));
        assertEquals(Boolean.TRUE, entry.rawget("isActive"));
        assertEquals(5000.0, entry.rawget("goal1"));
        assertEquals(137.0, entry.rawget("goal1progress"));
        assertEquals("pain", entry.rawget("goal2"));
        assertEquals(Boolean.TRUE, entry.rawget("goal2progress"));
    }

    @Test
    void preservesSidecarFieldsOnExistingEntries() {
        // The reason this handler merges instead of replacing: Lifestyles stores progress
        // baselines (LSTerminator's ogKills, ogFireKR, ...) on the same entry, and only its own
        // full mirror writes them. A wholesale replace with our allowlisted subset would strip
        // them and corrupt progress math after the next reload.
        KahluaTable modData = table();
        KahluaTable serverAmbitions = table();
        KahluaTable serverEntry = table();
        serverEntry.rawset("name", "LSTerminator");
        serverEntry.rawset("goal1progress", 50.0);
        serverEntry.rawset("ogKills", 4200.0);
        serverEntry.rawset("reset", Boolean.TRUE);
        serverAmbitions.rawset("LSTerminator", serverEntry);
        modData.rawset("Ambitions", serverAmbitions);

        KahluaTable sent = table();
        KahluaTable clientEntry = table();
        clientEntry.rawset("goal1progress", 137.0);
        sent.rawset("LSTerminator", clientEntry);

        SyncAmbitionsHandler.mergeAmbitions(sent, modData, NEW_TABLE);

        KahluaTable entry = (KahluaTable) ambitions(modData).rawget("LSTerminator");
        assertEquals(137.0, entry.rawget("goal1progress"));
        assertEquals(4200.0, entry.rawget("ogKills"));
        assertEquals(Boolean.TRUE, entry.rawget("reset"));
        // Field absent from the client entry stays untouched rather than being cleared.
        assertEquals("LSTerminator", entry.rawget("name"));
    }

    @Test
    void doesNotResurrectEntriesAbsentFromThePayloadOrTouchOtherEntries() {
        KahluaTable modData = table();
        KahluaTable serverAmbitions = table();
        KahluaTable other = table();
        other.rawset("goal1progress", 9.0);
        serverAmbitions.rawset("LSExplorer", other);
        modData.rawset("Ambitions", serverAmbitions);

        KahluaTable sent = table();
        KahluaTable clientEntry = table();
        clientEntry.rawset("goal1progress", 1.0);
        sent.rawset("LSLucky", clientEntry);

        SyncAmbitionsHandler.mergeAmbitions(sent, modData, NEW_TABLE);

        assertEquals(
                9.0,
                ((KahluaTable) ambitions(modData).rawget("LSExplorer")).rawget("goal1progress"));
        assertEquals(
                1.0, ((KahluaTable) ambitions(modData).rawget("LSLucky")).rawget("goal1progress"));
    }

    @Test
    void skipsUnknownFieldsNonPrimitivesAndJunkKeys() {
        KahluaTable sent = table();
        KahluaTable entry = table();
        entry.rawset("goal1progress", 10.0);
        entry.rawset("ogKills", 4200.0);
        entry.rawset("evil", table());
        KahluaTable nested = table();
        entry.rawset("goal2progress", nested);
        sent.rawset("LSTerminator", entry);
        sent.rawset(1.0, entry);
        sent.rawset("NotATable", "junk");
        KahluaTable modData = table();

        int merged = SyncAmbitionsHandler.mergeAmbitions(sent, modData, NEW_TABLE);

        assertEquals(1, merged);
        KahluaTable mergedEntry = (KahluaTable) ambitions(modData).rawget("LSTerminator");
        assertEquals(10.0, mergedEntry.rawget("goal1progress"));
        // ogKills is client-sent here but NOT allowlisted: the client never legitimately needs to
        // write it (Lifestyles' own mirror owns it), so the packet can't tamper with baselines.
        assertNull(mergedEntry.rawget("ogKills"));
        assertNull(mergedEntry.rawget("evil"));
        assertNull(mergedEntry.rawget("goal2progress"));
        assertNull(ambitions(modData).rawget(1.0));
        assertNull(ambitions(modData).rawget("NotATable"));
    }
}
