package com.sentientsimulations.projectzomboid.atfcasino.npc;

/**
 * Where the casino's characters stand by default. Tile coordinates; the NPC is centred on the tile.
 * These are the fallbacks for the {@code AtfCasino.<Npc>X/Y} + {@code FloorZ} sandbox options and
 * must match the defaults in {@code media/sandbox-options.txt} (and the Lua fallbacks in {@code
 * media/lua/client/AtfCasino/}).
 */
public final class CasinoLayout {

    public static final int Z = -1;

    public static final int GUARD_LEFT_X = 615;
    public static final int GUARD_LEFT_Y = 9414;
    public static final int GUARD_RIGHT_X = 619;
    public static final int GUARD_RIGHT_Y = 9414;

    public static final int DEALER_X = 615;
    public static final int DEALER_Y = 9422;

    public static final int CROUPIER_X = 619;
    public static final int CROUPIER_Y = 9422;

    public static final int POKER_DEALER_X = 614;
    public static final int POKER_DEALER_Y = 9418;

    public static final String GUARD_NAME = "Creepy Spiffo";
    public static final String DEALER_NAME = "Creepy Spiffo Dealer";
    public static final String CROUPIER_NAME = "Creepy Spiffo Croupier";
    public static final String POKER_DEALER_NAME = "Creepy Spiffo Poker Dealer";

    /** Players this far (tiles, Chebyshev) from a guard on the casino floor are under watch. */
    public static final float GUARD_WATCH_RADIUS = 20.0F;

    /**
     * A player must be within this many tiles of a dealer to open, sit at, or stay at that table.
     */
    public static final float TABLE_RADIUS = 8.0F;

    /**
     * Default facing for every NPC, as the 1-based index of the {@code AtfCasino.<Npc>Facing}
     * sandbox enum (N, NE, E, SE, S, SW, W, NW) — must match {@code numValues}/{@code default} in
     * {@code media/sandbox-options.txt}.
     */
    public static final int FACING_SOUTH_INDEX = 5;

    // Radians per enum index, atan2 convention (east = 0, y grows south): N, NE, E, SE, S, SW,
    // W, NW.
    private static final float[] FACING_RADIANS = {
        (float) (-Math.PI / 2.0),
        (float) (-Math.PI / 4.0),
        0.0F,
        (float) (Math.PI / 4.0),
        (float) (Math.PI / 2.0),
        (float) (3.0 * Math.PI / 4.0),
        (float) Math.PI,
        (float) (-3.0 * Math.PI / 4.0),
    };

    private CasinoLayout() {}

    public static float centre(int tile) {
        return tile + 0.5F;
    }

    /**
     * Facing angle in radians for a sandbox facing enum index; out-of-range falls back to south.
     */
    public static float facingRadians(int enumIndex) {
        if (enumIndex < 1 || enumIndex > FACING_RADIANS.length) {
            enumIndex = FACING_SOUTH_INDEX;
        }
        return FACING_RADIANS[enumIndex - 1];
    }
}
