package com.sentientsimulations.projectzomboid.survivoreconomy.records;

import org.jspecify.annotations.Nullable;

/**
 * Outcome of a player→player transfer attempt. On success {@code eventId} is the generated paired
 * event id and {@code failureReason} is null. On failure {@code eventId} is null and {@code
 * failureReason} carries the rejection cause.
 */
public record TransferResult(
        @Nullable String eventId, @Nullable TransferFailureReason failureReason) {

    public boolean ok() {
        return eventId != null;
    }

    public static TransferResult success(String eventId) {
        return new TransferResult(eventId, null);
    }

    public static TransferResult failure(TransferFailureReason reason) {
        return new TransferResult(null, reason);
    }
}
