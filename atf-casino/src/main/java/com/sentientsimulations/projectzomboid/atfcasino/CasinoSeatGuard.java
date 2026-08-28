package com.sentientsimulations.projectzomboid.atfcasino;

import zombie.characters.IsoPlayer;

/**
 * One player, one table: sitting down at a casino game first stands the player up from every other
 * game, so switching tables is a single click instead of an error. Each game's own leave path
 * settles the hand in flight (refunds, deferred leave) and the old window is closed on the client.
 */
public final class CasinoSeatGuard {

    private CasinoSeatGuard() {}

    /** Stands {@code player} up from every casino game except {@code game}. */
    static void standUpElsewhere(IsoPlayer player, CasinoGame game, long now) {
        if (game != CasinoGame.BLACKJACK) {
            BlackjackHandler.standUp(player, now);
        }
        if (game != CasinoGame.ROULETTE) {
            RouletteHandler.standUp(player, now);
        }
        if (game != CasinoGame.HOLDEM) {
            HoldemHandler.standUp(player, now);
        }
    }
}
