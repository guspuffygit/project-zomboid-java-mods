package com.sentientsimulations.projectzomboid.survivorleaderboard;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.survivorleaderboard.commands.OnClientAddPlayerCommand;
import com.sentientsimulations.projectzomboid.survivorleaderboard.commands.OnClientIncrementCommand;
import com.sentientsimulations.projectzomboid.survivorleaderboard.commands.OnClientRefreshCommand;
import io.pzstorm.storm.event.core.OnClientCommand;
import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.EveryHoursEvent;
import io.pzstorm.storm.event.lua.OnPlayerDeathEvent;
import io.pzstorm.storm.event.lua.OnServerStartedEvent;
import io.pzstorm.storm.event.lua.OnTickEvent;
import io.pzstorm.storm.event.zomboid.OnBanSteamIDEvent;
import io.pzstorm.storm.mod.ZomboidMod;
import io.pzstorm.storm.util.StormEnv;
import java.sql.SQLException;
import java.util.List;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.network.GameClient;

public class SurvivorLeaderboardMod implements ZomboidMod {

    private boolean hasPruned = false;

    @Override
    public void registerEventHandlers() {
        LOGGER.info(
                "[Lifeboard] Registering event handlers for {}",
                SurvivorLeaderboardMod.class.getCanonicalName());
        StormEventDispatcher.registerEventHandler(this);
        StormEventDispatcher.registerEventHandler(SurvivorLeaderboardBridge.class);
        StormEventDispatcher.registerEventHandler(SurvivorLeaderboardEndpoints.class);
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
            SurvivorLeaderboardBridge.deleteBySteamIdAsync(steamId);
        } catch (NumberFormatException e) {
            LOGGER.error("[Lifeboard] Invalid SteamID format: {}", event.getSteamID(), e);
        }
    }

    /**
     * Record PvP kills and reset the victim's kill count whenever a player dies. Mirrors the
     * attacker-attribution pattern used in the extra-logging mod's DeathEventHandler.
     */
    @SubscribeEvent
    public void onPlayerDeath(OnPlayerDeathEvent event) {
        if (GameClient.client) {
            return;
        }
        IsoPlayer victim = event.player;
        IsoGameCharacter attacker = victim.getAttackedBy();
        if (attacker instanceof IsoPlayer killer && killer != victim) {
            // areAllies touches Faction/SafeHouse state, so it must run here on the game thread.
            boolean isAlly = SurvivorLeaderboardBridge.areAllies(killer, victim);
            SurvivorLeaderboardBridge.recordPlayerKillAsync(killer, victim, isAlly);
        } else {
            SurvivorLeaderboardBridge.resetKillsForPlayerAsync(victim);
        }
    }

    /**
     * Sweep the kill log for un-decided ally kills and repeat-victim kills, applying delayed
     * penalties for each. Fires once per in-game hour. The two checks are independent — a kill can
     * trigger both penalties.
     */
    @SubscribeEvent
    public void onEveryHours(EveryHoursEvent event) {
        // The same jar loads on the client JVM, where this Lua event also fires — without the gate
        // a client would spawn the worker and write a bogus local DB.
        if (!StormEnv.isStormServer()) {
            return;
        }
        SurvivorLeaderboardBridge.processPenaltySweepsAsync();
    }

    /** Prune banned survivors on the first tick, once ServerWorldDatabase is fully ready. */
    @SubscribeEvent
    public void onTick(OnTickEvent event) {
        if (hasPruned || GameClient.client) {
            return;
        }
        hasPruned = true;
        SurvivorLeaderboardBridge.pruneBannedSurvivorsAsync();
    }

    @OnClientCommand
    public void onAddPlayer(OnClientAddPlayerCommand event) {
        LOGGER.info(
                "[Lifeboard] onAddPlayer from {} (steamId={})",
                event.getPlayer().getUsername(),
                event.getPlayer().getSteamID());
        SurvivorLeaderboardBridge.addPlayerAsync(event.getPlayer());
    }

    /** Sent by the client when the leaderboard window is opened; replies only to the requester. */
    @OnClientCommand
    public void onRefresh(OnClientRefreshCommand event) {
        LOGGER.info("[Lifeboard] onRefresh from {}", event.getPlayer().getUsername());
        SurvivorLeaderboardBridge.requestBoardAsync(event.getPlayer());
    }

    @OnClientCommand
    public void onIncrement(OnClientIncrementCommand event) {
        Double daysSurvived = event.getDaysSurvived();
        Double zombieKills = event.getZombieKills();
        if (daysSurvived == null) {
            LOGGER.warn("[Lifeboard] increment missing daysSurvived arg");
            return;
        }
        int zombieKillsInt = zombieKills != null ? zombieKills.intValue() : 0;
        SurvivorLeaderboardBridge.incrementDaysAsync(
                event.getPlayer(), daysSurvived.intValue(), zombieKillsInt);
    }
}
