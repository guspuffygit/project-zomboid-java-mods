package com.sentientsimulations.projectzomboid.survivorleaderboard;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.survivorleaderboard.commands.OnClientAddPlayerCommand;
import com.sentientsimulations.projectzomboid.survivorleaderboard.commands.OnClientIncrementCommand;
import com.sentientsimulations.projectzomboid.survivorleaderboard.commands.OnClientRefreshCommand;
import io.pzstorm.storm.event.core.OnClientCommand;
import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.EveryHoursEvent;
import io.pzstorm.storm.event.lua.OnCharacterDeathEvent;
import io.pzstorm.storm.event.lua.OnServerStartedEvent;
import io.pzstorm.storm.event.lua.OnTickEvent;
import io.pzstorm.storm.event.zomboid.OnBanSteamIDEvent;
import io.pzstorm.storm.mod.ZomboidMod;
import java.sql.SQLException;
import java.util.List;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;

public class SurvivorLeaderboardMod implements ZomboidMod {

    private boolean hasPruned = false;

    @Override
    public void registerEventHandlers() {
        LOGGER.info(
                "[Lifeboard] Registering event handlers for {}",
                SurvivorLeaderboardMod.class.getCanonicalName());
        StormEventDispatcher.registerEventHandler(this);
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
            String error = SurvivorLeaderboardBridge.deleteBySteamId(steamId);
            if (error != null) {
                LOGGER.warn("[Lifeboard] Failed to remove banned SteamID: {}", error);
            }
        } catch (NumberFormatException e) {
            LOGGER.error("[Lifeboard] Invalid SteamID format: {}", event.getSteamID(), e);
        }
    }

    /**
     * Record PvP kills and reset the victim's kill count whenever a player dies. Mirrors the
     * attacker-attribution pattern used in the extra-logging mod's DeathEventHandler.
     */
    @SubscribeEvent
    public void onCharacterDeath(OnCharacterDeathEvent event) {
        if (!(event.character instanceof IsoPlayer victim)) {
            return;
        }
        IsoGameCharacter attacker = victim.getAttackedBy();
        if (attacker instanceof IsoPlayer killer && killer != victim) {
            boolean isAlly = SurvivorLeaderboardBridge.areAllies(killer, victim);
            String error = SurvivorLeaderboardBridge.recordPlayerKill(killer, victim, isAlly);
            if (error != null) {
                LOGGER.warn("[Lifeboard] recordPlayerKill failed: {}", error);
            }
        } else {
            String error = SurvivorLeaderboardBridge.resetKillsForPlayer(victim);
            if (error != null) {
                LOGGER.warn("[Lifeboard] resetKillsForPlayer failed: {}", error);
            }
        }
    }

    /**
     * Sweep the kill log for un-decided ally kills and apply delayed penalties. Fires once per
     * in-game hour.
     */
    @SubscribeEvent
    public void onEveryHours(EveryHoursEvent event) {
        SurvivorLeaderboardBridge.processAllyKillPenalties();
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
        Double zombieKills = event.getZombieKills();
        LOGGER.info(
                "[Lifeboard] onIncrement from {} daysSurvived={} zombieKills={}",
                event.getPlayer().getUsername(),
                daysSurvived,
                zombieKills);
        if (daysSurvived == null) {
            LOGGER.warn("[Lifeboard] increment missing daysSurvived arg");
            return;
        }
        int zombieKillsInt = zombieKills != null ? zombieKills.intValue() : 0;
        String error =
                SurvivorLeaderboardBridge.incrementDays(
                        event.getPlayer(), daysSurvived.intValue(), zombieKillsInt);
        if (error != null) {
            LOGGER.warn("[Lifeboard] increment failed: {}", error);
        }
    }
}
