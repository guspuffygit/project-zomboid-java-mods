package com.sentientsimulations.projectzomboid.atfcasino;

import org.jetbrains.annotations.Nullable;

/**
 * One player, one table: a player may only hold a seat at one casino game at a time. Handlers call
 * this before seating someone; the seat itself still lives in each game's table, so leaving,
 * disconnect and presence enforcement release the player through the existing per-game paths.
 */
public final class CasinoSeatGuard {

    private CasinoSeatGuard() {}

    /**
     * Display name of the game the player is already seated at, or {@code null} if the player is
     * free to sit down at {@code game}.
     */
    public static @Nullable String seatedElsewhere(String username, CasinoGame game) {
        if (game != CasinoGame.BLACKJACK && BlackjackHandler.isSeated(username)) {
            return CasinoGame.BLACKJACK.getDisplayName();
        }
        if (game != CasinoGame.ROULETTE && RouletteHandler.isSeated(username)) {
            return CasinoGame.ROULETTE.getDisplayName();
        }
        if (game != CasinoGame.HOLDEM && HoldemHandler.isSeated(username)) {
            return CasinoGame.HOLDEM.getDisplayName();
        }
        return null;
    }
}
