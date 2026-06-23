package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class SurvivorSkillObeliskConfigTest {

    @BeforeEach
    void resetBefore() {
        SurvivorSkillObeliskConfig.resetToDefaults();
    }

    @AfterEach
    void resetAfter() {
        SurvivorSkillObeliskConfig.resetToDefaults();
    }

    @Test
    void defaultsMatchDeclaredConstants() {
        assertTrue(SurvivorSkillObeliskConfig.DEFAULT_RECOVER_SKILLS);
        assertTrue(SurvivorSkillObeliskConfig.isRecoverSkills());
        assertTrue(SurvivorSkillObeliskConfig.isRecoverRecipes());
        assertTrue(SurvivorSkillObeliskConfig.isRecoverSkillMagazines());
        assertTrue(SurvivorSkillObeliskConfig.isRecoverReadPrintMedia());
        assertTrue(SurvivorSkillObeliskConfig.isRecoverWatchedMedia());
        assertTrue(SurvivorSkillObeliskConfig.isRecoverLearnedSongs());
        assertTrue(SurvivorSkillObeliskConfig.isRecoverAmbitions());
        assertEquals(100, SurvivorSkillObeliskConfig.DEFAULT_SKILL_RECOVERY_PERCENT);
        assertEquals(100, SurvivorSkillObeliskConfig.getSkillRecoveryPercent());
    }

    @Test
    void setterRoundTripsEachBoolean() {
        SurvivorSkillObeliskConfig.setRecoverSkills(false);
        SurvivorSkillObeliskConfig.setRecoverRecipes(false);
        SurvivorSkillObeliskConfig.setRecoverSkillMagazines(false);
        SurvivorSkillObeliskConfig.setRecoverReadPrintMedia(false);
        SurvivorSkillObeliskConfig.setRecoverWatchedMedia(false);
        SurvivorSkillObeliskConfig.setRecoverLearnedSongs(false);
        SurvivorSkillObeliskConfig.setRecoverAmbitions(false);

        assertFalse(SurvivorSkillObeliskConfig.isRecoverSkills());
        assertFalse(SurvivorSkillObeliskConfig.isRecoverRecipes());
        assertFalse(SurvivorSkillObeliskConfig.isRecoverSkillMagazines());
        assertFalse(SurvivorSkillObeliskConfig.isRecoverReadPrintMedia());
        assertFalse(SurvivorSkillObeliskConfig.isRecoverWatchedMedia());
        assertFalse(SurvivorSkillObeliskConfig.isRecoverLearnedSongs());
        assertFalse(SurvivorSkillObeliskConfig.isRecoverAmbitions());

        SurvivorSkillObeliskConfig.setRecoverSkills(true);
        assertTrue(SurvivorSkillObeliskConfig.isRecoverSkills());
    }

    @Test
    void skillRecoveryPercentClampsToZeroLowerBound() {
        assertEquals(0, SurvivorSkillObeliskConfig.setSkillRecoveryPercent(-5));
        assertEquals(0, SurvivorSkillObeliskConfig.getSkillRecoveryPercent());
        assertEquals(0, SurvivorSkillObeliskConfig.setSkillRecoveryPercent(Integer.MIN_VALUE));
        assertEquals(0, SurvivorSkillObeliskConfig.getSkillRecoveryPercent());
    }

    @Test
    void skillRecoveryPercentClampsTo100UpperBound() {
        assertEquals(100, SurvivorSkillObeliskConfig.setSkillRecoveryPercent(150));
        assertEquals(100, SurvivorSkillObeliskConfig.getSkillRecoveryPercent());
        assertEquals(100, SurvivorSkillObeliskConfig.setSkillRecoveryPercent(Integer.MAX_VALUE));
        assertEquals(100, SurvivorSkillObeliskConfig.getSkillRecoveryPercent());
    }

    @Test
    void skillRecoveryPercentAcceptsInRangeValues() {
        assertEquals(0, SurvivorSkillObeliskConfig.setSkillRecoveryPercent(0));
        assertEquals(0, SurvivorSkillObeliskConfig.getSkillRecoveryPercent());
        assertEquals(50, SurvivorSkillObeliskConfig.setSkillRecoveryPercent(50));
        assertEquals(50, SurvivorSkillObeliskConfig.getSkillRecoveryPercent());
        assertEquals(100, SurvivorSkillObeliskConfig.setSkillRecoveryPercent(100));
        assertEquals(100, SurvivorSkillObeliskConfig.getSkillRecoveryPercent());
    }
}
