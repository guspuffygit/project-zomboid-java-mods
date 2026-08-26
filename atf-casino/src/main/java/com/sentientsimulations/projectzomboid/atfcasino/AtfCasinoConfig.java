package com.sentientsimulations.projectzomboid.atfcasino;

import zombie.SandboxOptions;
import zombie.config.BooleanConfigOption;
import zombie.config.ConfigOption;
import zombie.config.IntegerConfigOption;

public final class AtfCasinoConfig {

    public static final boolean DEFAULT_ENABLED = false;
    public static final int DEFAULT_MIN_BET = 1_000;
    public static final int DEFAULT_MAX_BET = 1_000_000;
    public static final int DEFAULT_BLACKJACK_BET_WINDOW_SECONDS = 20;
    public static final int DEFAULT_BLACKJACK_TURN_SECONDS = 20;
    public static final int DEFAULT_BLACKJACK_ROUND_PAUSE_SECONDS = 8;
    public static final int DEFAULT_ROULETTE_BET_WINDOW_SECONDS = 30;
    public static final int DEFAULT_ROULETTE_SPIN_SECONDS = 6;
    public static final int DEFAULT_ROULETTE_ROUND_PAUSE_SECONDS = 8;
    public static final int DEFAULT_HOLDEM_BIG_BLIND = 1_000;
    public static final int DEFAULT_HOLDEM_MIN_BUYIN_BLINDS = 20;
    public static final int DEFAULT_HOLDEM_MAX_BUYIN_BLINDS = 100;
    public static final int DEFAULT_HOLDEM_TURN_SECONDS = 20;
    public static final int DEFAULT_HOLDEM_ROUND_PAUSE_SECONDS = 10;
    public static final int DEFAULT_HOLDEM_START_DELAY_SECONDS = 5;
    public static final int MIN_SECONDS = 1;
    public static final int MAX_SECONDS = 600;

    private static final String PREFIX = "AtfCasino.";
    private static final String ENABLED_OPTION = "Enabled";
    private static final String MIN_BET_OPTION = "MinBet";
    private static final String MAX_BET_OPTION = "MaxBet";
    private static final String BLACKJACK_BET_WINDOW_OPTION = "BlackjackBetWindowSeconds";
    private static final String BLACKJACK_TURN_OPTION = "BlackjackTurnSeconds";
    private static final String BLACKJACK_ROUND_PAUSE_OPTION = "BlackjackRoundPauseSeconds";
    private static final String ROULETTE_BET_WINDOW_OPTION = "RouletteBetWindowSeconds";
    private static final String ROULETTE_SPIN_OPTION = "RouletteSpinSeconds";
    private static final String ROULETTE_ROUND_PAUSE_OPTION = "RoulettePauseSeconds";
    private static final String HOLDEM_BIG_BLIND_OPTION = "TexasHoldemBigBlind";
    private static final String HOLDEM_MIN_BUYIN_OPTION = "TexasHoldemMinBuyInBlinds";
    private static final String HOLDEM_MAX_BUYIN_OPTION = "TexasHoldemMaxBuyInBlinds";
    private static final String HOLDEM_TURN_OPTION = "TexasHoldemTurnSeconds";
    private static final String HOLDEM_ROUND_PAUSE_OPTION = "TexasHoldemPauseSeconds";
    private static final String HOLDEM_START_DELAY_OPTION = "TexasHoldemStartDelaySeconds";
    private static final String FLOOR_Z_OPTION = "FloorZ";
    private static final String GAME_ENABLED_SUFFIX = "Enabled";

    private AtfCasinoConfig() {}

    /** Master switch. When false the server rejects every wager. */
    public static boolean isEnabled() {
        return readBoolean(ENABLED_OPTION, DEFAULT_ENABLED);
    }

    /** Per-game switch, read from {@code AtfCasino.<Game>Enabled}. */
    public static boolean isGameEnabled(CasinoGame game) {
        return readBoolean(game.getOptionPrefix() + GAME_ENABLED_SUFFIX, DEFAULT_ENABLED);
    }

    /** Tile X for the NPC whose sandbox options are {@code AtfCasino.<prefix>X}/{@code Y}. */
    public static int getNpcTileX(String optionPrefix, int fallback) {
        return readInt(optionPrefix + "X", fallback);
    }

    public static int getNpcTileY(String optionPrefix, int fallback) {
        return readInt(optionPrefix + "Y", fallback);
    }

    /**
     * Facing enum index (1-based: N, NE, E, SE, S, SW, W, NW) from {@code
     * AtfCasino.<prefix>Facing}; convert with {@code CasinoLayout.facingRadians}.
     */
    public static int getNpcFacingIndex(String optionPrefix, int fallback) {
        return readInt(optionPrefix + "Facing", fallback);
    }

    /** Z level of the casino floor, shared by all five NPCs. */
    public static int getFloorZ(int fallback) {
        return readInt(FLOOR_Z_OPTION, fallback);
    }

