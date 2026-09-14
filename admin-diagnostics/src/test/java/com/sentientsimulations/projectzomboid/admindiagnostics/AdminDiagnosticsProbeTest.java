package com.sentientsimulations.projectzomboid.admindiagnostics;

import static org.junit.jupiter.api.Assertions.*;

import org.junit.jupiter.api.Test;
import zombie.network.GameClient;

class AdminDiagnosticsProbeTest {
    @Test
    void readsLocalJvmCountersWithoutStartingAGameOrCollectingGarbage() {
        zombie.core.random.RandStandard.INSTANCE.init();
        boolean oldClient = GameClient.client;
        try {
            GameClient.client = false;
            assertNull(AdminDiagnosticsProbe.snapshot());
            GameClient.client = true;
            var snapshot = AdminDiagnosticsProbe.snapshot();
            double used = ((Number) snapshot.rawget("heapUsedMiB")).doubleValue();
            double committed = ((Number) snapshot.rawget("heapCommittedMiB")).doubleValue();
            double max = ((Number) snapshot.rawget("heapMaxMiB")).doubleValue();
            assertTrue(used >= 0 && used <= committed && committed <= max);
            assertTrue(((Number) snapshot.rawget("gcMillis")).doubleValue() >= 0);
            assertTrue(snapshot.rawget("uiGlobalVisible") instanceof Boolean);
            assertTrue(((Number) snapshot.rawget("sharedChunks")).doubleValue() >= 0);
            assertNull(
                    snapshot.rawget("pingMs"), "No connection must not be reported as zero ping");
        } finally {
            GameClient.client = oldClient;
        }
    }
}
