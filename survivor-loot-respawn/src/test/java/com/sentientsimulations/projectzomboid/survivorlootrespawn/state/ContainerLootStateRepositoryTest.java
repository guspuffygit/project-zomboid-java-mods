package com.sentientsimulations.projectzomboid.survivorlootrespawn.state;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.lang.reflect.Field;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.Statement;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class ContainerLootStateRepositoryTest {

    private static final String CREATE_TABLE_SQL =
            """
            CREATE TABLE container_loot_state (
                square_x         INTEGER NOT NULL,
                square_y         INTEGER NOT NULL,
                square_z         INTEGER NOT NULL,
                container_type   TEXT    NOT NULL,
                container_index  INTEGER NOT NULL,
                looted_game_hours       REAL    NOT NULL,
                respawn_queued_at_hours REAL,
                PRIMARY KEY (square_x, square_y, square_z, container_type, container_index)
            ) WITHOUT ROWID""";

    private Connection conn;
    private Connection originalConn;

    @BeforeEach
    void setUp() throws Exception {
        conn = DriverManager.getConnection("jdbc:sqlite::memory:");
        try (Statement stmt = conn.createStatement()) {
            stmt.execute(CREATE_TABLE_SQL);
        }
        originalConn = swapDatabaseConnection(conn);
    }

    @AfterEach
    void tearDown() throws Exception {
        swapDatabaseConnection(originalConn);
        if (conn != null) {
            conn.close();
        }
    }

    @Test
    void selectRollingReturnsRowsLootedBeforeQuietPeriodEnd() {
        insert(1, 1, 0, "fridge", 0, /* looted */ 100.0, null);
        insert(2, 2, 0, "counter", 0, /* looted */ 150.0, null);
        insert(3, 3, 0, "crate", 0, /* looted */ 199.0, null);

        List<ContainerLootState> out =
                ContainerLootStateRepository.selectRolling(/* world */ 200.0, /* quiet */ 50);

        Set<Integer> xs = out.stream().map(ContainerLootState::squareX).collect(Collectors.toSet());
        assertEquals(Set.of(1, 2), xs, "only rows quiet-period-old or older are eligible");
    }

    @Test
    void quietPeriodBoundaryIsInclusive() {
        insert(10, 10, 0, "fridge", 0, /* looted */ 100.0, null);

        List<ContainerLootState> out =
                ContainerLootStateRepository.selectRolling(/* world */ 200.0, /* quiet */ 100);

        assertEquals(1, out.size(), "row looted exactly at quiet-period boundary must be eligible");
    }

    @Test
    void quietPeriodZeroEligibleForAllUnqueuedRows() {
        insert(1, 1, 0, "fridge", 0, 50.0, null);
        insert(2, 2, 0, "counter", 0, 199.9, null);

        List<ContainerLootState> out =
                ContainerLootStateRepository.selectRolling(/* world */ 200.0, /* quiet */ 0);

        assertEquals(2, out.size());
    }

    @Test
    void queuedRowsExcludedRegardlessOfQuietPeriod() {
        insert(1, 1, 0, "fridge", 0, /* looted */ 100.0, /* queued */ 150.0);
        insert(2, 2, 0, "counter", 0, /* looted */ 100.0, null);

        List<ContainerLootState> out =
                ContainerLootStateRepository.selectRolling(/* world */ 200.0, /* quiet */ 0);

        assertEquals(1, out.size());
        assertEquals(2, out.getFirst().squareX(), "queued row must be filtered out");
        assertNull(out.getFirst().respawnQueuedAtHours());
    }

    @Test
    void selectRollingReadsAllColumns() {
        insert(7, 8, 1, "crate", 2, /* looted */ 42.5, null);

        List<ContainerLootState> out = ContainerLootStateRepository.selectRolling(100.0, 0);

        assertEquals(1, out.size());
        ContainerLootState s = out.getFirst();
        assertEquals(7, s.squareX());
        assertEquals(8, s.squareY());
        assertEquals(1, s.squareZ());
        assertEquals("crate", s.containerType());
        assertEquals(2, s.containerIndex());
        assertEquals(42.5, s.lootedGameHours());
        assertNull(s.respawnQueuedAtHours());
    }

    @Test
    void markQueuedSetsTimestampAndExcludesRowFromSelectRolling() {
        insert(5, 5, 0, "fridge", 0, /* looted */ 100.0, null);

        ContainerLootStateRepository.markQueued(5, 5, 0, "fridge", 0, /* queued */ 175.0);

        List<ContainerLootState> rolling =
                ContainerLootStateRepository.selectRolling(/* world */ 200.0, /* quiet */ 0);
        assertTrue(rolling.isEmpty(), "row should no longer be eligible to roll after queueing");

        List<ContainerLootState> queued =
                ContainerLootStateRepository.selectQueuedForSquare(5, 5, 0);
        assertEquals(1, queued.size());
        assertNotNull(queued.getFirst().respawnQueuedAtHours());
        assertEquals(175.0, queued.getFirst().respawnQueuedAtHours(), 1e-9);
    }

    @Test
    void insertIfMissingAddsRowWithNullQueued() {
        boolean inserted =
                ContainerLootStateRepository.insertIfMissing(4, 5, 0, "fridge", 2, 123.5);

        assertTrue(inserted);
        List<ContainerLootState> rolling = ContainerLootStateRepository.selectRolling(200.0, 0);
        assertEquals(1, rolling.size());
        ContainerLootState s = rolling.getFirst();
        assertEquals(4, s.squareX());
        assertEquals(5, s.squareY());
        assertEquals(0, s.squareZ());
        assertEquals("fridge", s.containerType());
        assertEquals(2, s.containerIndex());
        assertEquals(123.5, s.lootedGameHours());
        assertNull(s.respawnQueuedAtHours(), "newly tracked rows enter normal roll cycle, not queued");
    }

    @Test
    void insertIfMissingPreservesExistingRow() {
        insert(1, 1, 0, "fridge", 0, /* looted */ 100.0, /* queued */ 150.0);

        boolean inserted =
                ContainerLootStateRepository.insertIfMissing(1, 1, 0, "fridge", 0, 999.0);

        assertFalse(inserted, "existing row must not be overwritten");
        List<ContainerLootState> queued = ContainerLootStateRepository.selectQueuedForSquare(1, 1, 0);
        assertEquals(1, queued.size());
        ContainerLootState s = queued.getFirst();
        assertEquals(
                100.0, s.lootedGameHours(), "looted_game_hours must not be overwritten by re-insert");
        assertEquals(
                150.0,
                s.respawnQueuedAtHours(),
                "respawn_queued_at_hours must not be overwritten by re-insert");
    }

    private void insert(
            int x,
            int y,
            int z,
            String type,
            int index,
            double lootedHours,
            Double queuedHours) {
        String sql =
                "INSERT INTO container_loot_state ("
                        + "square_x, square_y, square_z, container_type, container_index, "
                        + "looted_game_hours, respawn_queued_at_hours) "
                        + "VALUES (?, ?, ?, ?, ?, ?, ?)";
        try (PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, x);
            ps.setInt(2, y);
            ps.setInt(3, z);
            ps.setString(4, type);
            ps.setInt(5, index);
            ps.setDouble(6, lootedHours);
            if (queuedHours == null) {
                ps.setNull(7, java.sql.Types.REAL);
            } else {
                ps.setDouble(7, queuedHours);
            }
            ps.executeUpdate();
        } catch (Exception e) {
            throw new RuntimeException("test insert failed", e);
        }
    }

    private static Connection swapDatabaseConnection(Connection replacement) throws Exception {
        Field f = SurvivorLootRespawnDatabase.class.getDeclaredField("connection");
        f.setAccessible(true);
        Connection prev = (Connection) f.get(null);
        f.set(null, replacement);
        return prev;
    }
}
