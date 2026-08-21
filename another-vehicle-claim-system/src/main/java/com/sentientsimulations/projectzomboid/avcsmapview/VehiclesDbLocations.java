package com.sentientsimulations.projectzomboid.avcsmapview;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import java.io.File;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.sqlite.SQLiteConfig;
import zombie.ZomboidFileSystem;

/**
 * Reads vehicle positions straight out of the save's {@code vehicles.db}.
 *
 * <p>Vanilla's {@code VehiclesDB2} owns its own connection on the world-streamer thread and commits
 * every row write immediately, so a separate read-only connection sees the latest unloaded-vehicle
 * positions without touching PZ's connection from another thread. The busy timeout covers the brief
 * exclusive lock PZ takes while committing.
 */
final class VehiclesDbLocations {

    record Position(float x, float y) {}

    static final String DB_FILE = "vehicles.db";
    static final int IN_BATCH = 500;
    private static final int BUSY_TIMEOUT_MS = 1000;

    private VehiclesDbLocations() {}

    static Map<Integer, Position> readFromCurrentSave(Collection<Integer> sqlIds) {
        return read(new File(ZomboidFileSystem.instance.getCurrentSaveDir(), DB_FILE), sqlIds);
    }

    static Map<Integer, Position> read(File dbFile, Collection<Integer> sqlIds) {
        if (sqlIds.isEmpty()) {
            return Map.of();
        }
        if (!dbFile.isFile()) {
            LOGGER.warn("AVCS location sync: {} not found", dbFile);
            return Map.of();
        }
        SQLiteConfig config = new SQLiteConfig();
        config.setReadOnly(true);
        config.setBusyTimeout(BUSY_TIMEOUT_MS);
        Map<Integer, Position> out = new HashMap<>();
        try (Connection conn = config.createConnection("jdbc:sqlite:" + dbFile.getAbsolutePath())) {
            List<Integer> ids = new ArrayList<>(sqlIds);
            for (int from = 0; from < ids.size(); from += IN_BATCH) {
                List<Integer> batch = ids.subList(from, Math.min(ids.size(), from + IN_BATCH));
                readBatch(conn, batch, out);
            }
        } catch (SQLException e) {
            LOGGER.warn("AVCS location sync: reading {} failed: {}", dbFile, e.toString());
        }
        return out;
    }

    private static void readBatch(Connection conn, List<Integer> ids, Map<Integer, Position> out)
            throws SQLException {
        String sql =
                "SELECT id, x, y FROM vehicles WHERE id IN (" + "?,".repeat(ids.size() - 1) + "?)";
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            for (int i = 0; i < ids.size(); i++) {
                ps.setInt(i + 1, ids.get(i));
            }
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    out.put(rs.getInt(1), new Position(rs.getFloat(2), rs.getFloat(3)));
                }
            }
        }
    }
}
