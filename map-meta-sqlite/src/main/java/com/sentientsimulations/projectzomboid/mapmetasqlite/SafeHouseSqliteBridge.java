package com.sentientsimulations.projectzomboid.mapmetasqlite;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import java.io.File;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;
import zombie.ZomboidFileSystem;
import zombie.iso.areas.SafeHouse;
import zombie.network.chat.ChatServer;

public class SafeHouseSqliteBridge {

    private static final String DB_FILENAME = "map_meta.db";

    public static void onSave() {
        try {
            File dbFile = ZomboidFileSystem.instance.getFileInCurrentSave(DB_FILENAME);
            try (SafeHouseDatabase db = new SafeHouseDatabase(dbFile.getAbsolutePath())) {
                SafeHouseRepository repo = new SafeHouseRepository(db.getConnection());
                List<SafeHouseRecord> records = toRecords(SafeHouse.getSafehouseList());
                repo.saveAll(records);
                LOGGER.info("Saved {} safehouses to SQLite", records.size());
            }
        } catch (SQLException e) {
            LOGGER.error("Failed to save safehouses to SQLite", e);
        }
    }

    public static void onLoad() {
        try {
            File dbFile = ZomboidFileSystem.instance.getFileInCurrentSave(DB_FILENAME);
            if (!dbFile.exists()) {
                LOGGER.info("No {} found, using vanilla safehouse data", DB_FILENAME);
                return;
            }

            try (SafeHouseDatabase db = new SafeHouseDatabase(dbFile.getAbsolutePath())) {
                SafeHouseRepository repo = new SafeHouseRepository(db.getConnection());
                List<SafeHouseRecord> records = repo.loadAll();

                if (records.isEmpty()) {
                    LOGGER.info("SQLite DB exists but has no safehouses, using vanilla data");
                    return;
                }

                SafeHouse.clearSafehouseList();

                for (SafeHouseRecord record : records) {
                    SafeHouse sh =
                            new SafeHouse(
                                    record.x(), record.y(), record.w(), record.h(), record.owner());

                    sh.setHitPoints(record.hitPoints());
                    sh.setLastVisited(record.lastVisited());
                    sh.setTitle(record.title());
                    sh.setDatetimeCreated(record.datetimeCreated());
                    sh.setLocation(record.location());

                    for (String player : record.players()) {
                        sh.addPlayer(player);
                    }

                    for (String player : record.playersRespawn()) {
                        sh.setRespawnInSafehouse(true, player);
                    }

                    SafeHouse.getSafehouseList().add(sh);

                    if (ChatServer.isInited()) {
                        ChatServer.getInstance().createSafehouseChat(sh.getId());
                    }
                }

                LOGGER.info("Loaded {} safehouses from SQLite", records.size());
            }
        } catch (SQLException e) {
            LOGGER.error("Failed to load safehouses from SQLite, using vanilla data", e);
        }
    }

    static List<SafeHouseRecord> toRecords(List<SafeHouse> safehouses) {
        List<SafeHouseRecord> records = new ArrayList<>(safehouses.size());
        for (SafeHouse sh : safehouses) {
            records.add(
                    new SafeHouseRecord(
                            sh.getX(),
                            sh.getY(),
                            sh.getW(),
                            sh.getH(),
                            sh.getOwner(),
                            sh.getHitPoints(),
                            new ArrayList<>(sh.getPlayers()),
                            sh.getLastVisited(),
                            sh.getTitle(),
                            sh.getDatetimeCreated(),
                            sh.getLocation(),
                            new ArrayList<>(sh.getPlayersRespawn())));
        }
        return records;
    }
}
