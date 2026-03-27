package com.sentientsimulations.projectzomboid.avcs.safehouse;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import java.io.File;
import java.sql.SQLException;
import java.util.List;
import java.util.Map;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.ZomboidFileSystem;
import zombie.characters.IsoPlayer;
import zombie.network.GameServer;

public final class SafehouseAccessBridge {

    static final String MODULE = "AVCSSafehouse";
    private static final String DB_FILENAME = "safehouse_access.db";

    private SafehouseAccessBridge() {}

    static String getDbPath() {
        File dbFile = ZomboidFileSystem.instance.getFileInCurrentSave(DB_FILENAME);
        String path = dbFile.getAbsolutePath();
        LOGGER.info("[AVCSSafehouse] DB path: {}", path);
        return path;
    }

    /**
     * @return null on success, or an error message
     */
    public static String addAccess(String ownerUsername, String allowedUsername) {
        LOGGER.info(
                "[AVCSSafehouse] addAccess called: owner={}, allowed={}",
                ownerUsername,
                allowedUsername);
        if (ownerUsername.equals(allowedUsername)) {
            LOGGER.warn("[AVCSSafehouse] addAccess rejected: owner and allowed are the same user");
            return "Cannot grant access to yourself.";
        }
        try (SafehouseAccessDatabase db = new SafehouseAccessDatabase(getDbPath())) {
            SafehouseAccessRepository repo = new SafehouseAccessRepository(db.getConnection());
            boolean inserted = repo.insertAccess(ownerUsername, allowedUsername);
            if (!inserted) {
                LOGGER.info(
                        "[AVCSSafehouse] addAccess: '{}' already has access to '{}' safehouse",
                        allowedUsername,
                        ownerUsername);
                return "Player '" + allowedUsername + "' already has access.";
            }
            LOGGER.info(
                    "[AVCSSafehouse] addAccess succeeded: '{}' now has access to '{}' safehouse",
                    allowedUsername,
                    ownerUsername);
            return null;
        } catch (SQLException e) {
            LOGGER.error(
                    "[AVCSSafehouse] Failed to add access for '{}' -> '{}'",
                    ownerUsername,
                    allowedUsername,
                    e);
            return "Database error adding access.";
        }
    }

    /**
     * @return null on success, or an error message
     */
    public static String removeAccess(String ownerUsername, String allowedUsername) {
        LOGGER.info(
                "[AVCSSafehouse] removeAccess called: owner={}, allowed={}",
                ownerUsername,
                allowedUsername);
        try (SafehouseAccessDatabase db = new SafehouseAccessDatabase(getDbPath())) {
            SafehouseAccessRepository repo = new SafehouseAccessRepository(db.getConnection());
            boolean deleted = repo.deleteAccess(ownerUsername, allowedUsername);
            if (!deleted) {
                LOGGER.info(
                        "[AVCSSafehouse] removeAccess: '{}' did not have access to '{}' safehouse",
                        allowedUsername,
                        ownerUsername);
                return "Player '" + allowedUsername + "' did not have access.";
            }
            LOGGER.info(
                    "[AVCSSafehouse] removeAccess succeeded: '{}' no longer has access to '{}' safehouse",
                    allowedUsername,
                    ownerUsername);
            return null;
        } catch (SQLException e) {
            LOGGER.error(
                    "[AVCSSafehouse] Failed to remove access for '{}' -> '{}'",
                    ownerUsername,
                    allowedUsername,
                    e);
            return "Database error removing access.";
        }
    }

    /** Broadcast full access data to all connected clients. */
    public static void broadcast() {
        LOGGER.info("[AVCSSafehouse] broadcast() called");
        try {
            KahluaTable args = buildSyncTable();
            GameServer.sendServerCommand(MODULE, "sync", args);
            LOGGER.info("[AVCSSafehouse] broadcast() complete");
        } catch (SQLException e) {
            LOGGER.error("[AVCSSafehouse] Failed to broadcast access data", e);
        }
    }

    /** Send full access data to a single player. */
    static void syncToPlayer(IsoPlayer player) {
        LOGGER.info("[AVCSSafehouse] syncToPlayer() called for {}", player.getUsername());
        try {
            KahluaTable args = buildSyncTable();
            GameServer.sendServerCommand(player, MODULE, "sync", args);
            LOGGER.info("[AVCSSafehouse] syncToPlayer() complete");
        } catch (SQLException e) {
            LOGGER.error("[AVCSSafehouse] Failed to sync access data to player", e);
        }
    }

    /**
     * Build a KahluaTable:
     *
     * <pre>{ access = { [owner] = {player1, player2, ...}, ... } }</pre>
     */
    private static KahluaTable buildSyncTable() throws SQLException {
        try (SafehouseAccessDatabase db = new SafehouseAccessDatabase(getDbPath())) {
            SafehouseAccessRepository repo = new SafehouseAccessRepository(db.getConnection());
            Map<String, List<String>> allAccess = repo.loadAll();

            KahluaTable args = LuaManager.platform.newTable();
            KahluaTable accessTable = LuaManager.platform.newTable();

            for (Map.Entry<String, List<String>> entry : allAccess.entrySet()) {
                KahluaTable playerList = LuaManager.platform.newTable();
                int idx = 1;
                for (String allowed : entry.getValue()) {
                    playerList.rawset(idx++, allowed);
                }
                accessTable.rawset(entry.getKey(), playerList);
            }

            args.rawset("access", accessTable);
            return args;
        }
    }
}
