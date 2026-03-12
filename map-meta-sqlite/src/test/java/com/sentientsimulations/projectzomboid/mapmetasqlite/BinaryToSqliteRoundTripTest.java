package com.sentientsimulations.projectzomboid.mapmetasqlite;

import static org.junit.jupiter.api.Assertions.*;

import java.io.File;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import zombie.GameWindow;
import zombie.iso.areas.SafeHouse;

class BinaryToSqliteRoundTripTest {

    @TempDir File tempDir;
    private SafeHouseDatabase database;
    private SafeHouseRepository repository;

    @BeforeEach
    void setUp() throws Exception {
        database = new SafeHouseDatabase(new File(tempDir, "map_meta.db").getAbsolutePath());
        repository = new SafeHouseRepository(database.getConnection());
        SafeHouse.clearSafehouseList();
    }

    @AfterEach
    void tearDown() throws Exception {
        database.close();
        SafeHouse.clearSafehouseList();
    }

    @Test
    void binaryAndSqliteDataAreEquivalent() throws Exception {
        // Create SafeHouse objects using constructor + direct list manipulation
        // (avoiding addPlayer() which triggers game static initializers)
        SafeHouse sh1 = new SafeHouse(100, 200, 50, 40, "alice");
        sh1.setHitPoints(3);
        sh1.getPlayers().add("bob");
        sh1.setLastVisited(1700000000000L);
        sh1.setTitle("Alice's Base");
        sh1.setDatetimeCreated(1699000000000L);
        sh1.setLocation("Muldraugh");
        sh1.getPlayersRespawn().add("bob");

        SafeHouse sh2 = new SafeHouse(300, 400, 60, 50, "carol");
        sh2.setHitPoints(0);
        sh2.getPlayers().add("dave");
        sh2.getPlayers().add("eve");
        sh2.setLastVisited(1701000000000L);
        sh2.setTitle("Carol's Fort");
        sh2.setDatetimeCreated(1700500000000L);
        sh2.setLocation("Riverside");
        sh2.getPlayersRespawn().add("dave");
        sh2.getPlayersRespawn().add("eve");

        List<SafeHouse> originals = List.of(sh1, sh2);

        // Write to binary format (same as vanilla map_meta.bin SafeHouse section)
        ByteBuffer buffer = ByteBuffer.allocate(8192);
        buffer.putInt(originals.size());
        for (SafeHouse sh : originals) {
            sh.save(buffer);
        }
        buffer.flip();

        // Parse binary back into records (mirrors SafeHouse.load() binary format)
        int count = buffer.getInt();
        List<SafeHouseRecord> fromBinary = new ArrayList<>();
        for (int i = 0; i < count; i++) {
            fromBinary.add(parseBinaryRecord(buffer));
        }

        // Convert live SafeHouse objects to records via bridge
        List<SafeHouseRecord> fromBridge = SafeHouseSqliteBridge.toRecords(originals);

        // Save to SQLite and load back
        repository.saveAll(fromBridge);
        List<SafeHouseRecord> fromSqlite = repository.loadAll();

        // All three representations must match
        assertEquals(fromBinary.size(), fromBridge.size());
        assertEquals(fromBridge.size(), fromSqlite.size());

        for (int i = 0; i < fromBinary.size(); i++) {
            assertEquals(fromBinary.get(i), fromBridge.get(i), "binary vs bridge mismatch at " + i);
            assertEquals(fromBridge.get(i), fromSqlite.get(i), "bridge vs sqlite mismatch at " + i);
        }
    }

