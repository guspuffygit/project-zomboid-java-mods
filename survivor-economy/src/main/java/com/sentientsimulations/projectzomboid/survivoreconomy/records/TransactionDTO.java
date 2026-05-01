package com.sentientsimulations.projectzomboid.survivoreconomy.records;

import org.jspecify.annotations.Nullable;

/** Public-facing transaction shape (id is omitted; event_id is the stable external identifier). */
public record TransactionDTO(
        String eventId,
        String eventRole,
        long timestampMs,
        String type,
        @Nullable String parentEventId,
        @Nullable String reason,
        String playerUsername,
        long playerSteamId,
        String currency,
        double amount,
        @Nullable String itemId,
        @Nullable Integer itemQty,
        @Nullable String vehicleId,
        @Nullable String shopCategory,
        @Nullable String walletId,
        @Nullable String accountNumber,
        @Nullable Double deathX,
        @Nullable Double deathY,
        @Nullable Double deathZ) {

    public static TransactionDTO from(TransactionEntry e) {
        return new TransactionDTO(
                e.eventId(),
                e.eventRole(),
                e.timestampMs(),
                e.type(),
                e.parentEventId(),
                e.reason(),
                e.playerUsername(),
                e.playerSteamId(),
                e.currency(),
                e.amount(),
                e.itemId(),
                e.itemQty(),
                e.vehicleId(),
                e.shopCategory(),
                e.walletId(),
                e.accountNumber(),
                e.deathX(),
                e.deathY(),
                e.deathZ());
    }
}
