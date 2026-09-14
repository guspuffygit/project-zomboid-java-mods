package com.sentientsimulations.projectzomboid.guspuffyatfpatches;

import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.zomboid.OnZomboidGlobalsLoadEvent;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.Lua.LuaManager;
import zombie.iso.areas.SafeHouse;
import zombie.network.GameServer;
import zombie.network.PacketTypes;
import zombie.network.chat.ChatServer;
import zombie.network.packets.INetworkPacket;

/** Server-side completion for ATF's direct offline-safehouse creation path. */
public final class ATFSafehouseNativeSync {
    private ATFSafehouseNativeSync() {}

    @SubscribeEvent
    public static void expose(OnZomboidGlobalsLoadEvent event) {
        LuaManager.exposer.setExposed(ATFSafehouseNativeSync.class);
        LuaManager.exposer.exposeLikeJavaRecursively(ATFSafehouseNativeSync.class, LuaManager.env);
    }

    @LuaMethod
    public static void sync(SafeHouse house) {
        if (!GameServer.server || house == null || !SafeHouse.getSafehouseList().contains(house))
            return;
        ChatServer.getInstance().createSafehouseChat(house.getId());
        INetworkPacket.sendToAll(PacketTypes.PacketType.SafehouseSync, house);
        ChatServer.getInstance()
                .syncSafehouseChatMembers(house.getId(), house.getOwner(), house.getPlayers());
    }
}
