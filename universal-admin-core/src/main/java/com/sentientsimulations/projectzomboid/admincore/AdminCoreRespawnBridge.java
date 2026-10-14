package com.sentientsimulations.projectzomboid.admincore;

import se.krka.kahlua.integration.annotations.LuaMethod;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaEventManager;
import zombie.Lua.LuaManager;
import zombie.core.network.ByteBufferReader;
import zombie.core.raknet.UdpConnection;
import zombie.iso.IsoWorld;
import zombie.network.GameClient;
import zombie.network.PacketTypes;
import zombie.network.TableNetworkUtils;

/** Pre-character transport. Authentication and all spawn coordinates remain server-owned. */
public final class AdminCoreRespawnBridge {
    private static UdpConnection owner;
    private static final Choice[] CHOICES = new Choice[4];
    private static final String[] EXPECTED = new String[4];
    private static boolean negotiated;

    record Choice(String region, int x, int y, int z) {}

    private AdminCoreRespawnBridge() {}

    @LuaMethod
    public static boolean requestChoices(int playerIndex, String requestId) {
        return send("choices", playerIndex, requestId, null, 0);
    }

    @LuaMethod
    public static boolean requestMoreChoices(int playerIndex, String requestId, int offset) {
        return offset >= 0 && send("choices", playerIndex, requestId, null, offset);
    }

    @LuaMethod
    public static boolean choose(int playerIndex, String houseId, String requestId) {
        return send("choose", playerIndex, requestId, houseId, 0);
    }

    @LuaMethod
    public static boolean cancel(int playerIndex) {
        if (playerIndex >= 0 && playerIndex < 4) {
            CHOICES[playerIndex] = null;
            EXPECTED[playerIndex] = null;
        }
        return send("cancel", playerIndex, "cancel", null, 0);
    }

    private static boolean send(
            String command, int slot, String requestId, String house, int offset) {
        if (!GameClient.client
                || GameClient.connection == null
                || slot < 0
                || slot > 3
                || requestId == null
                || requestId.length() > 80) return false;
        if (owner != GameClient.connection) {
            owner = GameClient.connection;
            negotiated = false;
            java.util.Arrays.fill(CHOICES, null);
            java.util.Arrays.fill(EXPECTED, null);
        }
        EXPECTED[slot] = command.equals("cancel") ? null : requestId;
        KahluaTable args = LuaManager.platform.newTable();
        args.rawset("playerIndex", (double) slot);
        args.rawset("requestId", requestId);
        if (house != null) args.rawset("houseId", house);
        if (command.equals("choices")) args.rawset("offset", (double) offset);
        GameClient.instance.sendClientCommand(null, AdminCoreRespawnServer.MODULE, command, args);
        return true;
    }

    /** A narrow loading handler: no other module is dispatched while game loading. */
    public static boolean loading(PacketTypes.PacketType type, ByteBufferReader reader) {
        return type == PacketTypes.PacketType.ClientCommand && response(reader, true);
    }

    public static boolean response(ByteBufferReader reader, boolean dispatch) {
        ByteBufferReader copy = new ByteBufferReader(reader.bb.duplicate());
        boolean ours = false;
        try {
            ours = AdminCoreRespawnServer.MODULE.equals(copy.getUTF());
            if (!ours) return false;
            String command = copy.getUTF();
            if (!command.equals("choices")
                    && !command.equals("selected")
                    && !command.equals("rejected")) return true;
            KahluaTable args = LuaManager.platform.newTable();
            if (copy.getBoolean()) TableNetworkUtils.load(args, copy);
            Object index = args.rawget("playerIndex");
            if (!(index instanceof Double value)
                    || value < 0
                    || value > 3
                    || value != Math.floor(value)) return true;
            int slot = value.intValue();
            if (owner != GameClient.connection) {
                owner = GameClient.connection;
                negotiated = false;
                java.util.Arrays.fill(CHOICES, null);
                java.util.Arrays.fill(EXPECTED, null);
            }
            boolean lateRejection =
                    command.equals("rejected") && Boolean.TRUE.equals(args.rawget("creation"));
            boolean current =
                    EXPECTED[slot] != null && EXPECTED[slot].equals(args.rawget("requestId"));
            if (!current && !lateRejection) return true;
            if (command.equals("choices")) negotiated = Boolean.TRUE.equals(args.rawget("enabled"));
            if (command.equals("selected")) {
                String region = (String) args.rawget("regionKey");
                if (region == null || !region.startsWith(AdminCoreRespawnServer.PREFIX))
                    return true;
                CHOICES[slot] =
                        new Choice(
                                region,
                                ((Double) args.rawget("x")).intValue(),
                                ((Double) args.rawget("y")).intValue(),
                                ((Double) args.rawget("z")).intValue());
            }
            if (command.equals("rejected")) {
                CHOICES[slot] = null;
                EXPECTED[slot] = null;
            }
            if (dispatch)
                LuaEventManager.triggerEvent(
                        "OnServerCommand", AdminCoreRespawnServer.MODULE, command, args);
        } catch (Exception ignored) {
            // Foreign/malformed loading traffic never gains a general Lua command dispatch path.
        }
        return ours;
    }

    /** Used only for native IsoWorld.init's reads of the SpawnPoint setting. */
    public static String spawnPoint(String original) {
        if (!GameClient.client || owner != GameClient.connection || IsoWorld.instance == null)
            return original;
        String region = IsoWorld.instance.getSpawnRegion();
        for (Choice choice : CHOICES)
            if (choice != null && choice.region().equals(region))
                return choice.x() + "," + choice.y() + "," + choice.z();
        return original;
    }

    public static String spawnPointOption(Object option, String original) {
        return option == zombie.network.ServerOptions.instance.spawnPoint
                ? spawnPoint(original)
                : original;
    }

    public static boolean legacyPreference(boolean original) {
        return GameClient.client && owner == GameClient.connection && negotiated ? false : original;
    }
}
