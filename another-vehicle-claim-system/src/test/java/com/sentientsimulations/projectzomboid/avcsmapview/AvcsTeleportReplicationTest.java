package com.sentientsimulations.projectzomboid.avcsmapview;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.util.TreeSet;
import org.joml.Quaternionf;
import org.joml.Vector3f;
import org.junit.jupiter.api.Test;
import sun.misc.Unsafe;
import zombie.GameTime;
import zombie.core.physics.Transform;
import zombie.core.physics.WorldSimulation;
import zombie.network.GameServer;
import zombie.vehicles.BaseVehicle;
import zombie.vehicles.VehicleInterpolation;
import zombie.vehicles.VehicleInterpolationData;
import zombie.vehicles.VehicleParts;

class AvcsTeleportReplicationTest {

    private static final class Position extends VehicleInterpolationData {
        long timestamp() {
            return time;
        }
    }

    @Test
    void repeatedTeleportsEmitFreshNativePositionsAfterDrivingUpdates() throws Exception {
        boolean wasServer = GameServer.server;
        boolean wasCreated = WorldSimulation.instance.created;
        long previousClock = WorldSimulation.instance.time;
        try {
            GameServer.server = true;
            WorldSimulation.instance.created = false;
            BaseVehicle vehicle = vehicleFixture();
            for (float destination : new float[] {80, 160}) {
                vehicle.setX(10);
                WorldSimulation.instance.time = GameTime.getServerTimeMills() - 5000;
                Position priorDrivingUpdate = new Position();
                priorDrivingUpdate.set(vehicle);

                // The dedicated test server has no Bullet world; calling its update does not
                // advance this clock. Exercise that engine behavior and the actual AVCS producer.
                WorldSimulation.instance.time = 0;
                WorldSimulation.instance.update();
                assertEquals(0, WorldSimulation.instance.time);
                vehicle.setX(destination);
                vehicle.updateFlags = BaseVehicle.UpdateFlags.Full;
                AvcsAdminVehicleTeleport.queuePositionUpdate(vehicle);

                Position teleportUpdate = new Position();
                teleportUpdate.set(vehicle);
                assertTrue(teleportUpdate.timestamp() > priorDrivingUpdate.timestamp());
                assertTrue(
                        (vehicle.updateFlags & BaseVehicle.UpdateFlags.PositionOrientation) != 0);
                assertTrue((vehicle.updateFlags & BaseVehicle.UpdateFlags.Full) != 0);

                VehicleInterpolation interpolation =
                        nativeInterpolation(priorDrivingUpdate, teleportUpdate);
                float[] position = new float[27];
                assertTrue(
                        interpolation.interpolationDataGet(
                                position, new float[2], teleportUpdate.timestamp() + 100, null));
                assertEquals(destination, position[0]);
            }
        } finally {
            WorldSimulation.instance.time = previousClock;
            WorldSimulation.instance.created = wasCreated;
            GameServer.server = wasServer;
        }
    }

    private static BaseVehicle vehicleFixture() throws Exception {
        // Allocate a vehicle without starting a game world. Serialization and interpolation below
        // are the installed engine implementations; neither method is mocked or overridden.
        Field unsafeField = Unsafe.class.getDeclaredField("theUnsafe");
        unsafeField.setAccessible(true);
        Unsafe unsafe = (Unsafe) unsafeField.get(null);
        BaseVehicle vehicle = (BaseVehicle) unsafe.allocateInstance(BaseVehicle.class);
        field(BaseVehicle.class, vehicle, "savedRot", new Quaternionf());
        field(BaseVehicle.class, vehicle, "jniTransform", new Transform());
        field(BaseVehicle.class, vehicle, "jniLinearVelocity", new Vector3f());
        field(BaseVehicle.class, vehicle, "wheelInfo", new BaseVehicle.WheelInfo[0]);
        field(BaseVehicle.class, vehicle, "parts", new VehicleParts());
        return vehicle;
    }

    private static VehicleInterpolation nativeInterpolation(Position prior, Position target)
            throws Exception {
        Constructor<VehicleInterpolation> constructor =
                VehicleInterpolation.class.getDeclaredConstructor();
        constructor.setAccessible(true);
        VehicleInterpolation interpolation = constructor.newInstance();
        Field buffer = VehicleInterpolation.class.getDeclaredField("buffer");
        buffer.setAccessible(true);
        @SuppressWarnings("unchecked")
        TreeSet<VehicleInterpolationData> points =
                (TreeSet<VehicleInterpolationData>) buffer.get(interpolation);
        points.add(prior);
        points.add(target);
        field(VehicleInterpolation.class, interpolation, "buffering", false);
        return interpolation;
    }

    private static void field(Class<?> type, Object object, String name, Object value)
            throws Exception {
        Field field = type.getDeclaredField(name);
        field.setAccessible(true);
        field.set(object, value);
    }
}
