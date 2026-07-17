package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.HashMap;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import se.krka.kahlua.j2se.KahluaTableImpl;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.skills.PerkFactory;

/**
 * Pure-math tests for the per-perk target XP / obelisk-match helpers used by {@link
 * RecoverSkillsHandler#applySkillsAuthoritatively}. Recovery is additive on top of the live
 * character's current XP, minus what a previous recovery already granted (the ledger) — so XP
 * earned by playing is never wiped, but chaining a high-Running death into a high-Strength death
 * can't accumulate both.
 */
class RecoverSkillsHandlerTest {

    /**
     * Seed Strength + Running with vanilla-shaped XP curves so {@link
     * PerkFactory.Perk#getTotalXpForLevel} returns sensible numbers without calling {@code
     * PerkFactory.init()} (which needs the Translator / file system).
     */
    @BeforeAll
    static void seedPerkXpTables() {
        setXp(
                PerkFactory.Perks.Strength,
                1000,
                2000,
                4000,
                6000,
                12000,
                20000,
                40000,
                60000,
                80000,
                100000);
        setXp(PerkFactory.Perks.Cooking, 50, 100, 200, 500, 1000, 2000, 3000, 4000, 5000, 6000);
    }

    private static void setXp(
            PerkFactory.Perk perk,
            int xp1,
            int xp2,
            int xp3,
            int xp4,
            int xp5,
            int xp6,
            int xp7,
            int xp8,
            int xp9,
            int xp10) {
        perk.xp1 = (int) (xp1 * 1.5F);
        perk.xp2 = (int) (xp2 * 1.5F);
        perk.xp3 = (int) (xp3 * 1.5F);
        perk.xp4 = (int) (xp4 * 1.5F);
        perk.xp5 = (int) (xp5 * 1.5F);
        perk.xp6 = (int) (xp6 * 1.5F);
        perk.xp7 = (int) (xp7 * 1.5F);
        perk.xp8 = (int) (xp8 * 1.5F);
        perk.xp9 = (int) (xp9 * 1.5F);
        perk.xp10 = (int) (xp10 * 1.5F);
    }

    @Test
    void firstRecoveryAddsOnTopOfCurrentXp() {
        // Live character grinded 1000 Cooking XP since respawn, never recovered before. Recovery
        // adds the full saved amount on top — the grind is kept, not overwritten.
        float target =
                RecoverSkillsHandler.computeAdditiveTargetXp(
                        PerkFactory.Perks.Cooking, 1000f, 3000f, 0f, 1.0F);
        assertEquals(4000f, target);
    }

    @Test
    void savedXpZeroWithNoPreviousGrantIsNoOp() {
        // Dead character never earned Cooking; live character grinded 1000. Nothing to add,
        // nothing to subtract — earned XP survives untouched.
        float target =
                RecoverSkillsHandler.computeAdditiveTargetXp(
                        PerkFactory.Perks.Cooking, 1000f, 0f, 0f, 1.0F);
        assertEquals(1000f, target);
    }

    @Test
    void switchingDeathsSubtractsPreviousGrantBeforeAdding() {
        // Recovery #1 granted 3000 Cooking XP (the ledger). The player then recovers a different
        // death worth 500. Target = current − 3000 + 500: the two grants swap, they never stack.
        float current = 1000f + 3000f; // 1000 earned by playing + previous grant
        float target =
                RecoverSkillsHandler.computeAdditiveTargetXp(
                        PerkFactory.Perks.Cooking, current, 500f, 3000f, 1.0F);
        assertEquals(1500f, target);
    }

    @Test
    void reRecoveringSameDeathIsNoOp() {
        // Same death, same percent: the desired grant equals the ledger, delta is zero. Spamming
        // the obelisk on one death farms nothing.
        float target =
                RecoverSkillsHandler.computeAdditiveTargetXp(
                        PerkFactory.Perks.Cooking, 4000f, 3000f, 3000f, 1.0F);
        assertEquals(4000f, target);
    }

    @Test
    void switchingToDeathWithoutPerkRemovesOnlyTheGrant() {
        // Previous recovery granted 3000; the newly recovered death has xp=0 in this perk. Only
        // the grant is walked back — the 1000 XP earned by playing stays.
        float target =
                RecoverSkillsHandler.computeAdditiveTargetXp(
                        PerkFactory.Perks.Cooking, 4000f, 0f, 3000f, 1.0F);
        assertEquals(1000f, target);
    }

    @Test
    void percentScalesOnlyTheNewGrant() {
        // 50% recovery of 10000 saved XP adds 5000; the previous grant is subtracted at the full
        // amount it originally landed as, not rescaled.
        float target =
                RecoverSkillsHandler.computeAdditiveTargetXp(
                        PerkFactory.Perks.Cooking, 2000f, 10000f, 1000f, 0.5F);
        assertEquals(6000f, target);
    }

