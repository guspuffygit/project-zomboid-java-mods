package com.sentientsimulations.projectzomboid.avcsmapview;

import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.Lua.LuaManager;
import zombie.core.physics.Transform;
import zombie.core.physics.WorldSimulation;
import zombie.network.GameClient;
import zombie.vehicles.BaseVehicle;

/** Client half of the server-approved AVCS relocation notification. */
public final class AvcsVehicleSync {
    private static Number identity(BaseVehicle vehicle) {
        // New claims carry identity through native part ModData, including clients
        // which did not have the vehicle loaded when the Lua hint was broadcast.
        for (int i = 0; i < vehicle.getPartCount(); i++) {
            Object value = vehicle.getPartByIndex(i).getModData().rawget("AVCSIdentity");
            if (value instanceof Number key) return key;
        }
        Object value = vehicle.getModData().rawget("SQLID");
        return value instanceof Number key ? key : null;
    }

    @LuaMethod
    public static boolean apply(int id, double claim, double x, double y, double physicsY) {
        if (!GameClient.client || !Double.isFinite(claim + x + y + physicsY)) return false;
        BaseVehicle vehicle = LuaManager.GlobalObject.getVehicleById(id);
        if (vehicle == null) return false;
        Number key = identity(vehicle);
        if (key == null || Double.compare(key.doubleValue(), claim) != 0) return false;
        for (int seat = 0; seat < vehicle.getMaxPassengers(); seat++)
            if (vehicle.getCharacter(seat) != null) return true;
        vehicle.netPlayerFromServerUpdate(BaseVehicle.Authorization.Server, (short) -1);
        if (vehicle.interpolation != null) vehicle.interpolation.reset();
        vehicle.jniLinearVelocity.set(0f, 0f, 0f);
        Transform transform = BaseVehicle.allocTransform();
        try {
            vehicle.getWorldTransform(transform);
            transform.origin.set(
                    (float) x - WorldSimulation.instance.offsetX,
                    (float) physicsY,
                    (float) y - WorldSimulation.instance.offsetY);
            vehicle.setWorldTransform(transform);
        } finally {
            BaseVehicle.releaseTransform(transform);
        }
        vehicle.setX((float) x);
        vehicle.setY((float) y);
        vehicle.setZ(0f);
        vehicle.polyDirty = true;
        return true;
    }
}
