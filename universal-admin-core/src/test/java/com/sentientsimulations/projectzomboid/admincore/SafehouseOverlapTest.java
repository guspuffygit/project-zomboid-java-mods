package com.sentientsimulations.projectzomboid.admincore;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertSame;

import org.junit.jupiter.api.Test;
import zombie.iso.areas.SafeHouse;

class SafehouseOverlapTest {
    @Test
    void nativeBoundsDetectContainmentAndCrossingWithoutBlockingAdjacentClaims() {
        var house = new SafeHouse(100, 200, 10, 10, "owner");
        var houses = SafeHouse.getSafehouseList();
        houses.add(house);
        try {
            assertEquals(110, house.getX2());
            assertEquals(210, house.getY2());
            assertSame(house, SafeHouse.getSafehouseOverlapping(102, 202, 104, 204));
            assertSame(house, SafeHouse.getSafehouseOverlapping(90, 190, 120, 220));
            assertSame(house, SafeHouse.getSafehouseOverlapping(90, 204, 120, 206));
            assertSame(house, SafeHouse.getSafehouseOverlapping(109, 209, 111, 211));
            assertNull(SafeHouse.getSafehouseOverlapping(110, 200, 120, 210));
            assertNull(SafeHouse.getSafehouseOverlapping(90, 200, 100, 210));
            assertNull(SafeHouse.getSafehouseOverlapping(100, 210, 110, 220));
            assertNull(SafeHouse.getSafehouseOverlapping(110, 210, 120, 220));
        } finally {
            houses.remove(house);
        }
    }

    @Test
    void threeTileBorderIsSeparateFromActualOverlap() {
        var house = new SafeHouse(112, 202, 2, 2, "owner");
        var houses = SafeHouse.getSafehouseList();
        houses.add(house);
        try {
            // Selected tiles are x=100..109, y=200..209. Border adds three tiles.
            assertNull(SafeHouse.getSafehouseOverlapping(100, 200, 110, 210));
            assertSame(house, SafeHouse.getSafehouseOverlapping(97, 197, 113, 213));
            houses.remove(house);
            house = new SafeHouse(113, 202, 2, 2, "owner");
            houses.add(house);
            assertNull(SafeHouse.getSafehouseOverlapping(97, 197, 113, 213));
        } finally {
            houses.remove(house);
        }
    }
}
