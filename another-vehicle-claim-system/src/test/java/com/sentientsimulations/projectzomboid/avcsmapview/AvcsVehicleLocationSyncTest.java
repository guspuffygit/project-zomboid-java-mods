package com.sentientsimulations.projectzomboid.avcsmapview;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.sentientsimulations.projectzomboid.avcsmapview.AvcsVehicleLocationSync.LiveVehicle;
import com.sentientsimulations.projectzomboid.avcsmapview.AvcsVehicleLocationSync.Result;
import com.sentientsimulations.projectzomboid.avcsmapview.VehiclesDbLocations.Position;
import com.sentientsimulations.projectzomboid.avcsmapview.VehiclesDbLocations.VerifiedRead;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.junit.jupiter.api.Test;
import se.krka.kahlua.j2se.KahluaTableImpl;
import se.krka.kahlua.vm.KahluaTable;

class AvcsVehicleLocationSyncTest {

    private static final double TS = 1712345678d;
    private static final long NOW = 1_800_000_000L;

    private static double key(int sqlId) {
        return key(TS, sqlId);
    }

    private static double key(double timestamp, int sqlId) {
        return Double.parseDouble(((long) timestamp) + "" + sqlId);
    }

    private static KahluaTable table() {
        return new KahluaTableImpl(new HashMap<>());
    }

    private static KahluaTable claim(KahluaTable db, int sqlId, double x, double y) {
        return claim(db, key(sqlId), x, y);
    }

    private static KahluaTable claim(KahluaTable db, double key, double x, double y) {
        KahluaTable entry = table();
        entry.rawset("OwnerPlayerID", 76561198000000000d);
        entry.rawset("CarModel", "Base.CarNormal");
        entry.rawset("LastLocationX", x);
        entry.rawset("LastLocationY", y);
        entry.rawset("LastLocationUpdateDateTime", TS);
        db.rawset(key, entry);
        return entry;
    }

    private final List<KahluaTable> sent = new ArrayList<>();
    private final List<Collection<Integer>> dbQueries = new ArrayList<>();
    private final List<Map<Integer, Double>> dbExpectedKeys = new ArrayList<>();

    private Result run(
            KahluaTable db, Map<Integer, LiveVehicle> live, Map<Integer, Position> inDb) {
        return run(db, live, inDb, Set.of());
    }

    private Result run(
            KahluaTable db,
            Map<Integer, LiveVehicle> live,
            Map<Integer, Position> inDb,
            Set<Integer> unverifiedInDb) {
        return AvcsVehicleLocationSync.sync(
                db,
                live,
                byKey -> {
                    dbQueries.add(new ArrayList<>(byKey.keySet()));
                    dbExpectedKeys.add(new HashMap<>(byKey));
                    Map<Integer, Position> out = new HashMap<>();
                    Set<Integer> unverified = new HashSet<>();
                    for (int id : byKey.keySet()) {
                        if (unverifiedInDb.contains(id)) {
                            unverified.add(id);
                        } else if (inDb.containsKey(id)) {
                            out.put(id, inDb.get(id));
                        }
                    }
                    return new VerifiedRead(out, unverified);
                },
                AvcsVehicleLocationSyncTest::table,
                sent::add,
                NOW);
    }

