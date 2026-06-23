package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import zombie.characters.skills.PerkFactory;

/**
 * Pure-math tests for the per-perk target XP / obelisk-match helpers used by {@link
 * RecoverSkillsHandler#applySkillsAuthoritatively}. These cover the "saved xp=0 means reset to
 * baseline" behavior that lets each obelisk recovery wipe perks the dead character never earned —
 * so chaining a high-Running death and a high-Strength death can't accumulate to both high.
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
    void savedXpZeroWithBaselineGrantResetsToBaselineXp() {
        // Dead character had Strength at the granted baseline (5) with no earned XP. The recovery
        // target is the level-5 XP — even if the live character has farmed Strength above
        // baseline since respawn, the recovery walks them back down. This is what makes
        // recovering "Death B (high Cooking only)" wipe the Strength a different death pumped up.
        float target =
                RecoverSkillsHandler.computeRecoveryTargetXp(
                        PerkFactory.Perks.Strength, 0f, 5, 1.0F);
        assertEquals(PerkFactory.Perks.Strength.getTotalXpForLevel(5), target);
    }

    @Test
    void savedXpZeroWithNoGrantResetsToZero() {
        // Dead character had Cooking at 0 with no earned XP and no profession boost. The
        // recovery target is 0 — wipes any Cooking XP the live character has grinded.
        float target =
                RecoverSkillsHandler.computeRecoveryTargetXp(
                        PerkFactory.Perks.Cooking, 0f, 0, 1.0F);
        assertEquals(0f, target);
    }

    @Test
    void savedXpAddsToBaselineAtFullPercent() {
        // Dead character earned 3 levels of Strength above their level-5 grant. With 100%
        // recovery the live character ends up at level 8.
        float saved =
                PerkFactory.Perks.Strength.getTotalXpForLevel(8)
                        - PerkFactory.Perks.Strength.getTotalXpForLevel(5);
        float target =
                RecoverSkillsHandler.computeRecoveryTargetXp(
                        PerkFactory.Perks.Strength, saved, 5, 1.0F);
        assertEquals(PerkFactory.Perks.Strength.getTotalXpForLevel(8), target);
    }

    @Test
    void savedXpScalesByPercent() {
        float target =
                RecoverSkillsHandler.computeRecoveryTargetXp(
                        PerkFactory.Perks.Cooking, 10000f, 0, 0.5F);
        assertEquals(5000f, target);
    }

    @Test
    void savedXpScaledTargetAddsOnTopOfBaseline() {
        // Baseline grant level 5 + 50% of 10000 saved XP. The percent scales only the recovered
        // earnings; the baseline is always restored in full.
        float target =
                RecoverSkillsHandler.computeRecoveryTargetXp(
                        PerkFactory.Perks.Strength, 10000f, 5, 0.5F);
        assertEquals(PerkFactory.Perks.Strength.getTotalXpForLevel(5) + 5000f, target);
    }

    @Test
    void targetClampsAtLevelTenMax() {
        // Saved XP wildly exceeds level 10. Recovery shouldn't try to push past the cap, since
        // AddXP would no-op there anyway and the log line would lie about delta.
        float saved = PerkFactory.Perks.Strength.getTotalXpForLevel(10) * 10f;
        float target =
                RecoverSkillsHandler.computeRecoveryTargetXp(
                        PerkFactory.Perks.Strength, saved, 0, 1.0F);
        assertEquals(PerkFactory.Perks.Strength.getTotalXpForLevel(10), target);
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
}
