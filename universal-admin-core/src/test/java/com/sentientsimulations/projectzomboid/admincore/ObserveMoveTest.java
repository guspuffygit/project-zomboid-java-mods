package com.sentientsimulations.projectzomboid.admincore;

import static org.junit.jupiter.api.Assertions.*;

import org.junit.jupiter.api.Test;

class ObserveMoveTest {
    @Test
    void waitsForArrivalButRetriesLostRelocation() {
        ObserveMove move = new ObserveMove(100, 200, 1, 1_000_000_000L);
        assertTrue(move.waiting(10, 20, 0, 3_000_000_000L));
        assertFalse(move.waiting(102, 202, 1, 3_000_000_000L));
        assertTrue(move.waiting(100, 200, 0, 3_000_000_000L));
        assertFalse(move.waiting(10, 20, 0, 7_000_000_000L));
    }
}
