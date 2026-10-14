package com.sentientsimulations.projectzomboid.admincore;

import static org.junit.jupiter.api.Assertions.*;

import java.nio.ByteBuffer;
import java.util.List;
import org.junit.jupiter.api.Test;
import zombie.iso.areas.SafeHouse;

class SafehouseBoundaryTest {
    @Test
    void rejectsInvalidStaleDeletedOverlapAndUnsafeExpansion() {
        var house = new SafeHouse(100, 200, 10, 10, "owner");
        var other = new SafeHouse(130, 200, 10, 10, "other");
        SafeHouse.getSafehouseList().addAll(List.of(house, other));
        try {
            String expected = SafehouseBoundaryBridge.fingerprint(house);
            assertEquals(
                    "OK", SafehouseBoundaryBridge.validate(house, expected, 99, 199, 12, 12, true));
            assertNotEquals(
                    "OK",
                    SafehouseBoundaryBridge.validate(house, expected, 101, 200, 10, 10, true));
            assertEquals(
                    "OK",
                    SafehouseBoundaryBridge.validate(house, expected, 101, 200, 10, 10, false));
            assertNotEquals(
                    "OK",
                    SafehouseBoundaryBridge.validate(house, expected, 100, 200, 31, 10, true));
            // Touching the other's edge is allowed, matching native half-open coordinates.
            assertEquals(
                    "OK",
                    SafehouseBoundaryBridge.validate(house, expected, 100, 200, 30, 10, true));
            assertNotEquals(
                    "OK",
                    SafehouseBoundaryBridge.validate(
                            house, expected, Double.NaN, 200, 10, 10, false));
            assertNotEquals(
                    "OK",
                    SafehouseBoundaryBridge.validate(house, expected, 100.1, 200, 10, 10, false));
            assertNotEquals(
                    "OK",
                    SafehouseBoundaryBridge.validate(house, expected, 100, 200, 201, 10, false));
            house.getPlayers().add("new member");
            assertNotEquals(
                    "OK", SafehouseBoundaryBridge.validate(house, expected, 99, 199, 12, 12, true));
            house.getPlayers().remove("new member");
            house.getPlayersRespawn().add("owner");
            assertNotEquals(
                    "OK", SafehouseBoundaryBridge.validate(house, expected, 99, 199, 12, 12, true));
            SafeHouse.getSafehouseList().remove(house);
            assertNotEquals(
                    "OK", SafehouseBoundaryBridge.validate(house, expected, 99, 199, 12, 12, true));
            assertEquals(
                    "Permission denied.",
                    SafehouseBoundaryBridge.apply(null, house, expected, 99, 199, 12, 12, true));
        } finally {
            SafeHouse.getSafehouseList().remove(house);
            SafeHouse.getSafehouseList().remove(other);
        }
    }

    @Test
    void nativeMutationAndSaveLoadPreserveClaimDataWithoutRecreation() {
        var house = new SafeHouse(100, 200, 10, 10, "owner");
        house.getPlayers().add("member");
        house.getPlayersRespawn().add("member");
        house.setDatetimeCreated(123456789L);
        house.setLastVisited(234567890L);
        house.setLocation("Riverside");
        house.setTitle("Original property");
        house.setHitPoints(125);
        var id = house.getId();
        var players = house.getPlayers();
        var respawns = house.getPlayersRespawn();
        SafehouseBoundaryBridge.applyRectangle(house, 95, 195, 20, 20);
        assertEquals(id, house.getId());
        assertSame(players, house.getPlayers());
        assertSame(respawns, house.getPlayersRespawn());
        assertEquals(SafeHouse.getOnlineID(95, 195), house.getOnlineID());
        var bytes = ByteBuffer.allocate(8192);
        house.save(bytes);
        bytes.flip();
        SafeHouse loaded = SafeHouse.load(bytes, 223);
        try {
            assertEquals(95, loaded.getX());
            assertEquals(195, loaded.getY());
            assertEquals(20, loaded.getW());
            assertEquals(20, loaded.getH());
            assertEquals(house.getOwner(), loaded.getOwner());
            assertEquals(players, loaded.getPlayers());
            assertEquals(respawns, loaded.getPlayersRespawn());
            assertEquals(house.getDatetimeCreated(), loaded.getDatetimeCreated());
            assertEquals(house.getLastVisited(), loaded.getLastVisited());
            assertEquals(house.getLocation(), loaded.getLocation());
            assertEquals(house.getTitle(), loaded.getTitle());
            assertEquals(house.getHitPoints(), loaded.getHitPoints());
            assertEquals(house.getOnlineID(), loaded.getOnlineID());
        } finally {
            SafeHouse.getSafehouseList().remove(loaded);
        }
    }
}
