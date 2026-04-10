package com.sentientsimulations.projectzomboid.survivorleaderboard;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.survivorleaderboard.commands.OnClientAddPlayerCommand;
import com.sentientsimulations.projectzomboid.survivorleaderboard.commands.OnClientDeleteAllEntriesCommand;
import com.sentientsimulations.projectzomboid.survivorleaderboard.commands.OnClientDeleteEntryCommand;
import com.sentientsimulations.projectzomboid.survivorleaderboard.commands.OnClientIncrementCommand;
import com.sentientsimulations.projectzomboid.survivorleaderboard.commands.OnClientRefreshCommand;
import io.pzstorm.storm.event.core.OnClientCommand;
import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.OnServerStartedEvent;
import io.pzstorm.storm.event.lua.OnTickEvent;
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

    @OnClientCommand
    public void onDeleteEntry(OnClientDeleteEntryCommand event) {
        String username = event.getDisplayName();
        LOGGER.info(
                "[Lifeboard] onDeleteEntry from {} targeting displayName={}",
                event.getPlayer().getUsername(),
                username);
        if (username == null) {
            LOGGER.warn("[Lifeboard] deleteEntry missing player.displayName arg");
            return;
        }
        String error = SurvivorLeaderboardBridge.deleteEntry(username);
        if (error != null) {
            LOGGER.warn("[Lifeboard] deleteEntry failed: {}", error);
        }
    }

    @OnClientCommand
    public void onDeleteAllEntries(OnClientDeleteAllEntriesCommand event) {
        LOGGER.info("[Lifeboard] onDeleteAllEntries from {}", event.getPlayer().getUsername());
        String error = SurvivorLeaderboardBridge.deleteAllEntries();
        if (error != null) {
            LOGGER.warn("[Lifeboard] deleteAllEntries failed: {}", error);
        }
    }
}