    @Test
    void targetClampsAtLevelTenMax() {
        // Saved XP wildly exceeds level 10. Recovery shouldn't try to push past the cap, since
        // AddXP would no-op there anyway and the log line would lie about delta.
        float saved = PerkFactory.Perks.Strength.getTotalXpForLevel(10) * 10f;
        float target =
                RecoverSkillsHandler.computeAdditiveTargetXp(
                        PerkFactory.Perks.Strength, 0f, saved, 0f, 1.0F);
        assertEquals(PerkFactory.Perks.Strength.getTotalXpForLevel(10), target);
    }

    @Test
    void targetFloorsAtZeroWhenGrantExceedsCurrent() {
        // Defensive: if something outside this mod drained XP below the ledgered grant, walking
        // the grant back must not drive XP negative.
        float target =
                RecoverSkillsHandler.computeAdditiveTargetXp(
                        PerkFactory.Perks.Cooking, 100f, 0f, 500f, 1.0F);
        assertEquals(0f, target);
    }

    @Test
    void hiddenSkillHigherSavedLevelRestoresLevelAndScaledXp() {
        RecoverSkillsHandler.HiddenSkillRestore restore =
                RecoverSkillsHandler.computeHiddenSkillRestore(1, 200.0, 4, 321.0, 0.5F);
        assertEquals(4, restore.level());
        // Within-level XP scales by percent (floored); the level restores in full because
        // Lifestyles' per-level thresholds only exist in its Lua.
        assertEquals(160.0, restore.xp());
    }

    @Test
    void hiddenSkillSameLevelOnlyRaisesXp() {
        RecoverSkillsHandler.HiddenSkillRestore restore =
                RecoverSkillsHandler.computeHiddenSkillRestore(4, 100.0, 4, 500.0, 1.0F);
        assertEquals(4, restore.level());
        assertEquals(500.0, restore.xp());
    }

    @Test
    void hiddenSkillSameLevelLowerScaledXpIsNoOp() {
        // Live character re-earned more within-level XP than the scaled saved amount — the
        // restore must not walk it back.
        assertNull(RecoverSkillsHandler.computeHiddenSkillRestore(4, 400.0, 4, 500.0, 0.5F));
    }

    @Test
    void hiddenSkillLowerSavedLevelIsNoOp() {
        // Live character out-leveled the death snapshot; recovery never downgrades.
        assertNull(RecoverSkillsHandler.computeHiddenSkillRestore(6, 0.0, 4, 900.0, 1.0F));
    }

    @Test
    void hiddenSkillReRecoveringSameStateIsIdempotent() {
        // After a full restore the live state equals the saved state — a second recovery of the
        // same death finds nothing to raise.
        assertNull(RecoverSkillsHandler.computeHiddenSkillRestore(4, 500.0, 4, 500.0, 1.0F));
    }

    @Test
    void obeliskTypeMatchReturnsTrue() {
        assertTrue(RecoverSkillsHandler.isObeliskTypeMatch("Running", "Running"));
    }

    @Test
    void obeliskTypeMismatchReturnsFalse() {
        assertFalse(RecoverSkillsHandler.isObeliskTypeMatch("Running", "Strength"));
    }

    @Test
    void obeliskTypeNoneNeverMatches() {
        // The "None" sentinel must never match a real perk id, even one literally named "None".
        assertFalse(RecoverSkillsHandler.isObeliskTypeMatch("None", "Running"));
    }

    @Test
    void obeliskTypeNullNeverMatches() {
        assertFalse(RecoverSkillsHandler.isObeliskTypeMatch(null, "Running"));
    }

    @Test
    void songFieldsFromFullRowCopyVerbatim() {
        KahluaTable entry = new KahluaTableImpl(new HashMap<>());
        RecoverSkillsHandler.setSongFields(
                entry,
                new SurvivorSkillObeliskRepository.LearnedSongRow(
                        "Piano", "ContextMenu_02_01_P", "Piano02AmazingGrace", 2.0, 135.0, 1.0));

        assertEquals("ContextMenu_02_01_P", entry.rawget("name"));
        assertEquals("Piano02AmazingGrace", entry.rawget("sound"));
        assertEquals(2.0, entry.rawget("level"));
        assertEquals(135.0, entry.rawget("length"));
        assertEquals(1.0, entry.rawget("isaddon"));
    }

    /**
     * Rows saved before the level/length/isaddon columns existed read back null. Lifestyles does
     * {@code v.length * 48} on every learned entry, so a nil numeric field crashes its context
     * menus — every numeric field must be present even when the row has no value.
     */
    @Test
    void songFieldsFromLegacyRowNeverOmitNumerics() {
        KahluaTable entry = new KahluaTableImpl(new HashMap<>());
        RecoverSkillsHandler.setSongFields(
                entry,
                new SurvivorSkillObeliskRepository.LearnedSongRow(
                        "Piano", "ContextMenu_02_01_P", null, null, null, null));

        assertEquals("ContextMenu_02_01_P", entry.rawget("name"));
        assertNull(entry.rawget("sound"));
        assertEquals(1.0, entry.rawget("level"));
        assertEquals(60.0, entry.rawget("length"));
        assertEquals(0.0, entry.rawget("isaddon"));
    }
}
