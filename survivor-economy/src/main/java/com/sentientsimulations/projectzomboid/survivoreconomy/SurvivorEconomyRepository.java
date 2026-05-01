package com.sentientsimulations.projectzomboid.survivoreconomy;

import com.sentientsimulations.projectzomboid.survivoreconomy.records.TransactionDraft;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.TransactionEntry;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.jspecify.annotations.Nullable;

public class SurvivorEconomyRepository {

    private static final String SELECT_TRANSACTIONS_BASE =
            "SELECT id, event_id, event_role, timestamp_ms, type, parent_event_id, reason,"
                    + " player_username, player_steamid, currency, amount, item_id, item_qty,"
                    + " vehicle_id, shop_category, wallet_id, account_number,"
                    + " death_x, death_y, death_z FROM economy_transactions";

    private static final String INSERT_TRANSACTION =
            "INSERT INTO economy_transactions (event_id, event_role, timestamp_ms, type,"
                    + " parent_event_id, reason, player_username, player_steamid, currency,"
                    + " amount, item_id, item_qty, vehicle_id, shop_category, wallet_id,"
                    + " account_number, death_x, death_y, death_z)"
                    + " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";

    private static final String SELECT_BALANCES =
            "SELECT currency, SUM(amount) AS total FROM economy_transactions"
                    + " WHERE player_username = ? AND player_steamid = ?"
                    + " GROUP BY currency";

    private static final String SELECT_BY_EVENT =
            SELECT_TRANSACTIONS_BASE + " WHERE event_id = ? ORDER BY id ASC";

    private final Connection connection;
    private final SurvivorEconomyBalanceRepository balanceRepo;

    public SurvivorEconomyRepository(Connection connection) {
        this.connection = connection;
        this.balanceRepo = new SurvivorEconomyBalanceRepository(connection);
    }

    /**
     * Insert a single one-sided event (admin grant, withdraw, deposit, system income, money loss on
     * death) and apply the signed amount to {@code economy_balance} for the same player+currency.
     * Both writes happen inside one SQL transaction, so a failure on either side rolls back the
     * other and the running balance can never drift from {@code SUM(amount)}. Returns the generated
     * event id so callers can reference it as {@code parentEventId} on follow-on rows.
     */
    public String insertSole(TransactionDraft draft) throws SQLException {
        String eventId = generateEventId();
        boolean previousAutoCommit = connection.getAutoCommit();
        connection.setAutoCommit(false);
        try {
            insertRow(eventId, "SOLE", draft);
            balanceRepo.applyDelta(
                    draft.playerUsername(),
                    draft.playerSteamId(),
                    draft.currency(),
                    draft.amount(),
                    draft.timestampMs());
            connection.commit();
            return eventId;
        } catch (SQLException e) {
            connection.rollback();
            throw e;
        } finally {
            connection.setAutoCommit(previousAutoCommit);
        }
    }

    /**
     * Insert a paired event: a FROM row (one player loses) and a TO row (the counterparty gains),
     * plus matching {@code economy_balance} deltas for both sides. All four writes happen in a
     * single SQL transaction — a failure on any row rolls back every prior write. Returns the
     * shared event id.
     */
    public String insertPair(TransactionDraft from, TransactionDraft to) throws SQLException {
        String eventId = generateEventId();
        boolean previousAutoCommit = connection.getAutoCommit();
        connection.setAutoCommit(false);
        try {
            insertRow(eventId, "FROM", from);
            balanceRepo.applyDelta(
                    from.playerUsername(),
                    from.playerSteamId(),
                    from.currency(),
                    from.amount(),
                    from.timestampMs());
            insertRow(eventId, "TO", to);
            balanceRepo.applyDelta(
                    to.playerUsername(),
                    to.playerSteamId(),
                    to.currency(),
                    to.amount(),
                    to.timestampMs());
            connection.commit();
            return eventId;
        } catch (SQLException e) {
            connection.rollback();
            throw e;
        } finally {
            connection.setAutoCommit(previousAutoCommit);
        }
    }