    @Test
    void liveVehiclesWinDbFillsTheRestAndOnlyChangesAreBroadcast() {
        KahluaTable db = table();
        KahluaTable loaded = claim(db, 1, 10d, 10d);
        KahluaTable recycledLoaded = claim(db, 2, 20d, 20d);
        KahluaTable unloaded = claim(db, 3, 30d, 30d);
        KahluaTable gone = claim(db, 4, 40d, 40d);
        KahluaTable unchanged = claim(db, 5, 50d, 51d);
        KahluaTable recycledUnclaimed = claim(db, 6, 60d, 60d);
        KahluaTable orphaned = claim(db, 7, 70d, 70d);
        KahluaTable reclaimed = claim(db, key(TS + 100, 7), 71d, 71d);
        KahluaTable recycledUnloaded = claim(db, 8, 80d, 80d);
        db.rawset("garbage", table());
        db.rawset(123d, table());

        Map<Integer, LiveVehicle> live = new HashMap<>();
        live.put(1, new LiveVehicle(key(1), 12.7f, 13.2f));
        // sqlId 2 came back on a car claimed under a different key
        live.put(2, new LiveVehicle(key(99), 1f, 1f));
        // sqlId 6 came back on a never-claimed car: no imprint at all
        live.put(6, new LiveVehicle(null, 61.9f, 62.1f));
        Map<Integer, Position> inDb = new HashMap<>();
        inDb.put(3, new Position(30.5f, 31.9f));
        inDb.put(5, new Position(50.9f, 51.1f));
        inDb.put(7, new Position(77.5f, 78.5f));
        inDb.put(8, new Position(88.5f, 88.5f));

        Result result = run(db, live, inDb, Set.of(8));

        assertEquals(new Result(9, 2, 1, 3, 3, 1, 1, 3), result);
        assertEquals(1, dbQueries.size());
        assertEquals(Set.of(3, 4, 5, 7, 8), new HashSet<>(dbQueries.get(0)));
        // the db is asked to verify each row against the claim's own key
        assertEquals(key(3), dbExpectedKeys.get(0).get(3));
        assertEquals(key(TS + 100, 7), dbExpectedKeys.get(0).get(7));

        assertEquals(12d, loaded.rawget("LastLocationX"));
        assertEquals(13d, loaded.rawget("LastLocationY"));
        assertEquals((double) NOW, loaded.rawget("LastLocationUpdateDateTime"));
        assertEquals(20d, recycledLoaded.rawget("LastLocationX"));
        assertEquals(TS, recycledLoaded.rawget("LastLocationUpdateDateTime"));
        assertEquals(30d, unloaded.rawget("LastLocationX"));
        assertEquals(31d, unloaded.rawget("LastLocationY"));
        assertEquals(40d, gone.rawget("LastLocationX"));
        assertEquals(TS, unchanged.rawget("LastLocationUpdateDateTime"));
        assertEquals(60d, recycledUnclaimed.rawget("LastLocationX"));
        assertEquals(TS, recycledUnclaimed.rawget("LastLocationUpdateDateTime"));
        assertEquals(70d, orphaned.rawget("LastLocationX"));
        assertEquals(77d, reclaimed.rawget("LastLocationX"));
        assertEquals(78d, reclaimed.rawget("LastLocationY"));
        assertEquals(80d, recycledUnloaded.rawget("LastLocationX"));
        assertEquals(TS, recycledUnloaded.rawget("LastLocationUpdateDateTime"));

        assertEquals(1, sent.size());
        KahluaTable batch = sent.get(0);
        assertEquals(3, batch.len());
        assertNull(batch.rawget(4));
        Map<Object, KahluaTable> byVehicle = new HashMap<>();
        for (int i = 1; i <= 3; i++) {
            KahluaTable delta = (KahluaTable) batch.rawget(i);
            byVehicle.put(delta.rawget("VehicleID"), delta);
        }
        assertEquals(12d, byVehicle.get(key(1)).rawget("LastLocationX"));
        assertEquals(31d, byVehicle.get(key(3)).rawget("LastLocationY"));
        assertEquals(77d, byVehicle.get(key(TS + 100, 7)).rawget("LastLocationX"));
    }

    @Test
    void broadcastIsChunked() {
        KahluaTable db = table();
        Map<Integer, LiveVehicle> live = new HashMap<>();
        int count = AvcsVehicleLocationSync.BATCH_SIZE * 2 + 5;
        for (int id = 1; id <= count; id++) {
            claim(db, id, 0d, 0d);
            live.put(id, new LiveVehicle(key(id), id, id));
        }

        Result result = run(db, live, Map.of());

        assertEquals(count, result.changed());
        assertTrue(dbQueries.isEmpty());
        assertEquals(3, sent.size());
        assertEquals(AvcsVehicleLocationSync.BATCH_SIZE, sent.get(0).len());
        assertEquals(AvcsVehicleLocationSync.BATCH_SIZE, sent.get(1).len());
        assertEquals(5, sent.get(2).len());
    }

    @Test
    void nothingToDoSendsNothing() {
        KahluaTable db = table();
        claim(db, 1, 5d, 6d);

        Result result = run(db, Map.of(1, new LiveVehicle(key(1), 5.5f, 6.5f)), Map.of());

        assertEquals(0, result.changed());
        assertTrue(sent.isEmpty());
    }
}
