package com.sentientsimulations.projectzomboid.extralogging.containerhistory;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.OnClientCommand;
import java.util.List;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.network.GameServer;

public final class QueryContainerHistoryHandler {

    private static final String MODULE = "ExtraLogging";
    private static final String REPLY_COMMAND = "containerHistory";
    private static final int DEFAULT_LIMIT = 200;
    private static final int MAX_LIMIT = 1000;

    private QueryContainerHistoryHandler() {}

    @OnClientCommand
    public static void onQuery(QueryContainerHistoryCommand event) {
        String ref = event.getContainerRef();
        if (ref == null || ref.isBlank()) {
            LOGGER.warn(
                    "queryContainerHistory: missing ref from {}", event.getPlayer().getUsername());
            return;
        }

        Integer requested = event.getLimit();
        int limit = requested == null ? DEFAULT_LIMIT : Math.min(Math.max(requested, 1), MAX_LIMIT);

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
