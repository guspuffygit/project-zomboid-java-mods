package com.sentientsimulations.projectzomboid.survivorlootrespawn.state;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.survivorlootrespawn.metrics.SurvivorLootRespawnMetrics;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;

public final class ContainerLootStateRepository {

    private static final String INSERT_IF_MISSING_SQL =
            """
            INSERT INTO container_loot_state (
                square_x, square_y, square_z, container_type, container_index,
                looted_game_hours, respawn_queued_at_hours, fill_added_nothing_count
            ) VALUES (?, ?, ?, ?, ?, ?, NULL, 0)
            ON CONFLICT(square_x, square_y, square_z, container_type, container_index)
            DO NOTHING""";

    private static final String SELECT_ROLLING_SQL =
            """
            SELECT square_x, square_y, square_z, container_type, container_index,
                   looted_game_hours, respawn_queued_at_hours, fill_added_nothing_count
              FROM container_loot_state
             WHERE respawn_queued_at_hours IS NULL
               AND looted_game_hours <= ? - ?""";

    private static final String SELECT_QUEUED_FOR_SQUARE_SQL =
            """
            SELECT square_x, square_y, square_z, container_type, container_index,
                   looted_game_hours, respawn_queued_at_hours, fill_added_nothing_count
              FROM container_loot_state
             WHERE square_x = ? AND square_y = ? AND square_z = ?
               AND respawn_queued_at_hours IS NOT NULL""";

    private static final String SELECT_QUEUED_IN_CHUNK_SQL =
            """
            SELECT square_x, square_y, square_z, container_type, container_index,
                   looted_game_hours, respawn_queued_at_hours, fill_added_nothing_count
              FROM container_loot_state
             WHERE square_x >= ? AND square_x < ?
               AND square_y >= ? AND square_y < ?
               AND respawn_queued_at_hours IS NOT NULL""";

    private static final String MARK_QUEUED_SQL =
            """
            UPDATE container_loot_state
               SET respawn_queued_at_hours = ?
             WHERE square_x = ? AND square_y = ? AND square_z = ?
               AND container_type = ? AND container_index = ?""";

    private static final String DELETE_SQL =
            """
            DELETE FROM container_loot_state
             WHERE square_x = ? AND square_y = ? AND square_z = ?
               AND container_type = ? AND container_index = ?""";

    private static final String INCREMENT_FILL_ADDED_NOTHING_SQL =
            """
            UPDATE container_loot_state
               SET fill_added_nothing_count = fill_added_nothing_count + 1
             WHERE square_x = ? AND square_y = ? AND square_z = ?
               AND container_type = ? AND container_index = ?""";

    private static final String COUNT_TOTAL_SQL = "SELECT COUNT(*) FROM container_loot_state";

    private static final String COUNT_QUEUED_SQL =
            "SELECT COUNT(*) FROM container_loot_state WHERE respawn_queued_at_hours IS NOT NULL";

    public record InsertRow(
            int squareX,
            int squareY,
            int squareZ,
            String containerType,
            int containerIndex,
            double lootedGameHours) {}

    private ContainerLootStateRepository() {}

    public static boolean insertIfMissing(
            int x, int y, int z, String containerType, int containerIndex, double lootedGameHours) {
        synchronized (SurvivorLootRespawnDatabase.class) {
            try {
                Connection c = SurvivorLootRespawnDatabase.getConnection();
                try (PreparedStatement ps = c.prepareStatement(INSERT_IF_MISSING_SQL)) {
                    ps.setInt(1, x);
                    ps.setInt(2, y);
                    ps.setInt(3, z);
                    ps.setString(4, containerType);
                    ps.setInt(5, containerIndex);
                    ps.setDouble(6, lootedGameHours);
                    return ps.executeUpdate() > 0;
                }
            } catch (SQLException e) {
                SurvivorLootRespawnMetrics.recordDbError("insert");
                LOGGER.error(
                        "[SurvivorLootRespawn] Failed to insert container loot state at x={} y={} z={} type={} idx={}",
                        x,
                        y,
                        z,
                        containerType,
                        containerIndex,
                        e);
                return false;
            }
        }
    }

