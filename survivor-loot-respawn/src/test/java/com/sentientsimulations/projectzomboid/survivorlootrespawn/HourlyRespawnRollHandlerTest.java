package com.sentientsimulations.projectzomboid.survivorlootrespawn;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

class HourlyRespawnRollHandlerTest {

    private static final double EPS = 1e-9;

    @Test
    void chanceAtZeroHoursReturnsMin() {
        double c = HourlyRespawnRollHandler.computeChance(0.0, 96, 5, 100, 1.05);
        assertEquals(5.0, c, EPS);
    }

    @Test
    void chanceAtMaxHoursReturnsMax() {
        double c = HourlyRespawnRollHandler.computeChance(96.0, 96, 0, 100, 1.05);
        assertEquals(100.0, c, EPS);
    }

    @Test
    void chanceClampsAboveMaxHours() {
        double c = HourlyRespawnRollHandler.computeChance(500.0, 96, 0, 100, 1.05);
        assertEquals(100.0, c, EPS);
    }

    @Test
    void chanceClampsBelowZeroHours() {
        double c = HourlyRespawnRollHandler.computeChance(-10.0, 96, 7, 100, 1.05);
        assertEquals(7.0, c, EPS);
    }

    @Test
    void midpointWithDefaultSteepnessIsSlightlyBelowLinear() {
        double c = HourlyRespawnRollHandler.computeChance(48.0, 96, 0, 100, 1.05);
        double expected = 100.0 * (Math.pow(1.05, 0.5) - 1.0) / (1.05 - 1.0);
        assertEquals(expected, c, EPS);
        assertTrue(c < 50.0, "convex curve must be below linear at midpoint, got " + c);
        assertTrue(c > 48.0, "default steepness is mild, midpoint should stay near linear");
    }

    @Test
    void higherSteepnessPushesChanceLater() {
        double mild = HourlyRespawnRollHandler.computeChance(48.0, 96, 0, 100, 1.05);
        double steep = HourlyRespawnRollHandler.computeChance(48.0, 96, 0, 100, 2.0);
        assertTrue(steep < mild, "higher steepness should yield lower midpoint chance");
    }

    @Test
    void steepnessOneFallsBackToLinear() {
        double c = HourlyRespawnRollHandler.computeChance(48.0, 96, 0, 100, 1.0);
        assertEquals(50.0, c, EPS);
    }

    @Test
    void steepnessBelowOneFallsBackToLinear() {
        double c = HourlyRespawnRollHandler.computeChance(24.0, 96, 0, 100, 0.5);
        assertEquals(25.0, c, EPS);
    }

    @Test
    void hoursTillMaxZeroShortCircuitsToMax() {
        double c = HourlyRespawnRollHandler.computeChance(1.0, 0, 5, 80, 1.05);
        assertEquals(80.0, c, EPS);
    }

    @Test
    void minAndMaxBothZeroAlwaysReturnsZero() {
        double c = HourlyRespawnRollHandler.computeChance(50.0, 96, 0, 0, 1.05);
        assertEquals(0.0, c, EPS);
    }

    @Test
    void minEqualsMaxReturnsThatValue() {
        double c = HourlyRespawnRollHandler.computeChance(10.0, 96, 25, 25, 1.05);
        assertEquals(25.0, c, EPS);
    }

    @Test
    void floorAndCeilingApplyAcrossCurve() {
        double atZero = HourlyRespawnRollHandler.computeChance(0.0, 96, 10, 90, 1.05);
        double atMax = HourlyRespawnRollHandler.computeChance(96.0, 96, 10, 90, 1.05);
        assertEquals(10.0, atZero, EPS);
        assertEquals(90.0, atMax, EPS);
    }
}
