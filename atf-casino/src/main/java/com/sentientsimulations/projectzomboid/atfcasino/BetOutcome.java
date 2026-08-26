package com.sentientsimulations.projectzomboid.atfcasino;

import org.jetbrains.annotations.Nullable;

/**
 * Result of resolving one wager. {@code payout} is the gross amount returned to the player — the
 * wager is already gone by the time a game resolves, so a payout of {@code wager} is a push and a
 * payout of 0 is a total loss.
 */
public record BetOutcome(int payout, @Nullable String resultId, @Nullable String detail) {

    public static BetOutcome loss(@Nullable String resultId) {
        return new BetOutcome(0, resultId, null);
    }

    public static BetOutcome win(int payout, @Nullable String resultId) {
        return new BetOutcome(payout, resultId, null);
    }

    public boolean isWin() {
        return payout > 0;
    }
}