    public static int batchInsertIfMissing(List<InsertRow> rows) {
        if (rows.isEmpty()) {
            return 0;
        }
        synchronized (SurvivorLootRespawnDatabase.class) {
            try {
                Connection c = SurvivorLootRespawnDatabase.getConnection();
                boolean prevAutoCommit = c.getAutoCommit();
                c.setAutoCommit(false);
                try (PreparedStatement ps = c.prepareStatement(INSERT_IF_MISSING_SQL)) {
                    for (InsertRow r : rows) {
                        ps.setInt(1, r.squareX());
                        ps.setInt(2, r.squareY());
                        ps.setInt(3, r.squareZ());
                        ps.setString(4, r.containerType());
                        ps.setInt(5, r.containerIndex());
                        ps.setDouble(6, r.lootedGameHours());
                        ps.addBatch();
                    }
                    int[] counts = ps.executeBatch();
                    c.commit();
                    int inserted = 0;
                    for (int n : counts) {
                        if (n > 0) {
                            inserted++;
                        }
                    }
                    return inserted;
                } catch (SQLException e) {
                    c.rollback();
                    throw e;
                } finally {
                    c.setAutoCommit(prevAutoCommit);
                }
            } catch (SQLException e) {
                SurvivorLootRespawnMetrics.recordDbError("batch_insert");
                LOGGER.error(
                        "[SurvivorLootRespawn] Failed to batch insert {} container loot states",
                        rows.size(),
                        e);
                return 0;
            }
        }
    }

    public static List<ContainerLootState> selectRolling(
            double worldAgeHours, int quietPeriodHours) {
        List<ContainerLootState> out = new ArrayList<>();
        synchronized (SurvivorLootRespawnDatabase.class) {
            try {
                Connection c = SurvivorLootRespawnDatabase.getConnection();
                try (PreparedStatement ps = c.prepareStatement(SELECT_ROLLING_SQL)) {
                    ps.setDouble(1, worldAgeHours);
                    ps.setInt(2, quietPeriodHours);
                    try (ResultSet rs = ps.executeQuery()) {
                        while (rs.next()) {
                            out.add(read(rs));
                        }
                    }
                }
            } catch (SQLException e) {
                SurvivorLootRespawnMetrics.recordDbError("select_rolling");
                LOGGER.error(
                        "[SurvivorLootRespawn] Failed to select rolling container loot states", e);
            }
        }
        return out;
    }

    public static List<ContainerLootState> selectQueuedInChunk(int chunkWX, int chunkWY) {
        int worldX0 = chunkWX * 8;
        int worldX1 = worldX0 + 8;
        int worldY0 = chunkWY * 8;
        int worldY1 = worldY0 + 8;
        List<ContainerLootState> out = new ArrayList<>();
        synchronized (SurvivorLootRespawnDatabase.class) {
            try {
                Connection c = SurvivorLootRespawnDatabase.getConnection();
                try (PreparedStatement ps = c.prepareStatement(SELECT_QUEUED_IN_CHUNK_SQL)) {
                    ps.setInt(1, worldX0);
                    ps.setInt(2, worldX1);
                    ps.setInt(3, worldY0);
                    ps.setInt(4, worldY1);
                    try (ResultSet rs = ps.executeQuery()) {
                        while (rs.next()) {
                            out.add(read(rs));
                        }
                    }
                }
            } catch (SQLException e) {
                SurvivorLootRespawnMetrics.recordDbError("select_queued_chunk");
                LOGGER.error(
                        "[SurvivorLootRespawn] Failed to select queued container loot states in chunk wx={} wy={}",
                        chunkWX,
                        chunkWY,
                        e);
            }
        }
        return out;
    }

    public static List<ContainerLootState> selectQueuedForSquare(int x, int y, int z) {
        List<ContainerLootState> out = new ArrayList<>();
        synchronized (SurvivorLootRespawnDatabase.class) {
            try {
                Connection c = SurvivorLootRespawnDatabase.getConnection();
                try (PreparedStatement ps = c.prepareStatement(SELECT_QUEUED_FOR_SQUARE_SQL)) {
                    ps.setInt(1, x);
                    ps.setInt(2, y);
                    ps.setInt(3, z);
                    try (ResultSet rs = ps.executeQuery()) {
                        while (rs.next()) {
                            out.add(read(rs));
                        }
                    }
                }
            } catch (SQLException e) {
                SurvivorLootRespawnMetrics.recordDbError("select_queued_square");
                LOGGER.error(
                        "[SurvivorLootRespawn] Failed to select queued container loot states at x={} y={} z={}",
                        x,
                        y,
                        z,
                        e);
            }
        }
        return out;
    }

    public static void markQueued(
            int x, int y, int z, String containerType, int containerIndex, double gameHours) {
        synchronized (SurvivorLootRespawnDatabase.class) {
            try {
                Connection c = SurvivorLootRespawnDatabase.getConnection();
                try (PreparedStatement ps = c.prepareStatement(MARK_QUEUED_SQL)) {
                    ps.setDouble(1, gameHours);
                    ps.setInt(2, x);
                    ps.setInt(3, y);
                    ps.setInt(4, z);
                    ps.setString(5, containerType);
                    ps.setInt(6, containerIndex);
                    ps.executeUpdate();
                }
            } catch (SQLException e) {
                SurvivorLootRespawnMetrics.recordDbError("mark_queued");
                LOGGER.error(
                        "[SurvivorLootRespawn] Failed to mark container loot state queued at x={} y={} z={} type={} idx={}",
                        x,
                        y,
                        z,
                        containerType,
                        containerIndex,
                        e);
            }
        }
    }

