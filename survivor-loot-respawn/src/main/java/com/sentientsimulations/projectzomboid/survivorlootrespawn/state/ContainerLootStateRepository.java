package com.sentientsimulations.projectzomboid.survivorlootrespawn.state;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;

public final class ContainerLootStateRepository {

    private static final String UPSERT_SQL =
            """
            INSERT INTO container_loot_state (
                square_x, square_y, square_z, container_type, container_index,
                looted_game_hours, item_count, respawn_queued_at_hours,
                last_username, last_steam_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, NULL, ?, ?)
            ON CONFLICT(square_x, square_y, square_z, container_type, container_index)
            DO UPDATE SET
                item_count    = excluded.item_count,
                last_username = excluded.last_username,
                last_steam_id = excluded.last_steam_id""";

    private static final String SELECT_ROLLING_SQL =
            """
            SELECT square_x, square_y, square_z, container_type, container_index,
                   looted_game_hours, item_count, respawn_queued_at_hours,
                   last_username, last_steam_id
              FROM container_loot_state
             WHERE respawn_queued_at_hours IS NULL""";

    private static final String SELECT_QUEUED_FOR_SQUARE_SQL =
            """
            SELECT square_x, square_y, square_z, container_type, container_index,
                   looted_game_hours, item_count, respawn_queued_at_hours,
                   last_username, last_steam_id
              FROM container_loot_state
             WHERE square_x = ? AND square_y = ? AND square_z = ?
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

    private ContainerLootStateRepository() {}

    public static void upsert(ContainerLootState s) {
        try {
            Connection c = SurvivorLootRespawnDatabase.getConnection();
            try (PreparedStatement ps = c.prepareStatement(UPSERT_SQL)) {
                ps.setInt(1, s.squareX());
                ps.setInt(2, s.squareY());
                ps.setInt(3, s.squareZ());
                ps.setString(4, s.containerType());
                ps.setInt(5, s.containerIndex());
                ps.setDouble(6, s.lootedGameHours());
                ps.setInt(7, s.itemCount());
                ps.setString(8, s.lastUsername());
                ps.setString(9, s.lastSteamId());
                ps.executeUpdate();
            }
        } catch (SQLException e) {
            LOGGER.error(
                    "Failed to upsert container loot state at x={} y={} z={} type={} idx={}",
                    s.squareX(),
                    s.squareY(),
                    s.squareZ(),
                    s.containerType(),
                    s.containerIndex(),
                    e);
        }
    }

    public static List<ContainerLootState> selectRolling() {
        List<ContainerLootState> out = new ArrayList<>();
        try {
            Connection c = SurvivorLootRespawnDatabase.getConnection();
            try (PreparedStatement ps = c.prepareStatement(SELECT_ROLLING_SQL);
                    ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    out.add(read(rs));
                }
            }
        } catch (SQLException e) {
            LOGGER.error("Failed to select rolling container loot states", e);
        }
        return out;
    }

    public static List<ContainerLootState> selectQueuedForSquare(int x, int y, int z) {
        List<ContainerLootState> out = new ArrayList<>();
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
            LOGGER.error(
                    "Failed to select queued container loot states at x={} y={} z={}", x, y, z, e);
        }
        return out;
    }

    public static void markQueued(
            int x, int y, int z, String containerType, int containerIndex, double gameHours) {
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
            LOGGER.error(
                    "Failed to mark container loot state queued at x={} y={} z={} type={} idx={}",
                    x,
                    y,
                    z,
                    containerType,
                    containerIndex,
                    e);
        }
    }

    public static void delete(int x, int y, int z, String containerType, int containerIndex) {
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
            LOGGER.error(
                    "Failed to delete container loot state at x={} y={} z={} type={} idx={}",
                    x,
                    y,
                    z,
                    containerType,
                    containerIndex,
                    e);
        }
    }

    private static ContainerLootState read(ResultSet rs) throws SQLException {
        double queued = rs.getDouble("respawn_queued_at_hours");
        Double queuedBoxed = rs.wasNull() ? null : queued;
        String username = rs.getString("last_username");
        if (rs.wasNull()) {
            username = null;
        }
        String steamId = rs.getString("last_steam_id");
        if (rs.wasNull()) {
            steamId = null;
        }
        return new ContainerLootState(
                rs.getInt("square_x"),
                rs.getInt("square_y"),
                rs.getInt("square_z"),
                rs.getString("container_type"),
                rs.getInt("container_index"),
                rs.getDouble("looted_game_hours"),
                rs.getInt("item_count"),
                queuedBoxed,
                username,
                steamId);
    }
}