    /**
     * Load up to {@code limit} most recent transactions, newest first. Each filter ({@code
     * username}, {@code steamId}, {@code type}) may be null. Filters that are non-null must all
     * match (AND).
     */
    public List<TransactionEntry> loadRecent(
            int limit, @Nullable String username, @Nullable Long steamId, @Nullable String type)
            throws SQLException {
        StringBuilder sql = new StringBuilder(SELECT_TRANSACTIONS_BASE);
        List<Object> params = new ArrayList<>();
        List<String> predicates = new ArrayList<>();
        if (username != null) {
            predicates.add("player_username = ?");
            params.add(username);
        }
        if (steamId != null) {
            predicates.add("player_steamid = ?");
            params.add(steamId);
        }
        if (type != null) {
            predicates.add("type = ?");
            params.add(type);
        }
        if (!predicates.isEmpty()) {
            sql.append(" WHERE ").append(String.join(" AND ", predicates));
        }
        sql.append(" ORDER BY timestamp_ms DESC, id DESC LIMIT ?");
        params.add(limit);

        List<TransactionEntry> results = new ArrayList<>();
        try (PreparedStatement ps = connection.prepareStatement(sql.toString())) {
            bindParams(ps, params);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    results.add(rowToEntry(rs));
                }
            }
        }
        return results;
    }

    /**
     * Load every row that shares the given {@code event_id}. SOLE events return 1 row; paired
     * events return 2 (FROM then TO, in insertion order).
     */
    public List<TransactionEntry> loadByEventId(String eventId) throws SQLException {
        List<TransactionEntry> results = new ArrayList<>();
        try (PreparedStatement ps = connection.prepareStatement(SELECT_BY_EVENT)) {
            ps.setString(1, eventId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    results.add(rowToEntry(rs));
                }
            }
        }
        return results;
    }

    /**
     * Sum {@code amount} grouped by currency for the given player. The sign convention (+ gained, −
     * lost) means the sum equals the player's net holding in each currency over all logged history.
     */
    public Map<String, Double> loadBalances(String username, long steamId) throws SQLException {
        Map<String, Double> balances = new LinkedHashMap<>();
        try (PreparedStatement ps = connection.prepareStatement(SELECT_BALANCES)) {
            ps.setString(1, username);
            ps.setLong(2, steamId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    balances.put(rs.getString("currency"), rs.getDouble("total"));
                }
            }
        }
        return balances;
    }

    private void insertRow(String eventId, String role, TransactionDraft d) throws SQLException {
        try (PreparedStatement ps = connection.prepareStatement(INSERT_TRANSACTION)) {
            ps.setString(1, eventId);
            ps.setString(2, role);
            ps.setLong(3, d.timestampMs());
            setNullableString(ps, 4, d.type());
            setNullableString(ps, 5, d.parentEventId());
            setNullableString(ps, 6, d.reason());
            setNullableString(ps, 7, d.playerUsername());
            ps.setLong(8, d.playerSteamId());
            setNullableString(ps, 9, d.currency());
            ps.setDouble(10, d.amount());
            setNullableString(ps, 11, d.itemId());
            setNullableInt(ps, 12, d.itemQty());
            setNullableString(ps, 13, d.vehicleId());
            setNullableString(ps, 14, d.shopCategory());
            setNullableString(ps, 15, d.walletId());
            setNullableString(ps, 16, d.accountNumber());
            setNullableDouble(ps, 17, d.deathX());
            setNullableDouble(ps, 18, d.deathY());
            setNullableDouble(ps, 19, d.deathZ());
            ps.executeUpdate();
        }
    }

    private static String generateEventId() {
        return "evt_" + UUID.randomUUID();
    }

    private static TransactionEntry rowToEntry(ResultSet rs) throws SQLException {
        return new TransactionEntry(
                rs.getLong("id"),
                rs.getString("event_id"),
                rs.getString("event_role"),
                rs.getLong("timestamp_ms"),
                rs.getString("type"),
                rs.getString("parent_event_id"),
                rs.getString("reason"),
                rs.getString("player_username"),
                rs.getLong("player_steamid"),
                rs.getString("currency"),
                rs.getDouble("amount"),
                rs.getString("item_id"),
                getNullableInt(rs, "item_qty"),
                rs.getString("vehicle_id"),
                rs.getString("shop_category"),
                rs.getString("wallet_id"),
                rs.getString("account_number"),
                getNullableDouble(rs, "death_x"),
                getNullableDouble(rs, "death_y"),
                getNullableDouble(rs, "death_z"));
    }

    private static void setNullableString(PreparedStatement ps, int idx, @Nullable String v)
            throws SQLException {
        if (v == null) ps.setNull(idx, Types.VARCHAR);
        else ps.setString(idx, v);
    }

    private static void setNullableInt(PreparedStatement ps, int idx, @Nullable Integer v)
            throws SQLException {
        if (v == null) ps.setNull(idx, Types.INTEGER);
        else ps.setInt(idx, v);
    }

    private static void setNullableDouble(PreparedStatement ps, int idx, @Nullable Double v)
            throws SQLException {
        if (v == null) ps.setNull(idx, Types.DOUBLE);
        else ps.setDouble(idx, v);
    }

    private static @Nullable Integer getNullableInt(ResultSet rs, String col) throws SQLException {
        int v = rs.getInt(col);
        return rs.wasNull() ? null : v;
    }

    private static @Nullable Double getNullableDouble(ResultSet rs, String col)
            throws SQLException {
        double v = rs.getDouble(col);
        return rs.wasNull() ? null : v;
    }

    private static void bindParams(PreparedStatement ps, List<Object> params) throws SQLException {
        for (int i = 0; i < params.size(); i++) {
            Object value = params.get(i);
            if (value instanceof Long l) {
                ps.setLong(i + 1, l);
            } else if (value instanceof Integer n) {
                ps.setInt(i + 1, n);
            } else if (value instanceof String s) {
                ps.setString(i + 1, s);
            } else {
                ps.setObject(i + 1, value);
            }
        }
    }
}
