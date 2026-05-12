package com.sentientsimulations.projectzomboid.survivoreconomy;

import com.sentientsimulations.projectzomboid.survivoreconomy.records.DiscordAccount;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.DiscordLink;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.DiscordLinkClaimResult;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.DiscordLinkCode;
import java.security.SecureRandom;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Types;
import java.util.ArrayList;
import java.util.List;
import org.jspecify.annotations.Nullable;

/**
 * CRUD over {@code discord_links} and {@code discord_link_codes}. Code generation, claim
 * consumption, and link upsert flow through here. Atomic claim operations bracket their work in a
 * single SQL transaction so a partial state (code consumed but link not written, or link written
 * but code still active) cannot persist.
 */
public class DiscordLinkRepository {

    /** Default code TTL — 10 minutes. */
    public static final long DEFAULT_CODE_TTL_MS = 10L * 60L * 1000L;

    /** Length of generated codes in characters. */
    static final int CODE_LENGTH = 8;

    /**
     * Code alphabet: uppercase A–Z and digits 2–9, omitting visually ambiguous {@code 0/O} and
     * {@code 1/I}.
     */
    static final char[] CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".toCharArray();

    private static final SecureRandom RNG = new SecureRandom();

    private static final String INSERT_CODE =
            "INSERT INTO discord_link_codes"
                    + " (code, direction, discord_id, discord_username, steamid, username,"
                    + " created_at_ms, expires_at_ms, consumed_at_ms)"
                    + " VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL)";

    private static final String SELECT_CODE = "SELECT * FROM discord_link_codes WHERE code = ?";

    private static final String MARK_CODE_CONSUMED_FOR_PLAYER =
            "UPDATE discord_link_codes"
                    + " SET steamid = ?, username = ?, consumed_at_ms = ?"
                    + " WHERE code = ? AND consumed_at_ms IS NULL";

    private static final String MARK_CODE_CONSUMED_FOR_DISCORD =
            "UPDATE discord_link_codes"
                    + " SET discord_id = ?, discord_username = ?, consumed_at_ms = ?"
                    + " WHERE code = ? AND consumed_at_ms IS NULL";

    private static final String UPSERT_LINK =
            "INSERT INTO discord_links"
                    + " (discord_id, discord_username, steamid, created_at_ms, updated_at_ms)"
                    + " VALUES (?, ?, ?, ?, ?)"
                    + " ON CONFLICT(discord_id, steamid) DO UPDATE SET"
                    + " discord_username = excluded.discord_username,"
                    + " updated_at_ms = excluded.updated_at_ms";

    private static final String SELECT_LINKS_BY_DISCORD =
            "SELECT discord_id, discord_username, steamid, created_at_ms, updated_at_ms"
                    + " FROM discord_links WHERE discord_id = ?"
                    + " ORDER BY updated_at_ms DESC";

    private static final String SELECT_LINKS_BY_STEAMID =
            "SELECT discord_id, discord_username, steamid, created_at_ms, updated_at_ms"
                    + " FROM discord_links WHERE steamid = ?"
                    + " ORDER BY updated_at_ms DESC";

    private static final String SELECT_LINK_EXISTS =
            "SELECT 1 FROM discord_links WHERE discord_id = ? AND steamid = ? LIMIT 1";

    private static final String SELECT_ACCOUNTS_FOR_DISCORD =
            "SELECT eb.player_username, eb.player_steamid, eb.currency, eb.balance"
                    + " FROM economy_balance eb"
                    + " INNER JOIN discord_links dl ON eb.player_steamid = dl.steamid"
                    + " WHERE dl.discord_id = ? AND eb.balance > 0"
                    + " ORDER BY eb.player_username ASC, eb.currency ASC";

    private final Connection connection;

    public DiscordLinkRepository(Connection connection) {
        this.connection = connection;
    }

    /**
     * Generate and persist a new {@code DISCORD}-direction code. {@code discordId} and {@code
     * discordUsername} are recorded; {@code steamid}/{@code username} stay null until consumption
     * by an in-game player.
     */
    public DiscordLinkCode createDiscordCode(
            String discordId, @Nullable String discordUsername, long nowMs, long ttlMs)
            throws SQLException {
        String code = generateCode();
        long expiresAt = nowMs + ttlMs;
        try (PreparedStatement ps = connection.prepareStatement(INSERT_CODE)) {
            ps.setString(1, code);
            ps.setString(2, DiscordLinkCode.DIRECTION_DISCORD);
            ps.setString(3, discordId);
            setNullableString(ps, 4, discordUsername);
            ps.setNull(5, Types.INTEGER);
            ps.setNull(6, Types.VARCHAR);
            ps.setLong(7, nowMs);
            ps.setLong(8, expiresAt);
            ps.executeUpdate();
        }
        return new DiscordLinkCode(
                code,
                DiscordLinkCode.DIRECTION_DISCORD,
                discordId,
                discordUsername,
                null,
                null,
                nowMs,
                expiresAt,
                null);
    }

