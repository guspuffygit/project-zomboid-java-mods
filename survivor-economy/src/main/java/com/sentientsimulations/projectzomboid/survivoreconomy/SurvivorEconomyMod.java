package com.sentientsimulations.projectzomboid.survivoreconomy;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.EveryHoursEvent;
import io.pzstorm.storm.event.lua.OnClientCommandEvent;
import io.pzstorm.storm.event.lua.OnServerStartedEvent;
import io.pzstorm.storm.event.lua.OnZombieDeadEvent;
import io.pzstorm.storm.mod.ZomboidMod;
import java.sql.SQLException;
import java.util.List;
import org.jspecify.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.network.GameClient;
import zombie.network.GameServer;

public class SurvivorEconomyMod implements ZomboidMod {
    @Override
    public void registerEventHandlers() {
        LOGGER.info(
                "[SurvivorEconomy] Registering event handlers for {}",
                SurvivorEconomyMod.class.getCanonicalName());
        StormEventDispatcher.registerEventHandler(this);
        StormEventDispatcher.registerEventHandler(SurvivorEconomyEndpoints.class);
        StormEventDispatcher.registerEventHandler(DiscordLinkEndpoints.class);
        LOGGER.info("[SurvivorEconomy] Event handlers registered successfully");
    }

    @Override
    public List<Class<?>> getCommandClasses() {
        return List.of();
    }

    @SubscribeEvent
    public void onServerStarted(OnServerStartedEvent event) {
        LOGGER.info(
                "[SurvivorEconomy] onServerStarted fired, initializing DB at {}",
                SurvivorEconomyBridge.getDbPath());
        try (SurvivorEconomyDatabase db =
                new SurvivorEconomyDatabase(SurvivorEconomyBridge.getDbPath())) {
            LOGGER.info("[SurvivorEconomy] Database initialized successfully");
        } catch (SQLException e) {
            LOGGER.error("[SurvivorEconomy] Failed to initialize database", e);
        }
    }

    /**
     * Server-side hourly tick — Storm mirror of Lua {@code Events.EveryHours.Add}. Iterates online
     * players and runs a paycheck clock-in for each.
     */
    @SubscribeEvent
    public void onEveryHours(EveryHoursEvent event) {
        if (GameClient.client) {
            return;
        }
        for (IsoPlayer player : GameServer.Players) {
            if (player == null) {
                continue;
            }
            SurvivorEconomyBridge.processClockIn(player);
        }
    }

    /**
     * Server-side handler for client→server commands. Today only {@code requestBalance} is
     * recognized — sent by {@code SurvivorEconomyClient.lua} on the first valid tick after connect
     * — and answers with a {@code balanceUpdated} push so the client can populate its cache without
     * waiting for the next economy event.
     */
    @SubscribeEvent
    public void onClientCommand(OnClientCommandEvent event) {
        if (GameClient.client) {
            return;
        }
        if (!SurvivorEconomyBridge.MODULE.equals(event.getModule())) {
            return;
        }
        IsoPlayer player = event.getPlayer();
        if (player == null) {
            return;
        }
        String command = event.getCommand();
        if (CMD_REQUEST_BALANCE.equals(command)) {
            SurvivorEconomyBridge.pushBalanceUpdated(player);
            return;
        }
        if (CMD_TRANSFER_TO_PLAYER.equals(command)) {
            handleTransferToPlayer(player, event.getArgs().orElse(null));
            return;
        }
        if (CMD_CLAIM_DISCORD_WALLET.equals(command)) {
            handleClaimDiscordWallet(player, event.getArgs().orElse(null));
        }
    }

    private static void handleTransferToPlayer(IsoPlayer sender, KahluaTable args) {
        if (args == null) {
            return;
        }
        Object usernameObj = args.rawget("targetUsername");
        Object steamIdObj = args.rawget("targetSteamId");
        Object currencyObj = args.rawget("currency");
        Object amountObj = args.rawget("amount");
        if (!(usernameObj instanceof String targetUsername)
                || !(currencyObj instanceof String currency)) {
            return;
        }
        Long targetSteamId = readLong(steamIdObj);
        Double amount = readDouble(amountObj);
        if (targetSteamId == null || amount == null) {
            return;
        }
        SurvivorEconomyBridge.processTransfer(
                sender, targetUsername, targetSteamId, currency, amount);
    }

    private static void handleClaimDiscordWallet(IsoPlayer claimer, KahluaTable args) {
        if (args == null) {
            return;
        }
        Object discordIdObj = args.rawget("fromDiscordId");
        Object currencyObj = args.rawget("currency");
        Object amountObj = args.rawget("amount");
        if (!(discordIdObj instanceof String fromDiscordId)
                || !(currencyObj instanceof String currency)) {
            return;
        }
        Double amount = readDouble(amountObj);
        if (amount == null) {
            return;
        }
        SurvivorEconomyBridge.claimDiscordWallet(claimer, fromDiscordId, currency, amount);
    }

    private static @Nullable Long readLong(Object value) {
        if (value instanceof Number n) {
            return n.longValue();
        }
        if (value instanceof String s) {
            try {
                return Long.parseLong(s);
            } catch (NumberFormatException ignored) {
                return null;
            }
        }
        return null;
    }

    private static @Nullable Double readDouble(Object value) {
        if (value instanceof Number n) {
            return n.doubleValue();
        }
        if (value instanceof String s) {
            try {
                return Double.parseDouble(s);
            } catch (NumberFormatException ignored) {
                return null;
            }
        }
        return null;
    }

    static final String CMD_REQUEST_BALANCE = "requestBalance";
    static final String CMD_TRANSFER_TO_PLAYER = "transferToPlayer";
    static final String CMD_CLAIM_DISCORD_WALLET = "claimDiscordWallet";

    /**
     * Server-side zombie-kill hook — Storm mirror of Lua {@code Events.OnZombieDead.Add}, with
     * attribution server-authoritative: the killer is read from {@link
     * IsoGameCharacter#getAttackedBy()} on the dead zombie. Non-player kills (fire, ambient,
     * unattributed) fall through, as do vehicle-seated kills.
     */
    @SubscribeEvent
    public void onZombieDead(OnZombieDeadEvent event) {
        if (GameClient.client) {
            return;
        }
        IsoGameCharacter zombie = event.zombie;
        if (zombie == null) {
            return;
        }
        IsoGameCharacter attacker = zombie.getAttackedBy();
        if (!(attacker instanceof IsoPlayer player)) {
            return;
        }
        if (player.isSeatedInVehicle()) {
            return;
        }
        SurvivorEconomyBridge.processZombieKill(player);
    }
}
