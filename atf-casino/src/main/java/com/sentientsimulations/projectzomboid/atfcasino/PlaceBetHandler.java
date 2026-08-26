package com.sentientsimulations.projectzomboid.atfcasino;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.OnClientCommand;
import org.jetbrains.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;
import zombie.network.GameServer;

/**
 * Handles the {@code AtfCasino:placeBet} client command: validates the wager against the server's
 * sandbox options, takes the stake through the economy mod, resolves the game and pays out.
 *
 * <p>Client commands are dispatched from {@code mainLoopDealWithNetData}, so this runs on the
 * server main loop — the only place economy and chat calls are safe.
 */
public final class PlaceBetHandler {

    private static final String MODULE = "AtfCasino";
    private static final String RESULT_COMMAND = "betResult";
    private static final String CURRENCY = "Scraps";

    private static final String DISABLED = "DISABLED";
    private static final String INVALID_GAME = "INVALID_GAME";
    private static final String GAME_DISABLED = "GAME_DISABLED";
    private static final String WAGER_TOO_LOW = "WAGER_TOO_LOW";
    private static final String WAGER_TOO_HIGH = "WAGER_TOO_HIGH";

    private static final String STAKE_REASON_PREFIX = "casino_stake_";
    private static final String PAYOUT_REASON_PREFIX = "casino_payout_";

    private PlaceBetHandler() {}

    @OnClientCommand
    public static void onPlaceBet(PlaceBetCommand event) {
        IsoPlayer player = event.getPlayer();
        if (player == null) {
            LOGGER.warn("[AtfCasino] placeBet from null player; dropping");
            return;
        }
        if (!AtfCasinoConfig.isEnabled()) {
            sendResult(player, event.getGameId(), false, DISABLED, 0, 0, null);
            return;
        }
        CasinoGame game = CasinoGame.fromId(event.getGameId());
        if (game == null || game.isTableGame()) {
            LOGGER.warn(
                    "[AtfCasino] placeBet from {} with unknown game \"{}\"",
                    player.getUsername(),
                    event.getGameId());
            sendResult(player, event.getGameId(), false, INVALID_GAME, 0, 0, null);
            return;
        }
        if (!AtfCasinoConfig.isGameEnabled(game)) {
            sendResult(player, game.getId(), false, GAME_DISABLED, 0, 0, null);
            return;
        }

        int wager = event.getWager();
        if (wager < AtfCasinoConfig.getMinBet()) {
            sendResult(player, game.getId(), false, WAGER_TOO_LOW, wager, 0, null);
            return;
        }
        if (wager > AtfCasinoConfig.getMaxBet()) {
            sendResult(player, game.getId(), false, WAGER_TOO_HIGH, wager, 0, null);
            return;
        }

        AtfEconomyBridge.DeductResult stake =
                AtfEconomyBridge.deduct(
                        player, CURRENCY, wager, STAKE_REASON_PREFIX + game.getId());
        if (!stake.ok()) {
            LOGGER.info(
                    "[AtfCasino] {} failed to stake {} {} on {}: {}",
                    player.getUsername(),
                    wager,
                    CURRENCY,
                    game.getId(),
                    stake.reason());
            sendResult(player, game.getId(), false, stake.reason(), wager, 0, null);
            return;
        }

        BetOutcome outcome = resolve(game, event.getSelection(), wager);
        if (outcome.isWin()) {
            payOut(player, game, outcome.payout());
        }
        LOGGER.info(
                "[AtfCasino] {} wagered {} {} on {} ({}) -> {} paying {}",
                player.getUsername(),
                wager,
                CURRENCY,
                game.getId(),
                event.getSelection(),
                outcome.resultId(),
                outcome.payout());
        sendResult(player, game.getId(), true, null, wager, outcome.payout(), outcome.resultId());
    }

    /**
     * Resolves one wager. The stake is already taken by the time this runs, so the return value is
     * the gross payout. Unreachable while every registered game is a table game.
     */
    private static BetOutcome resolve(CasinoGame game, @Nullable String selection, int wager) {
        throw new IllegalStateException("no casino game implements resolve() yet: " + game);
    }

    /**
     * Grants go through the bridge's username + steamId path rather than the player object so the
     * payout still lands if the player disconnects between the stake and the resolution.
     */
    private static void payOut(IsoPlayer player, CasinoGame game, int payout) {
        AtfEconomyBridge.GrantResult result =
                AtfEconomyBridge.grant(
                        player.getUsername(),
                        player.getSteamID(),
                        CURRENCY,
                        payout,
                        PAYOUT_REASON_PREFIX + game.getId());
        if (!result.ok()) {
            LOGGER.error(
                    "[AtfCasino] payout of {} {} to {} on {} FAILED: {}",
                    payout,
                    CURRENCY,
                    player.getUsername(),
                    game.getId(),
                    result.reason());
        }
    }

    private static void sendResult(
            IsoPlayer player,
            @Nullable String gameId,
            boolean ok,
            @Nullable String reason,
            int wager,
            int payout,
            @Nullable String resultId) {
        KahluaTable args = LuaManager.platform.newTable();
        args.rawset("ok", ok);
        args.rawset("game", gameId == null ? "" : gameId);
        args.rawset("wager", (double) wager);
        args.rawset("payout", (double) payout);
        if (resultId != null) {
            args.rawset("result", resultId);
        }
        if (reason != null) {
            args.rawset("reason", reason);
        }
        GameServer.sendServerCommand(player, MODULE, RESULT_COMMAND, args);
    }
}