    /**
     * Atomically consume a {@code DISCORD}-direction code as a specific player and upsert the
     * resulting link. Validates direction, expiry, and prior consumption. Returns a result with the
     * code's discordId on success or a {@code FAILURE_*} reason otherwise.
     */
    public DiscordLinkClaimResult consumeDiscordCodeAsPlayer(
            String code, long steamId, String username, long nowMs) throws SQLException {
        boolean previousAutoCommit = connection.getAutoCommit();
        connection.setAutoCommit(false);
        try {
            DiscordLinkCode existing = loadCode(code);
            if (existing == null) {
                connection.commit();
                return DiscordLinkClaimResult.failure(DiscordLinkClaimResult.FAILURE_NOT_FOUND);
            }
            if (!DiscordLinkCode.DIRECTION_DISCORD.equals(existing.direction())) {
                connection.commit();
                return DiscordLinkClaimResult.failure(
                        DiscordLinkClaimResult.FAILURE_WRONG_DIRECTION);
            }
            if (existing.consumedAtMs() != null) {
                connection.commit();
                return DiscordLinkClaimResult.failure(
                        DiscordLinkClaimResult.FAILURE_ALREADY_CONSUMED);
            }
            if (nowMs > existing.expiresAtMs()) {
                connection.commit();
                return DiscordLinkClaimResult.failure(DiscordLinkClaimResult.FAILURE_EXPIRED);
            }
            String discordId = existing.discordId();
            if (discordId == null) {
                connection.commit();
                return DiscordLinkClaimResult.failure(DiscordLinkClaimResult.FAILURE_NOT_FOUND);
            }

            try (PreparedStatement ps =
                    connection.prepareStatement(MARK_CODE_CONSUMED_FOR_PLAYER)) {
                ps.setLong(1, steamId);
                ps.setString(2, username);
                ps.setLong(3, nowMs);
                ps.setString(4, code);
                ps.executeUpdate();
            }
            upsertLinkInternal(discordId, existing.discordUsername(), steamId, nowMs);
            connection.commit();
            return DiscordLinkClaimResult.successDiscordToPlayer(
                    discordId, existing.discordUsername(), steamId, username);
        } catch (SQLException e) {
            connection.rollback();
            throw e;
        } finally {
            connection.setAutoCommit(previousAutoCommit);
        }
    }

    /** Read a single code row, or null if not found. */
    public @Nullable DiscordLinkCode loadCode(String code) throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(SELECT_CODE)) {
            ps.setString(1, code);
            try (ResultSet rs = ps.executeQuery()) {
                if (!rs.next()) {
                    return null;
                }
                return rowToCode(rs);
            }
        }
    }

    /** All Discord ↔ Steam links for a given Discord user, most recently updated first. */
    public List<DiscordLink> listLinksForDiscord(String discordId) throws SQLException {
        List<DiscordLink> out = new ArrayList<>();
        try (PreparedStatement ps = connection.prepareStatement(SELECT_LINKS_BY_DISCORD)) {
            ps.setString(1, discordId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    out.add(rowToLink(rs));
                }
            }
        }
        return out;
    }

    /** True iff a {@code discord_links} row exists for the given (discord_id, steamId) pair. */
    public boolean isLinked(String discordId, long steamId) throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(SELECT_LINK_EXISTS)) {
            ps.setString(1, discordId);
            ps.setLong(2, steamId);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next();
            }
        }
    }

    /**
     * Every (character × currency) balance reachable through any Steam ID linked to {@code
     * discordId}. Used to populate the {@code /tip} account picker — only positive balances are
     * returned so the picker only shows accounts the user can actually spend from.
     */
    public List<DiscordAccount> listAccountsForDiscord(String discordId) throws SQLException {
        List<DiscordAccount> out = new ArrayList<>();
        try (PreparedStatement ps = connection.prepareStatement(SELECT_ACCOUNTS_FOR_DISCORD)) {
            ps.setString(1, discordId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    out.add(
                            new DiscordAccount(
                                    rs.getString("player_username"),
                                    rs.getLong("player_steamid"),
                                    rs.getString("currency"),
                                    rs.getDouble("balance")));
                }
            }
        }
        return out;
    }

    /** All Discord users linked to a given Steam ID, most recently updated first. */
    public List<DiscordLink> listLinksForSteamId(long steamId) throws SQLException {
        List<DiscordLink> out = new ArrayList<>();
        try (PreparedStatement ps = connection.prepareStatement(SELECT_LINKS_BY_STEAMID)) {
            ps.setLong(1, steamId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    out.add(rowToLink(rs));
                }
            }
        }
        return out;
    }

    private void upsertLinkInternal(
            String discordId, @Nullable String discordUsername, long steamId, long nowMs)
            throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(UPSERT_LINK)) {
            ps.setString(1, discordId);
            setNullableString(ps, 2, discordUsername);
            ps.setLong(3, steamId);
            ps.setLong(4, nowMs);
            ps.setLong(5, nowMs);
            ps.executeUpdate();
        }
    }

    static String generateCode() {
        char[] chars = new char[CODE_LENGTH];
        for (int i = 0; i < CODE_LENGTH; i++) {
            chars[i] = CODE_ALPHABET[RNG.nextInt(CODE_ALPHABET.length)];
        }
        return new String(chars);
    }

    private static DiscordLinkCode rowToCode(ResultSet rs) throws SQLException {
        return new DiscordLinkCode(
                rs.getString("code"),
                rs.getString("direction"),
                rs.getString("discord_id"),
                rs.getString("discord_username"),
                getNullableLong(rs, "steamid"),
                rs.getString("username"),
                rs.getLong("created_at_ms"),
                rs.getLong("expires_at_ms"),
                getNullableLong(rs, "consumed_at_ms"));
    }

    private static DiscordLink rowToLink(ResultSet rs) throws SQLException {
        return new DiscordLink(
                rs.getString("discord_id"),
                rs.getString("discord_username"),
                rs.getLong("steamid"),
                rs.getLong("created_at_ms"),
                rs.getLong("updated_at_ms"));
    }

    private static void setNullableString(PreparedStatement ps, int idx, @Nullable String v)
            throws SQLException {
        if (v == null) {
            ps.setNull(idx, Types.VARCHAR);
        } else {
            ps.setString(idx, v);
        }
    }

    private static @Nullable Long getNullableLong(ResultSet rs, String col) throws SQLException {
        long v = rs.getLong(col);
        return rs.wasNull() ? null : v;
    }
}
