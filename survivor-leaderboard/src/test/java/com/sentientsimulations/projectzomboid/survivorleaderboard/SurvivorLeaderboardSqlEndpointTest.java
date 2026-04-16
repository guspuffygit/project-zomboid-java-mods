package com.sentientsimulations.projectzomboid.survivorleaderboard;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.sentientsimulations.projectzomboid.survivorleaderboard.records.SqlExecutionResponse;
import java.io.File;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * Integration test for {@link SurvivorLeaderboardBridge#executeSql(String, java.sql.Connection)},
 * the code path behind the {@code POST /leaderboard/sql} endpoint. Uses a real SQLite leaderboard
 * DB in a temp dir so the schema and SQL dialect match production.
 */
class SurvivorLeaderboardSqlEndpointTest {

    @TempDir File tempDir;

    private SurvivorLeaderboardDatabase db;
    private SurvivorLeaderboardRepository repo;

    @BeforeEach
    void setUp() throws Exception {
        db =
                new SurvivorLeaderboardDatabase(
                        new File(tempDir, "survivor_leaderboard.db").getAbsolutePath());
        repo = new SurvivorLeaderboardRepository(db.getConnection());
    }

    @AfterEach
    void tearDown() throws Exception {
        if (db != null) {
            db.close();
        }
    }

    @Test
    void selectReturnsColumnsAndRows() throws Exception {
        repo.insertSurvivor(1L, "alice");
        repo.updateDayCount(1L, "alice", 7);
        repo.insertSurvivor(2L, "bob");
        repo.updateDayCount(2L, "bob", 3);

        SqlExecutionResponse response =
                SurvivorLeaderboardBridge.executeSql(
                        "SELECT username, day_count FROM survivors ORDER BY day_count DESC",
                        db.getConnection());

        assertNull(response.error());
        assertNull(response.updateCount());
        assertEquals(List.of("username", "day_count"), response.columns());
        assertEquals(2, response.rows().size());

        List<Object> first = response.rows().get(0);
        assertEquals("alice", first.get(0));
        assertEquals(7, ((Number) first.get(1)).intValue());

        List<Object> second = response.rows().get(1);
        assertEquals("bob", second.get(0));
        assertEquals(3, ((Number) second.get(1)).intValue());
    }

    @Test
    void selectOnEmptyTableReturnsNoRows() {
        SqlExecutionResponse response =
                SurvivorLeaderboardBridge.executeSql(
                        "SELECT username FROM survivors", db.getConnection());

        assertNull(response.error());
        assertEquals(List.of("username"), response.columns());
        assertTrue(response.rows().isEmpty());
    }

    @Test
    void updateReturnsUpdateCount() throws Exception {
        repo.insertSurvivor(1L, "alice");
        repo.insertSurvivor(2L, "bob");

        SqlExecutionResponse response =
                SurvivorLeaderboardBridge.executeSql(
                        "UPDATE survivors SET kill_count = 99", db.getConnection());

        assertNull(response.error());
        assertNull(response.columns());
        assertNull(response.rows());
        assertEquals(2, response.updateCount());

        SqlExecutionResponse after =
                SurvivorLeaderboardBridge.executeSql(
                        "SELECT kill_count FROM survivors WHERE steam_id = 1", db.getConnection());
        assertEquals(99, ((Number) after.rows().get(0).get(0)).intValue());
    }

    @Test
    void deleteReturnsUpdateCount() throws Exception {
        repo.insertSurvivor(1L, "alice");
        repo.insertSurvivor(2L, "bob");
        repo.updateDayCount(2L, "bob", 1);

        SqlExecutionResponse response =
                SurvivorLeaderboardBridge.executeSql(
                        "DELETE FROM survivors WHERE steam_id = 1", db.getConnection());

        assertNull(response.error());
        assertEquals(1, response.updateCount());
        assertEquals(1, repo.loadAllOrdered().size());
    }

    @Test
    void invalidSqlReturnsError() {
        SqlExecutionResponse response =
                SurvivorLeaderboardBridge.executeSql(
                        "SELECT * FROM does_not_exist", db.getConnection());

        assertNotNull(response.error());
        assertNull(response.columns());
        assertNull(response.rows());
        assertNull(response.updateCount());
    }

    @Test
    void syntaxErrorReturnsError() {
        SqlExecutionResponse response =
                SurvivorLeaderboardBridge.executeSql("NOT VALID SQL AT ALL", db.getConnection());

        assertNotNull(response.error());
    }
}
