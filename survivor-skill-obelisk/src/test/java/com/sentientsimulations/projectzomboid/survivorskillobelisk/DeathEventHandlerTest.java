package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import zombie.characters.skills.PerkFactory;

/**
 * Pure-math tests for the creation-grant subtraction logic that {@link DeathEventHandler} uses when
 * persisting per-perk XP. Exercises {@link DeathEventHandler#combineGrantedLevels} and {@link
 * DeathEventHandler#computeXpToSave} so we don't have to stand up an {@code IsoPlayer} (which pulls
 * in the entire game runtime).
 */
class DeathEventHandlerTest {

    /**
     * The static {@code PerkFactory.Perks.*} {@code Perk} instances exist as soon as the class
     * loads, but their {@code xp1..xp10} fields are zero until {@code PerkFactory.init()} runs. Set
     * the vanilla values directly so {@link PerkFactory.Perk#getTotalXpForLevel} returns production
     * numbers — without calling {@code init()}, which needs {@code Translator} (file system) and
     * would touch global state shared with other tests.
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
        setXp(PerkFactory.Perks.Blunt, 50, 100, 200, 500, 1000, 2000, 3000, 4000, 5000, 6000);
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
    void vanillaBaselineFitnessAndStrengthAreFive() {
        Map<PerkFactory.Perk, Integer> levels =
                DeathEventHandler.combineGrantedLevels(List.of(), null);
        assertEquals(5, levels.get(PerkFactory.Perks.Strength));
        assertEquals(5, levels.get(PerkFactory.Perks.Fitness));
        assertFalse(
                levels.containsKey(PerkFactory.Perks.Blunt),
                "untouched perks should not appear in the map");
    }

    @Test
    void traitBoostsSumWithBaseline() {
        Map<PerkFactory.Perk, Integer> strongTrait = new HashMap<>();
        strongTrait.put(PerkFactory.Perks.Strength, 4);

        Map<PerkFactory.Perk, Integer> levels =
                DeathEventHandler.combineGrantedLevels(List.of(strongTrait), null);

        assertEquals(9, levels.get(PerkFactory.Perks.Strength));
        assertEquals(5, levels.get(PerkFactory.Perks.Fitness));
    }

    @Test
    void negativeTraitBoostClampsToZero() {
        Map<PerkFactory.Perk, Integer> heavyPenalty = new HashMap<>();
        heavyPenalty.put(PerkFactory.Perks.Strength, -10);

        Map<PerkFactory.Perk, Integer> levels =
                DeathEventHandler.combineGrantedLevels(List.of(heavyPenalty), null);

        assertEquals(0, levels.get(PerkFactory.Perks.Strength));
    }

    @Test
    void boostsCapAtTen() {
        Map<PerkFactory.Perk, Integer> t1 = new HashMap<>();
        t1.put(PerkFactory.Perks.Strength, 4);
        Map<PerkFactory.Perk, Integer> t2 = new HashMap<>();
        t2.put(PerkFactory.Perks.Strength, 4);

        Map<PerkFactory.Perk, Integer> levels =
                DeathEventHandler.combineGrantedLevels(List.of(t1, t2), null);

        // 5 + 4 + 4 = 13, clamped to 10.
        assertEquals(10, levels.get(PerkFactory.Perks.Strength));
    }

    @Test
    void professionBoostsAddOnTopOfTraits() {
        Map<PerkFactory.Perk, Integer> trait = new HashMap<>();
        trait.put(PerkFactory.Perks.Blunt, 1);
        Map<PerkFactory.Perk, Integer> profession = new HashMap<>();
        profession.put(PerkFactory.Perks.Blunt, 2);

        Map<PerkFactory.Perk, Integer> levels =
                DeathEventHandler.combineGrantedLevels(List.of(trait), profession);

        assertEquals(3, levels.get(PerkFactory.Perks.Blunt));
    }

    @Test
    void unrelatedPerksStayUnboosted() {
        Map<PerkFactory.Perk, Integer> trait = new HashMap<>();
        trait.put(PerkFactory.Perks.Strength, 2);

        Map<PerkFactory.Perk, Integer> levels =
                DeathEventHandler.combineGrantedLevels(List.of(trait), null);

        assertFalse(levels.containsKey(PerkFactory.Perks.Blunt));
    }

    @Test
    void nullProfessionIsHandled() {
        Map<PerkFactory.Perk, Integer> trait = new HashMap<>();
        trait.put(PerkFactory.Perks.Strength, 1);

        Map<PerkFactory.Perk, Integer> levels =
                DeathEventHandler.combineGrantedLevels(List.of(trait), null);

        assertEquals(6, levels.get(PerkFactory.Perks.Strength));
    }

    @Test
    void nullTraitMapInListIsSkipped() {
        Map<PerkFactory.Perk, Integer> trait = new HashMap<>();
        trait.put(PerkFactory.Perks.Strength, 1);

        Map<PerkFactory.Perk, Integer> levels =
                DeathEventHandler.combineGrantedLevels(java.util.Arrays.asList(trait, null), null);

        assertEquals(6, levels.get(PerkFactory.Perks.Strength));
    }

    @Test
    void computeXpToSaveZeroRawXp() {
        float saved = DeathEventHandler.computeXpToSave(0f, 2, PerkFactory.Perks.Strength);
        assertEquals(0f, saved);
    }

    @Test
    void computeXpToSaveImmediateDeathSavesZero() {
        // Player dies the moment they spawn — rawXp equals exactly the creation grant.
        float granted = PerkFactory.Perks.Strength.getTotalXpForLevel(2);
        float saved = DeathEventHandler.computeXpToSave(granted, 2, PerkFactory.Perks.Strength);
        assertEquals(0f, saved);
    }

    @Test
    void computeXpToSaveLeveledUpSavesEarnedOnly() {
        // Character was granted Strength=2 at creation but reached level 5 through play. Save
        // should be the cumulative XP for levels 3-5 only (level-5 total minus level-2 total).
        float rawXp = PerkFactory.Perks.Strength.getTotalXpForLevel(5);
        float grantedXp = PerkFactory.Perks.Strength.getTotalXpForLevel(2);
        float saved = DeathEventHandler.computeXpToSave(rawXp, 2, PerkFactory.Perks.Strength);
        assertEquals(rawXp - grantedXp, saved);
        assertTrue(saved > 0f);
    }

    @Test
    void computeXpToSaveNoGrantSavesEverything() {
        float saved = DeathEventHandler.computeXpToSave(12345f, 0, PerkFactory.Perks.Strength);
        assertEquals(12345f, saved);
    }

    @Test
    void computeXpToSaveBelowGrantClampsToZero() {
        // Defensive: if rawXp < granted (Lifestyles mutated xpBoostMap mid-game, etc.) save 0
        // rather than going negative.
        float granted = PerkFactory.Perks.Strength.getTotalXpForLevel(5);
        float saved =
                DeathEventHandler.computeXpToSave(granted - 100f, 5, PerkFactory.Perks.Strength);
        assertEquals(0f, saved);
    }

    @Test
    void computeEarnedXpSubtractsBaseline() {
        assertEquals(500f, DeathEventHandler.computeEarnedXp(1500f, 1000f));
    }

    @Test
    void computeEarnedXpImmediateDeathSavesZero() {
        // Dying right after spawn: raw XP still equals the creation baseline exactly.
        assertEquals(0f, DeathEventHandler.computeEarnedXp(1000f, 1000f));
    }

    @Test
    void computeEarnedXpPerkAbsentFromBaselineSavesEverything() {
        // Perk added by a game update or mod after the character was created — nothing was
        // granted, so all of it was earned.
        assertEquals(1500f, DeathEventHandler.computeEarnedXp(1500f, null));
    }

    @Test
    void computeEarnedXpDecayBelowBaselineClampsToZero() {
        // Strength/Fitness XP can decay below the creation grant via XpUpdate.lua's get-lazy
        // timers; save 0 rather than going negative.
        assertEquals(0f, DeathEventHandler.computeEarnedXp(900f, 1000f));
    }
}