    public static int getMinBet() {
        return readInt(MIN_BET_OPTION, DEFAULT_MIN_BET);
    }

    public static int getMaxBet() {
        return readInt(MAX_BET_OPTION, DEFAULT_MAX_BET);
    }

    /** Seconds from the first bet of a round until cards are dealt. */
    public static int getBlackjackBetWindowSeconds() {
        return clampSeconds(
                readInt(BLACKJACK_BET_WINDOW_OPTION, DEFAULT_BLACKJACK_BET_WINDOW_SECONDS));
    }

    /** Seconds each player has to hit/stand/double before the table stands for them. */
    public static int getBlackjackTurnSeconds() {
        return clampSeconds(readInt(BLACKJACK_TURN_OPTION, DEFAULT_BLACKJACK_TURN_SECONDS));
    }

    /** Seconds the settled hands stay on the table before the next betting round opens. */
    public static int getBlackjackRoundPauseSeconds() {
        return clampSeconds(
                readInt(BLACKJACK_ROUND_PAUSE_OPTION, DEFAULT_BLACKJACK_ROUND_PAUSE_SECONDS));
    }

    /** Seconds from the first roulette bet of a round until the wheel spins. */
    public static int getRouletteBetWindowSeconds() {
        return clampSeconds(
                readInt(ROULETTE_BET_WINDOW_OPTION, DEFAULT_ROULETTE_BET_WINDOW_SECONDS));
    }

    /** Seconds the wheel spins before the ball drops and bets are paid. */
    public static int getRouletteSpinSeconds() {
        return clampSeconds(readInt(ROULETTE_SPIN_OPTION, DEFAULT_ROULETTE_SPIN_SECONDS));
    }

    /** Seconds the result stays on the board before the next betting round opens. */
    public static int getRoulettePauseSeconds() {
        return clampSeconds(
                readInt(ROULETTE_ROUND_PAUSE_OPTION, DEFAULT_ROULETTE_ROUND_PAUSE_SECONDS));
    }

    /** Big blind in Scraps; the small blind is half of it. */
    public static int getHoldemBigBlind() {
        return Math.max(2, readInt(HOLDEM_BIG_BLIND_OPTION, DEFAULT_HOLDEM_BIG_BLIND));
    }

    /** Smallest stack a player may buy in with, in Scraps (configured in big blinds). */
    public static int getHoldemMinBuyIn() {
        long v =
                (long)
                                Math.max(
                                        1,
                                        readInt(
                                                HOLDEM_MIN_BUYIN_OPTION,
                                                DEFAULT_HOLDEM_MIN_BUYIN_BLINDS))
                        * getHoldemBigBlind();
        return (int) Math.min(Integer.MAX_VALUE, v);
    }

    /** Largest stack a player may have on the table, in Scraps (configured in big blinds). */
    public static int getHoldemMaxBuyIn() {
        long v =
                (long)
                                Math.max(
                                        1,
                                        readInt(
                                                HOLDEM_MAX_BUYIN_OPTION,
                                                DEFAULT_HOLDEM_MAX_BUYIN_BLINDS))
                        * getHoldemBigBlind();
        return (int) Math.max(getHoldemMinBuyIn(), Math.min(Integer.MAX_VALUE, v));
    }

    /** Seconds each player has to act before the table checks or folds for them. */
    public static int getHoldemTurnSeconds() {
        return clampSeconds(readInt(HOLDEM_TURN_OPTION, DEFAULT_HOLDEM_TURN_SECONDS));
    }

    /** Seconds the showdown stays on the table before the next hand can start. */
    public static int getHoldemPauseSeconds() {
        return clampSeconds(readInt(HOLDEM_ROUND_PAUSE_OPTION, DEFAULT_HOLDEM_ROUND_PAUSE_SECONDS));
    }

    /** Seconds between enough players being ready and the cards going out. */
    public static int getHoldemStartDelaySeconds() {
        return clampSeconds(readInt(HOLDEM_START_DELAY_OPTION, DEFAULT_HOLDEM_START_DELAY_SECONDS));
    }

    private static int clampSeconds(int seconds) {
        return Math.max(MIN_SECONDS, Math.min(MAX_SECONDS, seconds));
    }

    private static boolean readBoolean(String name, boolean fallback) {
        ConfigOption co = readOption(name);
        if (co instanceof BooleanConfigOption bo) {
            return bo.getValue();
        }
        return fallback;
    }

    private static int readInt(String name, int fallback) {
        ConfigOption co = readOption(name);
        if (co instanceof IntegerConfigOption io) {
            return io.getValue();
        }
        return fallback;
    }

    private static ConfigOption readOption(String name) {
        SandboxOptions.SandboxOption opt = SandboxOptions.instance.getOptionByName(PREFIX + name);
        return opt == null ? null : opt.asConfigOption();
    }
}