    @Test
    void singleSafehouseMinimalFields() throws Exception {
        SafeHouse sh = new SafeHouse(10, 20, 30, 40, "solo");
        sh.setLastVisited(1000L);
        sh.setTitle("Solo Base");
        sh.setDatetimeCreated(900L);
        sh.setLocation("WestPoint");

        // Binary round-trip
        ByteBuffer buffer = ByteBuffer.allocate(4096);
        sh.save(buffer);
        buffer.flip();
        SafeHouseRecord fromBinary = parseBinaryRecord(buffer);

        // SQLite round-trip
        List<SafeHouseRecord> records = SafeHouseSqliteBridge.toRecords(List.of(sh));
        repository.saveAll(records);
        SafeHouseRecord fromSqlite = repository.loadAll().getFirst();

        assertEquals(fromBinary, records.getFirst());
        assertEquals(records.getFirst(), fromSqlite);

        assertEquals(10, fromSqlite.x());
        assertEquals(20, fromSqlite.y());
        assertEquals(30, fromSqlite.w());
        assertEquals(40, fromSqlite.h());
        assertEquals("solo", fromSqlite.owner());
        assertEquals(0, fromSqlite.hitPoints());
        assertEquals(List.of("solo"), fromSqlite.players());
        assertEquals(1000L, fromSqlite.lastVisited());
        assertEquals("Solo Base", fromSqlite.title());
        assertEquals(900L, fromSqlite.datetimeCreated());
        assertEquals("WestPoint", fromSqlite.location());
        assertTrue(fromSqlite.playersRespawn().isEmpty());
    }

    @Test
    void toRecordsPreservesAllFields() {
        SafeHouse sh = new SafeHouse(50, 60, 70, 80, "owner");
        sh.setHitPoints(7);
        sh.getPlayers().add("member1");
        sh.getPlayers().add("member2");
        sh.setLastVisited(5000L);
        sh.setTitle("Test House");
        sh.setDatetimeCreated(4000L);
        sh.setLocation("Rosewood");
        sh.getPlayersRespawn().add("member1");

        List<SafeHouseRecord> records = SafeHouseSqliteBridge.toRecords(List.of(sh));

        assertEquals(1, records.size());
        SafeHouseRecord rec = records.getFirst();
        assertEquals(50, rec.x());
        assertEquals(60, rec.y());
        assertEquals(70, rec.w());
        assertEquals(80, rec.h());
        assertEquals("owner", rec.owner());
        assertEquals(7, rec.hitPoints());
        assertEquals(List.of("owner", "member1", "member2"), rec.players());
        assertEquals(5000L, rec.lastVisited());
        assertEquals("Test House", rec.title());
        assertEquals(4000L, rec.datetimeCreated());
        assertEquals("Rosewood", rec.location());
        assertEquals(List.of("member1"), rec.playersRespawn());
    }

    @Test
    void toRecordsHandlesEmptySafehouseList() {
        List<SafeHouseRecord> records = SafeHouseSqliteBridge.toRecords(List.of());
        assertTrue(records.isEmpty());
    }

    /**
     * Parses a single SafeHouse from the binary format produced by {@code SafeHouse.save()}.
     * Mirrors the vanilla {@code SafeHouse.load(ByteBuffer, int)} deserialization for worldVersion
     * 244.
     */
    private static SafeHouseRecord parseBinaryRecord(ByteBuffer buffer) {
        int x = buffer.getInt();
        int y = buffer.getInt();
        int w = buffer.getInt();
        int h = buffer.getInt();
        String owner = GameWindow.ReadString(buffer);
        int hitPoints = buffer.getInt();

        int playerCount = buffer.getInt();
        List<String> players = new ArrayList<>(playerCount);
        for (int i = 0; i < playerCount; i++) {
            players.add(GameWindow.ReadString(buffer));
        }

        long lastVisited = buffer.getLong();
        String title = GameWindow.ReadString(buffer);
        long datetimeCreated = buffer.getLong();
        String location = GameWindow.ReadString(buffer);

        int respawnCount = buffer.getInt();
        List<String> playersRespawn = new ArrayList<>(respawnCount);
        for (int i = 0; i < respawnCount; i++) {
            playersRespawn.add(GameWindow.ReadString(buffer));
        }

        return new SafeHouseRecord(
                x, y, w, h, owner, hitPoints, players, lastVisited, title, datetimeCreated,
                location, playersRespawn);
    }
}
