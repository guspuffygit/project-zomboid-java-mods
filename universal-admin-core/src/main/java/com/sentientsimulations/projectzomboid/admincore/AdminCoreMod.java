package com.sentientsimulations.projectzomboid.admincore;

import io.pzstorm.storm.core.StormClassTransformer;
import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.zomboid.OnZomboidGlobalsLoadEvent;
import io.pzstorm.storm.mod.ZomboidMod;
import io.pzstorm.storm.util.StormEnv;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import zombie.Lua.LuaManager;

public final class AdminCoreMod implements ZomboidMod {
    private static final Logger LOGGER = LoggerFactory.getLogger(AdminCoreMod.class);

    @Override
    public void registerEventHandlers() {
        StormEventDispatcher.registerEventHandler(AdminCoreMod.class);
    }

    @Override
    public List<StormClassTransformer> getClassTransformers() {
        return StormEnv.isStormServer()
                ? List.of(
                        new AdminCoreObserverInterestPatch("zombie.network.PlayerDownloadServer"),
                        new AdminCoreObserverInterestPatch("zombie.network.ServerMap"),
                        new AdminCoreObserverInterestPatch(
                                "zombie.network.packets.character.PlayerPacket"),
                        new AdminCoreObserverInterestPatch("zombie.network.packets.INetworkPacket"),
                        new AdminCoreObserverInterestPatch("zombie.vehicles.VehicleManager"),
                        new AdminCoreObserverInterestPatch("zombie.popman.NetworkZombiePacker"),
                        new AdminCoreObserverInterestPatch(
                                "zombie.popman.animal.AnimalSynchronizationManager"),
                        new AdminCoreObserverReplicationPatch(
                                "io.pzstorm.storm.connection.StormGameEntityBroadcastGate"),
                        new AdminCoreObserverReplicationPatch(
                                "io.pzstorm.storm.connection.StormSyncIsoObjectGate"))
                : List.of(
                        new AdminCoreObservePatch(),
                        new AdminCoreObserveFramePatch(),
                        new AdminCoreObserveRenderPatch(),
                        new AdminCoreObserveVisibilityPatch(),
                        new AdminCoreObserveLightPatch(),
                        new AdminCoreObserveSquarePatch(),
                        new AdminCoreObserveBlackoutPatch(),
                        new AdminCoreObservePlayerPatch(),
                        new AdminCoreObserveStreamingPatch("zombie.iso.IsoChunkMap"),
                        new AdminCoreObserveStreamingPatch("zombie.iso.WorldStreamer"),
                        new AdminCoreObserveStreamingPatch("zombie.iso.IsoCell"),
                        new AdminCoreObserverPanPatch(),
                        new AdminCoreObserveProjectionPatch(),
                        new AdminCoreObserveTerrainPatch("zombie.iso.fboRenderChunk.FBORenderCell"),
                        new AdminCoreObserveTerrainPatch("zombie.iso.IsoCell"),
                        new AdminCoreObserveTerrainPatch("zombie.iso.IsoWater"),
                        new AdminCoreObserveTerrainPatch("zombie.iso.IsoGridSquare"),
                        new AdminCoreObserverWeatherPatch());
    }

    @SubscribeEvent
    public static void expose(OnZomboidGlobalsLoadEvent event) {
        if (!StormEnv.isStormServer()) {
            LuaManager.exposer.setExposed(AdminCoreObserveCamera.class);
            LuaManager.exposer.exposeLikeJavaRecursively(
                    AdminCoreObserveCamera.class, LuaManager.env);
            return;
        }
        LuaManager.exposer.setExposed(AdminCoreBridge.class);
        LuaManager.exposer.exposeLikeJavaRecursively(AdminCoreBridge.class, LuaManager.env);
        LuaManager.exposer.setExposed(AdminCoreObserverBridge.class);
        LuaManager.exposer.exposeLikeJavaRecursively(AdminCoreObserverBridge.class, LuaManager.env);
        LuaManager.exposer.setExposed(AdminCoreObserverInterest.class);
        LuaManager.exposer.exposeLikeJavaRecursively(
                AdminCoreObserverInterest.class, LuaManager.env);
        LuaManager.exposer.setExposed(SafehouseBoundaryBridge.class);
        LuaManager.exposer.exposeLikeJavaRecursively(SafehouseBoundaryBridge.class, LuaManager.env);
        LOGGER.info("[Universal Admin Core] Server bridge exposed.");
    }
}
