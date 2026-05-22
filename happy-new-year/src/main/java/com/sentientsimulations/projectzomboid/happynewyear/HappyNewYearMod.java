package com.sentientsimulations.projectzomboid.happynewyear;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.EveryDaysEvent;
import io.pzstorm.storm.mod.ZomboidMod;
import io.pzstorm.storm.util.StormEnv;
import zombie.GameTime;
import zombie.network.GameClient;
import zombie.network.chat.ChatServer;

public class HappyNewYearMod implements ZomboidMod {

    @Override
    public void registerEventHandlers() {
        if (!StormEnv.isStormServer()) {
            return;
        }
        LOGGER.info("[HappyNewYear] Registering event handlers");
        StormEventDispatcher.registerEventHandler(this);
    }

    @SubscribeEvent
    public void onEveryDays(EveryDaysEvent event) {
        if (GameClient.client) {
            return;
        }
        GameTime time = GameTime.getInstance();
        if (time.getMonth() != 0 || time.getDay() != 0) {
            return;
        }
        int year = time.getYear();
        String message = "Happy New Year!!! Welcome to " + year;
        LOGGER.info("[HappyNewYear] Broadcasting: {}", message);
        ChatServer.getInstance().sendServerAlertMessageToServerChat(message);
    }
}
