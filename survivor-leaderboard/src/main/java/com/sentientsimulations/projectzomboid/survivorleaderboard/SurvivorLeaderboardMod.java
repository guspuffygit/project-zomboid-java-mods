package com.sentientsimulations.projectzomboid.survivorleaderboard;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.survivorleaderboard.commands.OnClientAddPlayerCommand;
import com.sentientsimulations.projectzomboid.survivorleaderboard.commands.OnClientIncrementCommand;
import com.sentientsimulations.projectzomboid.survivorleaderboard.commands.OnClientRefreshCommand;
import io.pzstorm.storm.event.core.OnClientCommand;
import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.OnServerStartedEvent;
import io.pzstorm.storm.event.lua.OnTickEvent;
import io.pzstorm.storm.event.zomboid.OnBanSteamIDEvent;
import io.pzstorm.storm.mod.ZomboidMod;
import java.sql.SQLException;
import java.util.List;

public class SurvivorLeaderboardMod implements ZomboidMod {

    private boolean hasPruned = false;

    @Override
    public void registerEventHandlers() {
        LOGGER.info(
                "[Lifeboard] Registering event handlers for {}",
                SurvivorLeaderboardMod.class.getCanonicalName());
        StormEventDispatcher.registerEventHandler(this);
        LOGGER.info("[Lifeboard] Event handlers registered successfully");
    }

    @Override
    public List<Class<?>> getCommandClasses() {
        return List.of();
    }

    @SubscribeEvent
    public void onServerStarted(OnServerStartedEvent event) {
        LOGGER.info(
                "[Lifeboard] onServerStarted fired, initializing DB at {}",
                SurvivorLeaderboardBridge.getDbPath());
        try (SurvivorLeaderboardDatabase db =
                new SurvivorLeaderboardDatabase(SurvivorLeaderboardBridge.getDbPath())) {
            LOGGER.info("[Lifeboard] Database initialized successfully");
        } catch (SQLException e) {
            LOGGER.error("[Lifeboard] Failed to initialize database", e);
        }
    }

    /** Remove leaderboard entries for a Steam ID immediately when it is banned. */
    @SubscribeEvent
    public void onBanSteamID(OnBanSteamIDEvent event) {
        if (!event.isBan()) {
            return;
        }
        LOGGER.info("[Lifeboard] SteamID {} banned, removing from leaderboard", event.getSteamID());
        try {
            long steamId = Long.parseLong(event.getSteamID());
            String error = SurvivorLeaderboardBridge.deleteBySteamId(steamId);
            if (error != null) {
                LOGGER.warn("[Lifeboard] Failed to remove banned SteamID: {}", error);
            }
        } catch (NumberFormatException e) {
            LOGGER.error("[Lifeboard] Invalid SteamID format: {}", event.getSteamID(), e);
        }
    }

    /** Prune banned survivors on the first tick, once ServerWorldDatabase is fully ready. */
    @SubscribeEvent
    public void onTick(OnTickEvent event) {
        if (hasPruned) {
            return;
        }
        hasPruned = true;
        SurvivorLeaderboardBridge.pruneBannedSurvivors();
    }

    @OnClientCommand
    public void onAddPlayer(OnClientAddPlayerCommand event) {
        LOGGER.info(
                "[Lifeboard] onAddPlayer from {} (steamId={})",
                event.getPlayer().getUsername(),
                event.getPlayer().getSteamID());
        String error = SurvivorLeaderboardBridge.addPlayer(event.getPlayer());
        if (error != null) {
            LOGGER.warn("[Lifeboard] addPlayer failed: {}", error);
        }
    }

    @OnClientCommand
    public void onRefresh(OnClientRefreshCommand event) {
        LOGGER.info("[Lifeboard] onRefresh from {}", event.getPlayer().getUsername());
        String error = SurvivorLeaderboardBridge.refresh(event.getPlayer());
        if (error != null) {
            LOGGER.warn("[Lifeboard] refresh failed: {}", error);
        }
    }

    @OnClientCommand
    public void onIncrement(OnClientIncrementCommand event) {
        Double daysSurvived = event.getDaysSurvived();
        LOGGER.info(
                "[Lifeboard] onIncrement from {} daysSurvived={}",
                event.getPlayer().getUsername(),
                daysSurvived);
        if (daysSurvived == null) {
            LOGGER.warn("[Lifeboard] increment missing daysSurvived arg");
            return;
        }
        String error =
                SurvivorLeaderboardBridge.incrementDays(event.getPlayer(), daysSurvived.intValue());
        if (error != null) {
            LOGGER.warn("[Lifeboard] increment failed: {}", error);
        }
    }
}
