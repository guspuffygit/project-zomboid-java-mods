package com.sentientsimulations.projectzomboid.survivorleaderboard;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class SurvivorLeaderboardEndpointsTest {

    @Test
    void parseLimit_nullReturnsDefault() {
        assertEquals(
                SurvivorLeaderboardEndpoints.DEFAULT_LIMIT,
                SurvivorLeaderboardEndpoints.parseLimit(null));
    }

    @Test
    void parseLimit_validPositiveReturnsValue() {
        assertEquals(5, SurvivorLeaderboardEndpoints.parseLimit("5"));
    }

    @Test
    void parseLimit_largeValueReturnsValue() {
        assertEquals(10_000, SurvivorLeaderboardEndpoints.parseLimit("10000"));
    }

    @Test
    void parseLimit_zeroReturnsDefault() {
        assertEquals(
                SurvivorLeaderboardEndpoints.DEFAULT_LIMIT,
                SurvivorLeaderboardEndpoints.parseLimit("0"));
    }

    @Test
    void parseLimit_negativeReturnsDefault() {
        assertEquals(
                SurvivorLeaderboardEndpoints.DEFAULT_LIMIT,
                SurvivorLeaderboardEndpoints.parseLimit("-3"));
    }

    @Test
    void parseLimit_nonNumericReturnsDefault() {
        assertEquals(
                SurvivorLeaderboardEndpoints.DEFAULT_LIMIT,
                SurvivorLeaderboardEndpoints.parseLimit("abc"));
    }

    @Test
    void parseLimit_trimsWhitespace() {
        assertEquals(7, SurvivorLeaderboardEndpoints.parseLimit("  7  "));
    }
}
