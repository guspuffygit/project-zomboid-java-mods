package com.sentientsimulations.projectzomboid.admincore;

import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertSame;

import org.junit.jupiter.api.Test;

class ObserveFailureTest {
    @Test
    void failedSelectionRestoresOriginalAndClearsObservation() throws Exception {
        Object original = new Object();
        AdminCoreObserveCamera.follow("test-target");
        assertSame(
                original,
                AdminCoreObserveCamera.selectSafely(
                        original,
                        () -> {
                            throw new IllegalStateException("target disappeared during selection");
                        }));
        var username = AdminCoreObserveCamera.class.getDeclaredField("username");
        username.setAccessible(true);
        assertNull(username.get(null));
        assertNull(AdminCoreObserveCamera.select(null));
    }

    @Test
    void missingEngineMethodAlsoDegradesSafely() {
        Object original = new Object();
        assertSame(
                original,
                AdminCoreObserveCamera.selectSafely(
                        original,
                        () -> {
                            throw new NoSuchMethodError("changed engine API");
                        }));
    }
}
