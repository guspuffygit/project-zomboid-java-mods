package com.sentientsimulations.projectzomboid.avcsmapview;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.sentientsimulations.projectzomboid.avcsmapview.VehiclesDbLocations.Position;
import com.sentientsimulations.projectzomboid.avcsmapview.VehiclesDbLocations.VerifiedRead;
import java.io.File;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.Statement;
import java.util.HashMap;
import java.util.Map;
import java.util.Set;
import java.util.function.IntFunction;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class VehiclesDbLocationsTest {

    private static final double TS = 1712345678d;

    // vanilla VehiclesDB2.SQLStore.create() schema
    private static final String CREATE =
            "CREATE TABLE vehicles (id INTEGER PRIMARY KEY NOT NULL, wx INTEGER, wy INTEGER,"
                    + " x FLOAT, y FLOAT, inMeta BOOLEAN NULL DEFAULT FALSE, worldversion INTEGER,"
                    + " data BLOB);";

    private static double key(int sqlId) {
        return Double.parseDouble((long) TS + "" + sqlId);
    }

    /** A vehicle data blob with the claim-key mod-data entry buried mid-stream. */
    private static byte[] blobWithKey(double claimKey) {
        byte[] signature = VehiclesDbLocations.claimKeySignature(claimKey);
        byte[] blob = new byte[64 + signature.length + 32];
        for (int i = 0; i < blob.length; i++) {
            blob[i] = (byte) (i * 31);
        }
        System.arraycopy(signature, 0, blob, 64, signature.length);
        return blob;
    }

    private static File vanillaDb(Path dir, int rows, IntFunction<byte[]> blobForId)
            throws Exception {
        File file = dir.resolve("vehicles.db").toFile();
        try (Connection conn =
                DriverManager.getConnection("jdbc:sqlite:" + file.getAbsolutePath())) {
            try (Statement st = conn.createStatement()) {
                st.executeUpdate(CREATE);
            }
            conn.setAutoCommit(false);
            try (PreparedStatement ps =
                    conn.prepareStatement(
                            "INSERT INTO vehicles(wx,wy,x,y,worldversion,inMeta,data,id)"
                                    + " VALUES(?,?,?,?,?,?,?,?)")) {
                for (int id = 1; id <= rows; id++) {
                    ps.setInt(1, id / 8);
                    ps.setInt(2, id / 8);
                    ps.setFloat(3, id + 0.25f);
                    ps.setFloat(4, id * 2 + 0.75f);
                    ps.setInt(5, 249);
                    ps.setBoolean(6, false);
                    ps.setBytes(7, blobForId.apply(id));
                    ps.setInt(8, id);
                    ps.addBatch();
                }
                ps.executeBatch();
            }
            conn.commit();
        }
        return file;
    }

    @Test
    void onlyRowsCarryingTheExpectedClaimKeyResolve(@TempDir Path dir) throws Exception {
        // odd rows are imprinted with their own claim key, even rows with a stranger's
        File db =
                vanillaDb(
                        dir,
                        10,
                        id -> id % 2 == 1 ? blobWithKey(key(id)) : blobWithKey(key(id + 100)));
        Map<Integer, Double> asked = new HashMap<>();
        asked.put(1, key(1)); // imprinted, verified
        asked.put(2, key(2)); // recycled: blob carries another key
        asked.put(3, key(99)); // orphaned claim decoding to a live row
        asked.put(99, key(99)); // no row at all

        VerifiedRead got = VehiclesDbLocations.readVerified(db, asked);

        assertEquals(Map.of(1, new Position(1.25f, 2.75f)), got.positions());
        assertEquals(Set.of(2, 3), got.unverified());
    }

    @Test
    void nullBlobIsUnverified(@TempDir Path dir) throws Exception {
        File db = vanillaDb(dir, 1, id -> null);

        VerifiedRead got = VehiclesDbLocations.readVerified(db, Map.of(1, key(1)));

        assertTrue(got.positions().isEmpty());
        assertEquals(Set.of(1), got.unverified());
    }

    @Test
    void spansMultipleInBatches(@TempDir Path dir) throws Exception {
        int rows = VehiclesDbLocations.IN_BATCH * 2 + 7;
        File db = vanillaDb(dir, rows, id -> blobWithKey(key(id)));
        Map<Integer, Double> asked = new HashMap<>();
        for (int id = 1; id <= rows; id++) {
            asked.put(id, key(id));
        }

        VerifiedRead got = VehiclesDbLocations.readVerified(db, asked);

        assertEquals(rows, got.positions().size());
        assertTrue(got.unverified().isEmpty());
        assertEquals(new Position(rows + 0.25f, rows * 2 + 0.75f), got.positions().get(rows));
    }

    @Test
    void emptyInputAndMissingFileYieldNothing(@TempDir Path dir) {
        File nope = dir.resolve("nope.db").toFile();
        assertTrue(VehiclesDbLocations.readVerified(nope, Map.of(1, key(1))).positions().isEmpty());
        assertTrue(VehiclesDbLocations.readVerified(nope, Map.of()).positions().isEmpty());
        assertTrue(VehiclesDbLocations.readVerified(nope, Map.of()).unverified().isEmpty());
    }

    @Test
    void signatureMatchesKahluaModDataEncoding() {
        // KahluaTableImpl.save: key type 0x00, WriteString short length + UTF-8, value type 0x01,
        // big-endian IEEE-754 double
        byte[] signature = VehiclesDbLocations.claimKeySignature(key(911));
        assertEquals(17, signature.length);
        assertEquals(0, signature[0]);
        assertEquals(0, signature[1]);
        assertEquals(5, signature[2]);
        assertEquals("SQLID", new String(signature, 3, 5));
        assertEquals(1, signature[8]);
        long bits = Double.doubleToLongBits(key(911));
        for (int i = 0; i < 8; i++) {
            assertEquals((byte) (bits >> (56 - 8 * i)), signature[9 + i]);
        }

        byte[] blob = blobWithKey(key(911));
        assertTrue(VehiclesDbLocations.contains(blob, signature));
        assertFalse(VehiclesDbLocations.contains(blob, VehiclesDbLocations.claimKeySignature(1d)));
        assertTrue(VehiclesDbLocations.contains(signature, signature));
        assertFalse(VehiclesDbLocations.contains(new byte[3], signature));
    }
}
