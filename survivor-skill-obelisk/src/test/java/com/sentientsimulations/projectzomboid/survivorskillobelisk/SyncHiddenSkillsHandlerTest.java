package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

import java.util.HashMap;
import java.util.function.Supplier;
import org.junit.jupiter.api.Test;
import se.krka.kahlua.j2se.KahluaTableImpl;
import se.krka.kahlua.vm.KahluaTable;

/**
 * Tests for the table-mirroring core of {@link SyncHiddenSkillsHandler}: wholesale replacement
 * (client is authoritative), exactly the three numeric slots copied, junk skipped.
 */
class SyncHiddenSkillsHandlerTest {

    private static final Supplier<KahluaTable> NEW_TABLE =
            () -> new KahluaTableImpl(new HashMap<>());

    private static KahluaTable table() {
        return NEW_TABLE.get();
    }

    private static KahluaTable entry(Double level, Double xp, Double xpForNextLevel) {
        KahluaTable entry = table();
        if (level != null) {
            entry.rawset(1.0, level);
        }
        if (xp != null) {
            entry.rawset(2.0, xp);
        }
        if (xpForNextLevel != null) {
            entry.rawset(3.0, xpForNextLevel);
        }
        return entry;
    }

    @Test
    void mirrorsSkillsWithAllThreeSlots() {
        KahluaTable skills = table();
        skills.rawset("Yoga", entry(4.0, 320.0, 1000.0));
        skills.rawset("Inventing", entry(0.0, 50.0, 100.0));
        KahluaTable modData = table();

        int mirrored = SyncHiddenSkillsHandler.mirrorHiddenSkills(skills, modData, NEW_TABLE);

        assertEquals(2, mirrored);
        KahluaTable mirror = (KahluaTable) modData.rawget("LSHiddenSkills");
        KahluaTable yoga = (KahluaTable) mirror.rawget("Yoga");
        assertEquals(4.0, yoga.rawget(1.0));
        assertEquals(320.0, yoga.rawget(2.0));
        assertEquals(1000.0, yoga.rawget(3.0));
        KahluaTable inventing = (KahluaTable) mirror.rawget("Inventing");
        assertEquals(0.0, inventing.rawget(1.0));
    }

    @Test
    void replacesExistingMirrorWholesale() {
        // The client table is the source of truth: a skill reset (Lifestyles writes {0, 0, 100})
        // must overwrite the mirror, and skills absent client-side must vanish from it.
        KahluaTable modData = table();
        KahluaTable stale = table();
        stale.rawset("Yoga", entry(9.0, 8000.0, 9000.0));
        stale.rawset("Inventing", entry(5.0, 0.0, 1250.0));
        modData.rawset("LSHiddenSkills", stale);

        KahluaTable skills = table();
        skills.rawset("Yoga", entry(0.0, 0.0, 100.0));

        SyncHiddenSkillsHandler.mirrorHiddenSkills(skills, modData, NEW_TABLE);

        KahluaTable mirror = (KahluaTable) modData.rawget("LSHiddenSkills");
        assertEquals(0.0, ((KahluaTable) mirror.rawget("Yoga")).rawget(1.0));
        assertNull(mirror.rawget("Inventing"));
    }

    @Test
    void skipsEntriesWithNonNumericSlotsAndNonStringKeys() {
        KahluaTable skills = table();
        skills.rawset("Yoga", entry(null, 320.0, 1000.0));
        skills.rawset("Inventing", "not a table");
        skills.rawset(1.0, entry(1.0, 0.0, 100.0));
        KahluaTable bad = entry(2.0, 0.0, null);
        bad.rawset(3.0, "not a number");
        skills.rawset("Corrupt", bad);
        KahluaTable modData = table();

        int mirrored = SyncHiddenSkillsHandler.mirrorHiddenSkills(skills, modData, NEW_TABLE);

        assertEquals(0, mirrored);
        assertEquals(0, ((KahluaTable) modData.rawget("LSHiddenSkills")).size());
    }

    @Test
    void extraFieldsOnAnEntryAreNotCopied() {
        // The mirror is rebuilt with exactly slots 1..3 — a payload can't smuggle extra
        // server-side state inside a skill entry.
        KahluaTable skills = table();
        KahluaTable yoga = entry(4.0, 320.0, 1000.0);
        yoga.rawset("evil", table());
        yoga.rawset(4.0, "junk");
        skills.rawset("Yoga", yoga);
        KahluaTable modData = table();

        int mirrored = SyncHiddenSkillsHandler.mirrorHiddenSkills(skills, modData, NEW_TABLE);

        assertEquals(1, mirrored);
        KahluaTable mirroredYoga =
                (KahluaTable) ((KahluaTable) modData.rawget("LSHiddenSkills")).rawget("Yoga");
        assertEquals(4.0, mirroredYoga.rawget(1.0));
        assertNull(mirroredYoga.rawget("evil"));
        assertNull(mirroredYoga.rawget(4.0));
    }
}
