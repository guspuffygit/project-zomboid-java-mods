package com.sentientsimulations.projectzomboid.avcsmapview;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.sentientsimulations.projectzomboid.avcsmapview.VehiclesDbLocations.Position;
import java.io.File;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class VehiclesDbLocationsTest {

    // vanilla VehiclesDB2.SQLStore.create() schema
    private static final String CREATE =
            "CREATE TABLE vehicles (id INTEGER PRIMARY KEY NOT NULL, wx INTEGER, wy INTEGER,"
                    + " x FLOAT, y FLOAT, inMeta BOOLEAN NULL DEFAULT FALSE, worldversion INTEGER,"
                    + " data BLOB);";

    private static File vanillaDb(Path dir, int rows) throws Exception {
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
                    ps.setBytes(7, new byte[] {1, 2, 3});
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
    void readsRequestedIdsOnly(@TempDir Path dir) throws Exception {
        File db = vanillaDb(dir, 10);

        Map<Integer, Position> got = VehiclesDbLocations.read(db, Set.of(1, 3, 99));

        assertEquals(2, got.size());
        assertEquals(new Position(1.25f, 2.75f), got.get(1));
        assertEquals(new Position(3.25f, 6.75f), got.get(3));
        assertFalse(got.containsKey(99));
    }

    @Test
    void spansMultipleInBatches(@TempDir Path dir) throws Exception {
        int rows = VehiclesDbLocations.IN_BATCH * 2 + 7;
        File db = vanillaDb(dir, rows);
        List<Integer> ids = new ArrayList<>();
        for (int id = 1; id <= rows; id++) {
            ids.add(id);
        }

        Map<Integer, Position> got = VehiclesDbLocations.read(db, ids);

        assertEquals(rows, got.size());
        assertEquals(new Position(rows + 0.25f, rows * 2 + 0.75f), got.get(rows));
    }

    @Test
    void emptyInputAndMissingFileYieldNothing(@TempDir Path dir) {
        assertTrue(VehiclesDbLocations.read(dir.resolve("nope.db").toFile(), Set.of(1)).isEmpty());
        assertTrue(VehiclesDbLocations.read(dir.resolve("nope.db").toFile(), Set.of()).isEmpty());
    }
}