    public static void batchMarkQueued(List<ContainerLootState> rows, double gameHours) {
        if (rows.isEmpty()) {
            return;
        }
        synchronized (SurvivorLootRespawnDatabase.class) {
            try {
                Connection c = SurvivorLootRespawnDatabase.getConnection();
                boolean prevAutoCommit = c.getAutoCommit();
                c.setAutoCommit(false);
                try (PreparedStatement ps = c.prepareStatement(MARK_QUEUED_SQL)) {
                    for (ContainerLootState s : rows) {
                        ps.setDouble(1, gameHours);
                        ps.setInt(2, s.squareX());
                        ps.setInt(3, s.squareY());
                        ps.setInt(4, s.squareZ());
                        ps.setString(5, s.containerType());
                        ps.setInt(6, s.containerIndex());
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
                SurvivorLootRespawnMetrics.recordDbError("batch_mark_queued");
                LOGGER.error(
                        "[SurvivorLootRespawn] Failed to batch mark {} container loot states queued",
                        rows.size(),
                        e);
            }
        }
    }

    public static void delete(int x, int y, int z, String containerType, int containerIndex) {
        synchronized (SurvivorLootRespawnDatabase.class) {
            try {
                Connection c = SurvivorLootRespawnDatabase.getConnection();
                try (PreparedStatement ps = c.prepareStatement(DELETE_SQL)) {
                    ps.setInt(1, x);
                    ps.setInt(2, y);
                    ps.setInt(3, z);
                    ps.setString(4, containerType);
                    ps.setInt(5, containerIndex);
                    ps.executeUpdate();
                }
            } catch (SQLException e) {
                SurvivorLootRespawnMetrics.recordDbError("delete");
                LOGGER.error(
                        "[SurvivorLootRespawn] Failed to delete container loot state at x={} y={} z={} type={} idx={}",
                        x,
                        y,
                        z,
                        containerType,
                        containerIndex,
                        e);
            }
        }
    }

    public static void incrementFillAddedNothing(
            int x, int y, int z, String containerType, int containerIndex) {
        synchronized (SurvivorLootRespawnDatabase.class) {
            try {
                Connection c = SurvivorLootRespawnDatabase.getConnection();
                try (PreparedStatement ps = c.prepareStatement(INCREMENT_FILL_ADDED_NOTHING_SQL)) {
                    ps.setInt(1, x);
                    ps.setInt(2, y);
                    ps.setInt(3, z);
                    ps.setString(4, containerType);
                    ps.setInt(5, containerIndex);
                    ps.executeUpdate();
                }
            } catch (SQLException e) {
                SurvivorLootRespawnMetrics.recordDbError("increment_fill_added_nothing");
                LOGGER.error(
                        "[SurvivorLootRespawn] Failed to increment fill_added_nothing_count at x={} y={} z={} type={} idx={}",
                        x,
                        y,
                        z,
                        containerType,
                        containerIndex,
                        e);
            }
        }
    }

    public static long countTotal() {
        synchronized (SurvivorLootRespawnDatabase.class) {
            try {
                Connection c = SurvivorLootRespawnDatabase.getConnection();
                try (PreparedStatement ps = c.prepareStatement(COUNT_TOTAL_SQL);
                        ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        return rs.getLong(1);
                    }
                    return 0L;
                }
            } catch (SQLException e) {
                SurvivorLootRespawnMetrics.recordDbError("count_total");
                LOGGER.error(
                        "[SurvivorLootRespawn] Failed to count total container loot states", e);
                return 0L;
            }
        }
    }

    public static long countQueued() {
        synchronized (SurvivorLootRespawnDatabase.class) {
            try {
                Connection c = SurvivorLootRespawnDatabase.getConnection();
                try (PreparedStatement ps = c.prepareStatement(COUNT_QUEUED_SQL);
                        ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        return rs.getLong(1);
                    }
                    return 0L;
                }
            } catch (SQLException e) {
                SurvivorLootRespawnMetrics.recordDbError("count_queued");
                LOGGER.error(
                        "[SurvivorLootRespawn] Failed to count queued container loot states", e);
                return 0L;
            }
        }
    }

    private static ContainerLootState read(ResultSet rs) throws SQLException {
        double queued = rs.getDouble("respawn_queued_at_hours");
        Double queuedBoxed = rs.wasNull() ? null : queued;
        return new ContainerLootState(
                rs.getInt("square_x"),
                rs.getInt("square_y"),
                rs.getInt("square_z"),
                rs.getString("container_type"),
                rs.getInt("container_index"),
                rs.getDouble("looted_game_hours"),
                queuedBoxed,
                rs.getInt("fill_added_nothing_count"));
    }
}
