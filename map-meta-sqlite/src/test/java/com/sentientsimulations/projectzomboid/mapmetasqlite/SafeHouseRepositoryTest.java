package com.sentientsimulations.projectzomboid.mapmetasqlite;

import static org.junit.jupiter.api.Assertions.*;

import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class SafeHouseRepositoryTest {

    private SafeHouseDatabase database;
    private SafeHouseRepository repository;

    @BeforeEach
    void setUp() throws Exception {
        database = new SafeHouseDatabase(":memory:");
        repository = new SafeHouseRepository(database.getConnection());
    }

    @AfterEach
    void tearDown() throws Exception {
        database.close();
    }

    @Test
    void loadAllReturnsEmptyListWhenNoData() throws Exception {
        List<SafeHouseRecord> results = repository.loadAll();
        assertTrue(results.isEmpty());
    }

    @Test
    void saveAndLoadRoundTrip() throws Exception {
        var record =
                new SafeHouseRecord(
                        100,
                        200,
                        50,
                        40,
                        "alice",
                        0,
                        List.of("alice", "bob"),
                        1700000000000L,
                        "Alice's Base",
                        1699000000000L,
                        "Muldraugh",
                        List.of("bob"));

        repository.saveAll(List.of(record));
        List<SafeHouseRecord> loaded = repository.loadAll();

        assertEquals(1, loaded.size());
        SafeHouseRecord result = loaded.getFirst();
        assertEquals(100, result.x());
        assertEquals(200, result.y());
        assertEquals(50, result.w());
        assertEquals(40, result.h());
        assertEquals("alice", result.owner());
        assertEquals(0, result.hitPoints());
        assertEquals(List.of("alice", "bob"), result.players());
        assertEquals(1700000000000L, result.lastVisited());
        assertEquals("Alice's Base", result.title());
        assertEquals(1699000000000L, result.datetimeCreated());
        assertEquals("Muldraugh", result.location());
        assertEquals(List.of("bob"), result.playersRespawn());
    }

    @Test
    void saveAllReplacesExistingData() throws Exception {
        var first =
                new SafeHouseRecord(
                        10,
                        20,
                        30,
                        40,
                        "alice",
                        0,
                        List.of("alice"),
                        1L,
                        "First",
                        1L,
                        null,
                        List.of());

        repository.saveAll(List.of(first));

        var second =
                new SafeHouseRecord(
                        50,
                        60,
                        70,
                        80,
                        "bob",
                        5,
                        List.of("bob", "carol"),
                        2L,
                        "Second",
                        2L,
                        "Riverside",
                        List.of("carol"));

        repository.saveAll(List.of(second));

        List<SafeHouseRecord> loaded = repository.loadAll();
        assertEquals(1, loaded.size());
        assertEquals("bob", loaded.getFirst().owner());
        assertEquals(50, loaded.getFirst().x());
    }

    @Test
    void saveMultipleSafehouses() throws Exception {
        var sh1 =
                new SafeHouseRecord(
                        10,
                        20,
                        30,
                        40,
                        "alice",
                        0,
                        List.of("alice"),
                        1L,
                        "Base 1",
                        1L,
                        null,
                        List.of());
        var sh2 =
                new SafeHouseRecord(
                        100,
                        200,
                        50,
                        60,
                        "bob",
                        3,
                        List.of("bob", "dave"),
                        2L,
                        "Base 2",
                        2L,
                        "WestPoint",
                        List.of("dave"));

        repository.saveAll(List.of(sh1, sh2));

        List<SafeHouseRecord> loaded = repository.loadAll();
        assertEquals(2, loaded.size());
    }

    @Test
    void deleteAllClearsEverything() throws Exception {
        var record =
                new SafeHouseRecord(
                        10,
                        20,
                        30,
                        40,
                        "alice",
                        0,
                        List.of("alice", "bob"),
                        1L,
                        "Base",
                        1L,
                        null,
                        List.of("bob"));

        repository.saveAll(List.of(record));
        assertEquals(1, repository.loadAll().size());

        repository.deleteAll();
        assertTrue(repository.loadAll().isEmpty());
    }

    @Test
    void nullLocationHandledCorrectly() throws Exception {
        var record =
                new SafeHouseRecord(
                        10,
                        20,
                        30,
                        40,
                        "alice",
                        0,
                        List.of("alice"),
                        1L,
                        "Base",
                        1L,
                        null,
                        List.of());

        repository.saveAll(List.of(record));
        List<SafeHouseRecord> loaded = repository.loadAll();

        assertNull(loaded.getFirst().location());
    }

    @Test
    void emptyPlayersAndRespawns() throws Exception {
        var record =
                new SafeHouseRecord(
                        10, 20, 30, 40, "alice", 0, List.of(), 1L, "Base", 1L, null, List.of());

        repository.saveAll(List.of(record));
        List<SafeHouseRecord> loaded = repository.loadAll();

        assertTrue(loaded.getFirst().players().isEmpty());
        assertTrue(loaded.getFirst().playersRespawn().isEmpty());
    }
}
