package com.sentientsimulations.projectzomboid.admincore;

import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertSame;

import org.junit.jupiter.api.Test;
import zombie.iso.areas.SafeHouse;

class SafehouseLookupTest {
    @Test
    void resolvesNetworkBoundsAcrossDuplicateTitlesAndRejectsDeletedClaims() {
        var first = new SafeHouse(100, 200, 10, 10, "owner-one");
        var second = new SafeHouse(300, 400, 10, 10, "owner-two");
        var houses = SafeHouse.getSafehouseList();
        houses.add(first);
        houses.add(second);
        try {
            // Both real game objects have the default title "Safehouse".
            assertNull(SafeHouse.getSafeHouse(second.getId()));
            assertSame(second, AdminCoreBridge.safehouseByKey("300,400,10,10"));
            assertSame(first, AdminCoreBridge.safehouseByKey("100,200,10,10"));
            second.setTitle("Renamed home");
            assertSame(second, AdminCoreBridge.safehouseByKey("300,400,10,10"));
            assertNull(AdminCoreBridge.safehouseByKey(second.getTitle()));
            assertNull(AdminCoreBridge.safehouseByKey(second.getId()));
            assertNull(AdminCoreBridge.safehouseByKey("300,400,11,10"));
            assertNull(AdminCoreBridge.safehouseByKey("300,400,10,11"));
            houses.remove(second);
            assertNull(AdminCoreBridge.safehouseByKey("300,400,10,10"));
            assertNull(AdminCoreBridge.safehouseByKey(null));
            assertNull(AdminCoreBridge.safehouseByKey(""));
        } finally {
            houses.remove(first);
            houses.remove(second);
        }
    }
}
