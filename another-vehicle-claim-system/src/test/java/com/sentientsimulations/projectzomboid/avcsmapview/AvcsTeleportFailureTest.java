package com.sentientsimulations.projectzomboid.avcsmapview;

import static org.junit.jupiter.api.Assertions.*;

import java.util.LinkedHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;

class AvcsTeleportFailureTest {
    private static AvcsAdminVehicleTeleport.Job job(int id) {
        return new AvcsAdminVehicleTeleport.Job(
                id,
                (double) id,
                null,
                "admin",
                new AvcsAdminVehicleTeleport.Target(10, 20),
                0,
                0,
                100);
    }

    @Test
    void queuedFailureIsRemovedOnceAndDoesNotStopOtherJobs() {
        var pending = new LinkedHashMap<Integer, AvcsAdminVehicleTeleport.Job>();
        pending.put(1, job(1));
        pending.put(2, job(2));
        var errors = new AtomicInteger();
        var remaining = new AtomicInteger();
        AvcsAdminVehicleTeleport.tickPending(
                pending,
                j -> {
                    if (j.sqlId == 1) throw new IllegalStateException("chunk load failed");
                    remaining.incrementAndGet();
                    return false;
                },
                (j, e) -> {
                    assertEquals(1, j.sqlId);
                    errors.incrementAndGet();
                });
        assertEquals(1, errors.get());
        assertEquals(1, remaining.get());
        assertFalse(pending.containsKey(1));
        assertTrue(pending.containsKey(2));
    }

    @Test
    void moveFailureDoesNotEmitSuccessAndQueuedCompletionCleansUpOnce() {
        var pending = new LinkedHashMap<Integer, AvcsAdminVehicleTeleport.Job>();
        pending.put(1, job(1));
        var errors = new AtomicInteger();
        var successes = new AtomicInteger();
        AvcsAdminVehicleTeleport.tickPending(
                pending,
                j -> {
                    AvcsAdminVehicleTeleport.complete(
                            j,
                            () -> {
                                throw new IllegalStateException("move failed");
                            },
                            reason -> successes.incrementAndGet(),
                            (failed, error) -> errors.incrementAndGet());
                    return true;
                },
                (j, e) ->
                        fail("already handled movement failure must not trigger a second failure"));
        assertEquals(1, errors.get());
        assertEquals(0, successes.get());
        assertTrue(pending.isEmpty());
    }

    @Test
    void completedJobIsRemovedEvenIfFailureDeliveryThrows() {
        var pending = new LinkedHashMap<Integer, AvcsAdminVehicleTeleport.Job>();
        pending.put(1, job(1));
        assertThrows(
                IllegalStateException.class,
                () ->
                        AvcsAdminVehicleTeleport.tickPending(
                                pending,
                                j -> {
                                    throw new IllegalStateException("move failed");
                                },
                                (j, e) -> {
                                    throw new IllegalStateException("connection closed");
                                }));
        assertTrue(pending.isEmpty());
    }

    @Test
    void repliesOnlyUseAStillConnectedInitiator() {
        var replies = new AtomicInteger();
        AvcsAdminVehicleTeleport.replyIfConnected(() -> false, replies::incrementAndGet);
        assertEquals(0, replies.get());
        AvcsAdminVehicleTeleport.replyIfConnected(() -> true, replies::incrementAndGet);
        assertEquals(1, replies.get());
    }
}
