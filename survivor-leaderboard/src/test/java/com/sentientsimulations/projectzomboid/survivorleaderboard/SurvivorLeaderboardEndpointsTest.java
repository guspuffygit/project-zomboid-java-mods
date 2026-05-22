package com.sentientsimulations.projectzomboid.survivorleaderboard;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

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

    @Test
    void parseLimitWithMax_clampsLargeValues() {
        assertEquals(
                SurvivorLeaderboardEndpoints.KILL_LOG_MAX_LIMIT,
                SurvivorLeaderboardEndpoints.parseLimit(
                        "10000",
                        SurvivorLeaderboardEndpoints.KILL_LOG_DEFAULT_LIMIT,
                        SurvivorLeaderboardEndpoints.KILL_LOG_MAX_LIMIT));
    }

    @Test
    void parseLimitWithMax_nullReturnsDefault() {
        assertEquals(
                SurvivorLeaderboardEndpoints.KILL_LOG_DEFAULT_LIMIT,
                SurvivorLeaderboardEndpoints.parseLimit(
                        null,
                        SurvivorLeaderboardEndpoints.KILL_LOG_DEFAULT_LIMIT,
                        SurvivorLeaderboardEndpoints.KILL_LOG_MAX_LIMIT));
    }

    @Test
    void parseLimitWithMax_validPositiveReturnsValue() {
        assertEquals(
                25,
                SurvivorLeaderboardEndpoints.parseLimit(
                        "25",
                        SurvivorLeaderboardEndpoints.KILL_LOG_DEFAULT_LIMIT,
                        SurvivorLeaderboardEndpoints.KILL_LOG_MAX_LIMIT));
    }

    @Test
    void parseUsernameParam_nullOrBlankReturnsNull() {
        assertNull(SurvivorLeaderboardEndpoints.parseUsernameParam(null));
        assertNull(SurvivorLeaderboardEndpoints.parseUsernameParam(""));
        assertNull(SurvivorLeaderboardEndpoints.parseUsernameParam("   "));
    }

    @Test
    void parseUsernameParam_trimsAndReturns() {
        assertEquals("alice", SurvivorLeaderboardEndpoints.parseUsernameParam("alice"));
        assertEquals("alice", SurvivorLeaderboardEndpoints.parseUsernameParam("  alice  "));
    }

    @Test
    void parseSteamIdParam_nullOrBlankReturnsNull() {
        assertNull(SurvivorLeaderboardEndpoints.parseSteamIdParam(null));
        assertNull(SurvivorLeaderboardEndpoints.parseSteamIdParam(""));
        assertNull(SurvivorLeaderboardEndpoints.parseSteamIdParam("   "));
    }

    @Test
    void parseSteamIdParam_validNumericReturnsLong() {
        assertEquals(12345L, SurvivorLeaderboardEndpoints.parseSteamIdParam("12345"));
        assertEquals(12345L, SurvivorLeaderboardEndpoints.parseSteamIdParam("  12345  "));
    }

    @Test
    void parseSteamIdParam_invalidThrows() {
        assertThrows(
                NumberFormatException.class,
                () -> SurvivorLeaderboardEndpoints.parseSteamIdParam("abc"));
        assertThrows(
                NumberFormatException.class,
                () -> SurvivorLeaderboardEndpoints.parseSteamIdParam("12.5"));
    }

    @Test
    void parseKillCountParam_nullOrBlankReturnsNull() {
        assertNull(SurvivorLeaderboardEndpoints.parseKillCountParam(null));
        assertNull(SurvivorLeaderboardEndpoints.parseKillCountParam(""));
        assertNull(SurvivorLeaderboardEndpoints.parseKillCountParam("   "));
    }

    @Test
    void parseKillCountParam_validIntReturnsValue() {
        assertEquals(0, SurvivorLeaderboardEndpoints.parseKillCountParam("0"));
        assertEquals(42, SurvivorLeaderboardEndpoints.parseKillCountParam("42"));
        assertEquals(42, SurvivorLeaderboardEndpoints.parseKillCountParam("  42  "));
    }

    @Test
    void parseKillCountParam_negativeAllowed() {
        // Negative values mirror the ally-grief penalty convention — admins must be able to set
        // them too.
        assertEquals(-5, SurvivorLeaderboardEndpoints.parseKillCountParam("-5"));
    }

    @Test
    void parseKillCountParam_invalidThrows() {
        assertThrows(
                NumberFormatException.class,
                () -> SurvivorLeaderboardEndpoints.parseKillCountParam("abc"));
        assertThrows(
                NumberFormatException.class,
                () -> SurvivorLeaderboardEndpoints.parseKillCountParam("3.5"));
    }
}
