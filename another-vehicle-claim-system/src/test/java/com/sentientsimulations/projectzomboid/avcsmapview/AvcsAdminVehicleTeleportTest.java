package com.sentientsimulations.projectzomboid.avcsmapview;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.sentientsimulations.projectzomboid.avcsmapview.AvcsAdminVehicleTeleport.Job;
import com.sentientsimulations.projectzomboid.avcsmapview.AvcsAdminVehicleTeleport.Reason;
import com.sentientsimulations.projectzomboid.avcsmapview.AvcsAdminVehicleTeleport.Target;
import java.util.HashMap;
import org.junit.jupiter.api.Test;
import se.krka.kahlua.j2se.KahluaTableImpl;
import se.krka.kahlua.vm.KahluaTable;

class AvcsAdminVehicleTeleportTest {

    private static KahluaTable table() {
        return new KahluaTableImpl(new HashMap<>());
    }

    @Test
    void offsetDefaultsAndClamps() {
        assertEquals(2, AvcsAdminVehicleTeleport.clampOffset(null));
        assertEquals(2, AvcsAdminVehicleTeleport.clampOffset(Double.NaN));
        assertEquals(1, AvcsAdminVehicleTeleport.clampOffset(1.0));
        assertEquals(2, AvcsAdminVehicleTeleport.clampOffset(2.0));
        assertEquals(2, AvcsAdminVehicleTeleport.clampOffset(900.0));
        assertEquals(-2, AvcsAdminVehicleTeleport.clampOffset(-7.0));
        assertEquals(0, AvcsAdminVehicleTeleport.clampOffset(0.4));
    }

    @Test
    void targetIsAdminTilePlusOffsetAtTileCenter() {
        Target t = AvcsAdminVehicleTeleport.targetFor(13431.7f, 2522.1f, 1.0, 2.0);
        assertEquals(13432, t.x());
        assertEquals(2524, t.y());
        assertEquals(13432.5f, t.centerX());
        assertEquals(2524.5f, t.centerY());

        Target spoofed = AvcsAdminVehicleTeleport.targetFor(100f, 100f, 5000.0, -5000.0);
        assertEquals(102, spoofed.x());
        assertEquals(98, spoofed.y());
    }

    @Test
    void chunkOfUsesEightTileChunksIncludingNegatives() {
        assertEquals(0, AvcsAdminVehicleTeleport.chunkOf(7.9f));
        assertEquals(1, AvcsAdminVehicleTeleport.chunkOf(8.0f));
        assertEquals(1678, AvcsAdminVehicleTeleport.chunkOf(13431.5f));
        assertEquals(315, AvcsAdminVehicleTeleport.chunkOf(2521.5f));
        assertEquals(-1, AvcsAdminVehicleTeleport.chunkOf(-0.5f));
    }

    @Test
    void onlyAdminRolePasses() {
        assertTrue(AvcsAdminVehicleTeleport.isAdminRole("admin"));
        assertTrue(AvcsAdminVehicleTeleport.isAdminRole("Admin"));
        assertFalse(AvcsAdminVehicleTeleport.isAdminRole("moderator"));
        assertFalse(AvcsAdminVehicleTeleport.isAdminRole("none"));
        assertFalse(AvcsAdminVehicleTeleport.isAdminRole(null));
    }

    @Test
    void commandReadsClaimKeyAndOffsets() {
        KahluaTable args = table();
        args.rawset("VehicleID", 17123456785859d);
        args.rawset("OffsetX", 1.0);
        args.rawset("OffsetY", 2.0);
        AdminTeleportVehicleCommand cmd = new AdminTeleportVehicleCommand(null, args);
        assertEquals(17123456785859d, cmd.getVehicleId());
        assertEquals(1.0, cmd.getOffsetX());
        assertEquals(2.0, cmd.getOffsetY());
        assertEquals(5859, AvcsClaimKey.sqlIdFromClaimKey(cmd.getVehicleId()));

        AdminTeleportVehicleCommand empty = new AdminTeleportVehicleCommand(null, table());
        assertNull(empty.getVehicleId());
        assertNull(empty.getOffsetX());
        assertEquals(AvcsClaimKey.INVALID, AvcsClaimKey.sqlIdFromClaimKey(empty.getVehicleId()));
    }

    @Test
    void resultTableCarriesOutcome() {
        KahluaTable moved =
                AvcsAdminVehicleTeleport.resultTable(
                        table(), 17123456785859d, Reason.moved, new Target(10, 20));
        assertEquals(Boolean.TRUE, moved.rawget("ok"));
        assertEquals("moved", moved.rawget("reason"));
        assertEquals(17123456785859d, moved.rawget("VehicleID"));
        assertEquals(10d, moved.rawget("X"));
        assertEquals(20d, moved.rawget("Y"));

        KahluaTable refused =
                AvcsAdminVehicleTeleport.resultTable(table(), null, Reason.notAdmin, null);
        assertEquals(Boolean.FALSE, refused.rawget("ok"));
        assertEquals("notAdmin", refused.rawget("reason"));
        assertNull(refused.rawget("VehicleID"));
        assertNull(refused.rawget("X"));
    }

    @Test
    void jobExpiresAtDeadline() {
        Job job = new Job(5859, 17123456785859d, null, "admin", new Target(1, 1), 1678, 315, 1000L);
        assertFalse(job.expired(999L));
        assertTrue(job.expired(1000L));
        assertTrue(job.expired(5000L));
    }
}
