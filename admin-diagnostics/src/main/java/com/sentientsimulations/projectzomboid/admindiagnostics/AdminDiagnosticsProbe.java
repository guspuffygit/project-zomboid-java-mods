package com.sentientsimulations.projectzomboid.admindiagnostics;

import java.lang.management.GarbageCollectorMXBean;
import java.lang.management.ManagementFactory;
import java.util.List;
import se.krka.kahlua.integration.annotations.LuaMethod;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.iso.IsoChunkMap;
import zombie.network.GameClient;
import zombie.ui.UIManager;

public final class AdminDiagnosticsProbe {
    private static final List<GarbageCollectorMXBean> COLLECTORS =
            ManagementFactory.getGarbageCollectorMXBeans();

    private AdminDiagnosticsProbe() {}

    @LuaMethod
    public static KahluaTable snapshot() {
        if (!GameClient.client) return null;
        var values = LuaManager.platform.newTable();
        Runtime runtime = Runtime.getRuntime();
        values.rawset("heapUsedMiB", (runtime.totalMemory() - runtime.freeMemory()) / 1048576.0);
        values.rawset("heapCommittedMiB", runtime.totalMemory() / 1048576.0);
        values.rawset("heapMaxMiB", runtime.maxMemory() / 1048576.0);
        long count = 0, millis = 0;
        for (var collector : COLLECTORS) {
            count += Math.max(0, collector.getCollectionCount());
            millis += Math.max(0, collector.getCollectionTime());
        }
        values.rawset("gcCount", (double) count);
        values.rawset("gcMillis", (double) millis);
        values.rawset("sharedChunks", (double) IsoChunkMap.SharedChunks.size());
        values.rawset("uiGlobalVisible", UIManager.visibleAllUi);
        if (GameClient.connection != null) {
            values.rawset("pingMs", (double) GameClient.connection.getLastPing());
            values.rawset("fullyConnected", GameClient.connection.isFullyConnected());
        }
        return values;
    }
}
