package com.sentientsimulations.projectzomboid.extralogging.containerhistory;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.OnClientCommand;
import java.util.List;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;
import zombie.network.GameServer;

public final class QueryContainerHistoryHandler {

    private static final String MODULE = "ExtraLogging";
    private static final String REPLY_COMMAND = "containerHistory";
    private static final int DEFAULT_LIMIT = 200;
    private static final int MAX_LIMIT = 1000;

    private QueryContainerHistoryHandler() {}

    @OnClientCommand
    public static void onQuery(QueryContainerHistoryCommand event) {
        IsoPlayer player = event.getPlayer();
        if (player == null || !player.isAccessLevel("admin")) {
            String username = player == null ? "<null>" : player.getUsername();
            String steamId = player == null ? "?" : Long.toString(player.getSteamID());
            String role = "?";
            if (player != null) {
                role = player.getRole() == null ? "none" : player.getRole().getName();
            }
            LOGGER.warn(
                    "[StormAntiCheat] connection {}/{} sent queryContainerHistory while role={};"
                            + " the History button is gated to admins on the client, so a non-admin"
                            + " reaching this handler is running a hacked client or crafting"
                            + " client commands directly; dropping query for ref={}",
                    username,
                    steamId,
                    role,
                    event.getContainerRef());
            return;
        }

        String ref = event.getContainerRef();
        if (ref == null || ref.isBlank()) {
            LOGGER.warn("queryContainerHistory: missing ref from {}", player.getUsername());
            return;
        }

        Integer requested = event.getLimit();
        int limit = requested == null ? DEFAULT_LIMIT : Math.min(Math.max(requested, 1), MAX_LIMIT);

        ContainerHistoryWriter.flush();
        List<ContainerTransferRecord> rows =
                ContainerHistoryRepository.queryByContainerRef(ref, limit);

        KahluaTable reply = LuaManager.platform.newTable();
        reply.rawset("ref", ref);

        KahluaTable rowsTable = LuaManager.platform.newTable();
        int i = 1;
        for (ContainerTransferRecord r : rows) {
            KahluaTable rowTable = LuaManager.platform.newTable();
            rowTable.rawset("id", (double) r.id());
            rowTable.rawset("ts", (double) r.ts());
            rowTable.rawset("player", r.playerUsername());
            if (r.playerSteamId() != null) {
                rowTable.rawset("steamId", r.playerSteamId());
            }
            rowTable.rawset("itemType", r.itemType());
            rowTable.rawset("itemName", r.itemName());
            rowTable.rawset("itemId", (double) r.itemId());
            rowTable.rawset("srcRef", r.srcRef());
            rowTable.rawset("destRef", r.destRef());
            rowTable.rawset("uuid", r.uuid());
            rowsTable.rawset(i++, rowTable);
        }
        reply.rawset("rows", rowsTable);
        reply.rawset("count", (double) rows.size());

        GameServer.sendServerCommand(event.getPlayer(), MODULE, REPLY_COMMAND, reply);
    }
}
