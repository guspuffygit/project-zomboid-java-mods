package com.sentientsimulations.projectzomboid.extralogging.containerhistory;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;

public final class ContainerHistoryRepository {

    private static final String INSERT_SQL =
            "INSERT INTO transfers"
                    + " (ts, player_username, player_steam_id, item_type, item_name, item_id,"
                    + " src_ref, dest_ref, uuid) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";

    private static final String QUERY_BY_REF_SQL =
            "SELECT id, ts, player_username, player_steam_id, item_type, item_name, item_id,"
                    + " src_ref, dest_ref, uuid FROM transfers"
                    + " WHERE src_ref = ? OR dest_ref = ?"
                    + " ORDER BY ts DESC LIMIT ?";

    private ContainerHistoryRepository() {}

    public static void batchInsert(List<ContainerTransferRecord> records) {
        if (records.isEmpty()) {
            return;
        }
        synchronized (ContainerHistoryDatabase.class) {
            try {
                Connection c = ContainerHistoryDatabase.getConnection();
                boolean prevAutoCommit = c.getAutoCommit();
                c.setAutoCommit(false);
                try (PreparedStatement ps = c.prepareStatement(INSERT_SQL)) {
                    for (ContainerTransferRecord r : records) {
                        ps.setLong(1, r.ts());
                        ps.setString(2, r.playerUsername());
                        ps.setString(3, r.playerSteamId());
                        ps.setString(4, r.itemType());
                        ps.setString(5, r.itemName());
                        ps.setInt(6, r.itemId());
                        ps.setString(7, r.srcRef());
                        ps.setString(8, r.destRef());
                        ps.setString(9, r.uuid());
                        ps.addBatch();
                    }
                    ps.executeBatch();
                    c.commit();
                } catch (SQLException e) {
                    c.rollback();
                    throw e;
                } finally {
                    c.setAutoCommit(prevAutoCommit);
                }
            } catch (SQLException e) {
                LOGGER.error(
                        "Failed to batch insert {} container transfer records", records.size(), e);
            }
        }
    }

    public static List<ContainerTransferRecord> queryByContainerRef(String ref, int limit) {
        List<ContainerTransferRecord> out = new ArrayList<>();
        synchronized (ContainerHistoryDatabase.class) {
            try {
                Connection c = ContainerHistoryDatabase.getConnection();
                try (PreparedStatement ps = c.prepareStatement(QUERY_BY_REF_SQL)) {
                    ps.setString(1, ref);
                    ps.setString(2, ref);
                    ps.setInt(3, limit);
                    try (ResultSet rs = ps.executeQuery()) {
                        while (rs.next()) {
                            out.add(
                                    new ContainerTransferRecord(
                                            rs.getLong("id"),
                                            rs.getLong("ts"),
                                            rs.getString("player_username"),
                                            rs.getString("player_steam_id"),
                                            rs.getString("item_type"),
                                            rs.getString("item_name"),
                                            rs.getInt("item_id"),
                                            rs.getString("src_ref"),
                                            rs.getString("dest_ref"),
                                            rs.getString("uuid")));
                        }
                    }
                }
            } catch (SQLException e) {
                LOGGER.error("Failed to query container history for ref={}", ref, e);
            }
        }
        return out;
    }
}
