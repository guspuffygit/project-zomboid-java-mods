package com.sentientsimulations.projectzomboid.mapmetasqlite;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;

public class SafeHouseRepository {

    private static final String INSERT_SAFEHOUSE =
            """
            INSERT OR REPLACE INTO safehouses
                (x, y, w, h, owner, hit_points, last_visited, title, datetime_created, location)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""";

    private static final String INSERT_PLAYER =
            """
            INSERT OR IGNORE INTO safehouse_players (safehouse_x, safehouse_y, username)
            VALUES (?, ?, ?)""";

    private static final String INSERT_RESPAWN =
            """
            INSERT OR IGNORE INTO safehouse_respawns (safehouse_x, safehouse_y, username)
            VALUES (?, ?, ?)""";

    private static final String SELECT_ALL_SAFEHOUSES =
            """
            SELECT x, y, w, h, owner, hit_points, last_visited, title, datetime_created, location
            FROM safehouses""";

    private static final String SELECT_PLAYERS =
            """
            SELECT username FROM safehouse_players
            WHERE safehouse_x = ? AND safehouse_y = ?""";

    private static final String SELECT_RESPAWNS =
            """
            SELECT username FROM safehouse_respawns
            WHERE safehouse_x = ? AND safehouse_y = ?""";

    private final Connection connection;

    public SafeHouseRepository(Connection connection) {
        this.connection = connection;
    }

    public void saveAll(List<SafeHouseRecord> safehouses) throws SQLException {
        boolean wasAutoCommit = connection.getAutoCommit();
        connection.setAutoCommit(false);
        try {
            try (Statement stmt = connection.createStatement()) {
                stmt.execute("DELETE FROM safehouse_respawns");
                stmt.execute("DELETE FROM safehouse_players");
                stmt.execute("DELETE FROM safehouses");
            }

            try (PreparedStatement ps = connection.prepareStatement(INSERT_SAFEHOUSE)) {
                for (SafeHouseRecord sh : safehouses) {
                    ps.setInt(1, sh.x());
                    ps.setInt(2, sh.y());
                    ps.setInt(3, sh.w());
                    ps.setInt(4, sh.h());
                    ps.setString(5, sh.owner());
                    ps.setInt(6, sh.hitPoints());
                    ps.setLong(7, sh.lastVisited());
                    ps.setString(8, sh.title());
                    ps.setLong(9, sh.datetimeCreated());
                    ps.setString(10, sh.location());
                    ps.addBatch();
                }
                ps.executeBatch();
            }

            try (PreparedStatement ps = connection.prepareStatement(INSERT_PLAYER)) {
                for (SafeHouseRecord sh : safehouses) {
                    for (String player : sh.players()) {
                        ps.setInt(1, sh.x());
                        ps.setInt(2, sh.y());
                        ps.setString(3, player);
                        ps.addBatch();
                    }
                }
                ps.executeBatch();
            }

            try (PreparedStatement ps = connection.prepareStatement(INSERT_RESPAWN)) {
                for (SafeHouseRecord sh : safehouses) {
                    for (String player : sh.playersRespawn()) {
                        ps.setInt(1, sh.x());
                        ps.setInt(2, sh.y());
                        ps.setString(3, player);
                        ps.addBatch();
                    }
                }
                ps.executeBatch();
            }

            connection.commit();
        } catch (SQLException e) {
            connection.rollback();
            throw e;
        } finally {
            connection.setAutoCommit(wasAutoCommit);
        }
    }

    public List<SafeHouseRecord> loadAll() throws SQLException {
        List<SafeHouseRecord> results = new ArrayList<>();
        try (Statement stmt = connection.createStatement();
                ResultSet rs = stmt.executeQuery(SELECT_ALL_SAFEHOUSES)) {
            while (rs.next()) {
                int x = rs.getInt("x");
                int y = rs.getInt("y");
                List<String> players = loadStrings(SELECT_PLAYERS, x, y);
                List<String> respawns = loadStrings(SELECT_RESPAWNS, x, y);

                results.add(
                        new SafeHouseRecord(
                                x,
                                y,
                                rs.getInt("w"),
                                rs.getInt("h"),
                                rs.getString("owner"),
                                rs.getInt("hit_points"),
                                players,
                                rs.getLong("last_visited"),
                                rs.getString("title"),
                                rs.getLong("datetime_created"),
                                rs.getString("location"),
                                respawns));
            }
        }
        return results;
    }

    public void deleteAll() throws SQLException {
        try (Statement stmt = connection.createStatement()) {
            stmt.execute("DELETE FROM safehouse_respawns");
            stmt.execute("DELETE FROM safehouse_players");
            stmt.execute("DELETE FROM safehouses");
        }
    }

    private List<String> loadStrings(String sql, int x, int y) throws SQLException {
        List<String> results = new ArrayList<>();
        try (PreparedStatement ps = connection.prepareStatement(sql)) {
            ps.setInt(1, x);
            ps.setInt(2, y);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    results.add(rs.getString("username"));
                }
            }
        }
        return results;
    }
}
