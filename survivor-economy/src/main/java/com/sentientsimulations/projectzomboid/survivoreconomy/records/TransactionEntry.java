package com.sentientsimulations.projectzomboid.survivoreconomy.records;

import org.jspecify.annotations.Nullable;

/** A single row read from {@code economy_transactions}. */
public record TransactionEntry(
        long id,
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
        @Nullable Double deathZ) {}
