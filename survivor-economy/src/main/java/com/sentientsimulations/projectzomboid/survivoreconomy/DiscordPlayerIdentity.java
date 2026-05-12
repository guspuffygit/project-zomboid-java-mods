package com.sentientsimulations.projectzomboid.survivoreconomy;

/**
 * Synthetic player identity for Discord users. Encodes a Discord snowflake into the existing {@code
 * (player_username, player_steamid)} columns of {@code economy_balance} and {@code
 * economy_transactions} so all the same paired-transaction code paths can be reused without any
 * schema change.
 *
 * <p>Encoding:
 *
 * <ul>
 *   <li>{@code player_steamid = -<snowflake>} — real Steam64 IDs are always positive (≥ 7.65×10¹⁶),
 *       so a negative value is unambiguously a Discord identity.
 *   <li>{@code player_username = <snowflake>} — the snowflake as a string. Stable across Discord
 *       display-name changes; current display names live in {@code discord_links.discord_username}.
 * </ul>
 */
public final class DiscordPlayerIdentity {

    private final long snowflake;

    private DiscordPlayerIdentity(long snowflake) {
        this.snowflake = snowflake;
    }

    /**
     * Build an identity from a Discord snowflake. Throws {@link IllegalArgumentException} if the id
     * is null, blank, non-numeric, or non-positive.
     */
    public static DiscordPlayerIdentity of(String discordId) {
        if (discordId == null || discordId.isBlank()) {
            throw new IllegalArgumentException("Missing Discord id");
        }
        long parsed;
        try {
            parsed = Long.parseLong(discordId.trim());
        } catch (NumberFormatException e) {
            throw new IllegalArgumentException("Invalid Discord snowflake: " + discordId, e);
        }
        if (parsed <= 0L) {
            throw new IllegalArgumentException("Discord snowflake must be positive: " + discordId);
        }
        return new DiscordPlayerIdentity(parsed);
    }

    /** Synthetic {@code player_username} — the snowflake as a string. */
    public String username() {
        return Long.toString(snowflake);
    }

    /** Synthetic {@code player_steamid} — negated snowflake. */
    public long steamId() {
        return -snowflake;
    }

    /** The original Discord snowflake (always positive). */
    public String discordId() {
        return Long.toString(snowflake);
    }

    /** True if a {@code player_steamid} value belongs to a Discord synthetic identity. */
    public static boolean isSynthetic(long steamId) {
        return steamId < 0L;
    }

    /**
     * Recover the Discord snowflake from a synthetic {@code player_steamid}. Throws if the steamid
     * is not synthetic.
     */
    public static String discordIdFromSteamId(long steamId) {
        if (!isSynthetic(steamId)) {
            throw new IllegalArgumentException("Not a Discord synthetic steamid: " + steamId);
        }
        return Long.toString(-steamId);
    }
}
