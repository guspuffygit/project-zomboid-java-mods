package com.sentientsimulations.projectzomboid.atfcasino;

import org.jetbrains.annotations.Nullable;

/**
 * Registry of the games the casino offers. Table games run their own command flow (see {@link
 * BlackjackHandler}, {@link RouletteHandler}, {@link HoldemHandler}) and are never reachable
 * through {@code placeBet}.
 */
public enum CasinoGame {
    BLACKJACK("blackjack", "Blackjack", true),
    ROULETTE("roulette", "Roulette", true),
    HOLDEM("holdem", "Texas Holdem", true);

    private final String id;
    private final String displayName;
    private final boolean tableGame;

    CasinoGame(String id, String displayName, boolean tableGame) {
        this.id = id;
        this.displayName = displayName;
        this.tableGame = tableGame;
    }

    /** True for multi-round games with their own handler; {@code placeBet} rejects these. */
    public boolean isTableGame() {
        return tableGame;
    }

    public String getId() {
        return id;
    }

    public String getDisplayName() {
        return displayName;
    }

    /** Sandbox option name prefix for this game's per-game knobs, e.g. {@code CoinflipEnabled}. */
    public String getOptionPrefix() {
        return displayName.replace(" ", "");
    }

    @Nullable
    public static CasinoGame fromId(@Nullable String id) {
        if (id == null) {
            return null;
        }
        for (CasinoGame game : values()) {
            if (game.id.equalsIgnoreCase(id)) {
                return game;
            }
        }
        return null;
    }
}
