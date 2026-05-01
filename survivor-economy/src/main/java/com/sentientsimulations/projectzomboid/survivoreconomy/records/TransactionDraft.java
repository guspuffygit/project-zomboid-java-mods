package com.sentientsimulations.projectzomboid.survivoreconomy.records;

import org.jspecify.annotations.Nullable;

/**
 * Input shape for inserting a new economy transaction. {@code event_id} and {@code event_role} are
 * NOT included — they are assigned by {@link
 * com.sentientsimulations.projectzomboid.survivoreconomy.SurvivorEconomyRepository} when the row is
 * written, so that paired (FROM/TO) rows always share the same generated id and SOLE rows are
 * tagged correctly. {@code amount} is signed from the perspective of {@code playerUsername}: {@code
 * +} means the player gained that currency, {@code −} means lost.
 */
public record TransactionDraft(
        String type,
        long timestampMs,
        @Nullable String reason,
        @Nullable String parentEventId,
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

    /** Minimal draft with no type-specific metadata. All optional fields default to null. */
    public static TransactionDraft basic(
            String type,
            long timestampMs,
            String playerUsername,
            long playerSteamId,
            String currency,
            double amount) {
        return new TransactionDraft(
                type,
                timestampMs,
                null,
                null,
                playerUsername,
                playerSteamId,
                currency,
                amount,
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                null,
                null);
    }
}
