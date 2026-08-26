package com.sentientsimulations.projectzomboid.avcsmapview;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.sqlite.SQLiteConfig;
import zombie.ZomboidFileSystem;

/**
 * Reads vehicle positions straight out of the save's {@code vehicles.db}, but only for rows proven
 * to belong to the claim asking for them.
 *
 * <p>Vanilla's {@code VehiclesDB2} owns its own connection on the world-streamer thread and commits
 * every row write immediately, so a separate read-only connection sees the latest unloaded-vehicle
 * positions without touching PZ's connection from another thread. The busy timeout covers the brief
 * exclusive lock PZ takes while committing.
 *
 * <p>The row id alone is not proof of ownership: vanilla recycles the lowest free sqlId, so an
 * orphaned claim's id can point at a stranger's newer vehicle. A claimed vehicle carries its claim
 * key as {@code modData.SQLID}, and mod data is serialized inside the row's {@code data} blob as
 * {@code [0x00][len:short]["SQLID"][0x01][double]} (KahluaTableImpl.save key/value encoding, both
 * on the vehicle's own table and on a mule part's). {@link #readVerified} scans the blob for that
 * exact byte signature and reports rows without it as unverified instead of returning a position.
 */
final class VehiclesDbLocations {

    record Position(float x, float y) {}

    /**
     * {@code positions} holds rows whose data blob carries the expected claim key; {@code
     * unverified} the requested ids whose row exists but carries a different (or no) claim key.
     */
    record VerifiedRead(Map<Integer, Position> positions, Set<Integer> unverified) {

        static final VerifiedRead EMPTY = new VerifiedRead(Map.of(), Set.of());
    }

    static final String DB_FILE = "vehicles.db";
    static final int IN_BATCH = 500;
    private static final int BUSY_TIMEOUT_MS = 1000;
    private static final byte KEY_TYPE_STRING = 0;
    private static final byte VALUE_TYPE_DOUBLE = 1;

    private VehiclesDbLocations() {}

    static VerifiedRead readVerifiedFromCurrentSave(Map<Integer, Double> claimKeyBySqlId) {
        return readVerified(
                new File(ZomboidFileSystem.instance.getCurrentSaveDir(), DB_FILE), claimKeyBySqlId);
    }

    static VerifiedRead readVerified(File dbFile, Map<Integer, Double> claimKeyBySqlId) {
        if (claimKeyBySqlId.isEmpty()) {
            return VerifiedRead.EMPTY;
        }
        if (!dbFile.isFile()) {
            LOGGER.warn("AVCS location sync: {} not found", dbFile);
            return VerifiedRead.EMPTY;
        }
        SQLiteConfig config = new SQLiteConfig();
        config.setReadOnly(true);
        config.setBusyTimeout(BUSY_TIMEOUT_MS);
        Map<Integer, Position> positions = new HashMap<>();
        Set<Integer> unverified = new LinkedHashSet<>();
        try (Connection conn = config.createConnection("jdbc:sqlite:" + dbFile.getAbsolutePath())) {
            List<Integer> ids = new ArrayList<>(claimKeyBySqlId.keySet());
            for (int from = 0; from < ids.size(); from += IN_BATCH) {
                List<Integer> batch = ids.subList(from, Math.min(ids.size(), from + IN_BATCH));
                readBatch(conn, batch, claimKeyBySqlId, positions, unverified);
            }
        } catch (SQLException e) {
            LOGGER.warn("AVCS location sync: reading {} failed: {}", dbFile, e.toString());
        }
        return new VerifiedRead(positions, unverified);
    }

    private static void readBatch(
            Connection conn,
            List<Integer> ids,
            Map<Integer, Double> claimKeyBySqlId,
            Map<Integer, Position> positions,
            Set<Integer> unverified)
            throws SQLException {
        String sql =
                "SELECT id, x, y, data FROM vehicles WHERE id IN ("
                        + "?,".repeat(ids.size() - 1)
                        + "?)";
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            for (int i = 0; i < ids.size(); i++) {
                ps.setInt(i + 1, ids.get(i));
            }
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    int sqlId = rs.getInt(1);
                    Double claimKey = claimKeyBySqlId.get(sqlId);
                    byte[] data = rs.getBytes(4);
                    if (claimKey != null
                            && data != null
                            && contains(data, claimKeySignature(claimKey))) {
                        positions.put(sqlId, new Position(rs.getFloat(2), rs.getFloat(3)));
                    } else {
                        unverified.add(sqlId);
                    }
                }
            }
        }
    }

    /**
     * The serialized mod-data entry {@code SQLID = claimKey}: string key ({@code GameWindow
     * .WriteString}: big-endian short length + UTF-8 bytes) then a big-endian IEEE-754 double.
     */
    static byte[] claimKeySignature(double claimKey) {
        byte[] name = "SQLID".getBytes(StandardCharsets.UTF_8);
        byte[] signature = new byte[1 + 2 + name.length + 1 + 8];
        int at = 0;
        signature[at++] = KEY_TYPE_STRING;
        signature[at++] = (byte) (name.length >> 8);
        signature[at++] = (byte) name.length;
        for (byte b : name) {
            signature[at++] = b;
        }
        signature[at++] = VALUE_TYPE_DOUBLE;
        long bits = Double.doubleToLongBits(claimKey);
        for (int shift = 56; shift >= 0; shift -= 8) {
            signature[at++] = (byte) (bits >> shift);
        }
        return signature;
    }

    static boolean contains(byte[] haystack, byte[] needle) {
        outer:
        for (int from = 0; from <= haystack.length - needle.length; from++) {
            for (int i = 0; i < needle.length; i++) {
                if (haystack[from + i] != needle[i]) {
                    continue outer;
                }
            }
            return true;
        }
        return false;
    }
}
