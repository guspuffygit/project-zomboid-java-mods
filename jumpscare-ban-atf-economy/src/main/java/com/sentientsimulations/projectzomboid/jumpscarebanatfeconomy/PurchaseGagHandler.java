package com.sentientsimulations.projectzomboid.jumpscarebanatfeconomy;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.OnClientCommand;
import org.jetbrains.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;
import zombie.network.GameServer;
import zombie.network.chat.ChatServer;

/**
 * Handles the {@code JumpscareBanEconomy:purchaseGag} client command: charges the buyer the
 * sandbox-configured Scraps price through the economy mod, and on success triggers the same global
 * broadcast the matching jumpscare-ban admin command performs when run with no username argument.
 *
 * <p>Client commands are dispatched from {@code mainLoopDealWithNetData}, so this runs on the
 * server main loop — the only place {@code ChatServer} broadcasts are safe.
 */
public final class PurchaseGagHandler {

    private static final String MODULE = "JumpscareBanEconomy";
    private static final String RESULT_COMMAND = "purchaseResult";
    private static final String CURRENCY = "Scraps";
    private static final String INVALID_GAG = "INVALID_GAG";
    private static final String DISABLED = "DISABLED";
    private static final String DEDUCT_REASON_PREFIX = "jumpscare_gag_";

    private static final String COMMISSION_USERNAME = "Gus Puffy";
    private static final long COMMISSION_STEAM_ID = 76561197984809068L;
    private static final double COMMISSION_PCT = 0.20;
    private static final String COMMISSION_REASON_PREFIX = "jumpscare_gag_commission_";

    private PurchaseGagHandler() {}

    @OnClientCommand
    public static void onPurchaseGag(PurchaseGagCommand event) {
        IsoPlayer player = event.getPlayer();
        if (player == null) {
            LOGGER.warn("[JumpscareBanEconomy] purchaseGag from null player; dropping");
            return;
        }
        // Clients hide the shop button when disabled, so a request arriving here means a stale
        // client or a hand-crafted packet — never trust the client's view of the switch.
        if (!JumpscareBanEconomyConfig.isEnabled()) {
            LOGGER.info(
                    "[JumpscareBanEconomy] purchaseGag from {} while the mod is disabled; dropping",
                    player.getUsername());
            sendResult(player, event.getGagId(), false, DISABLED, 0);
            return;
        }
        JumpscareGag gag = JumpscareGag.fromId(event.getGagId());
        if (gag == null) {
            LOGGER.warn(
                    "[JumpscareBanEconomy] purchaseGag from {} with unknown gag \"{}\"",
                    player.getUsername(),
                    event.getGagId());
            sendResult(player, event.getGagId(), false, INVALID_GAG, 0);
            return;
        }

        // Price comes from the server's sandbox options — the client's displayed price is never
        // trusted. A price of 0 means free: deduct() rejects amount <= 0 as INVALID_AMOUNT.
        int price = JumpscareBanEconomyConfig.getPrice(gag);
        if (price > 0) {
            AtfEconomyBridge.DeductResult result =
                    AtfEconomyBridge.deduct(
                            player, CURRENCY, price, DEDUCT_REASON_PREFIX + gag.getId());
            if (!result.ok()) {
                LOGGER.info(
                        "[JumpscareBanEconomy] {} failed to purchase {} for {} {}: {}",
                        player.getUsername(),
                        gag.getId(),
                        price,
                        CURRENCY,
                        result.reason());
                sendResult(player, gag.getId(), false, result.reason(), price);
                return;
            }
            payCommission(player, gag, price);
        }

        playGlobal(gag);
        announceRedemption(player, gag, price);
        LOGGER.info(
                "[JumpscareBanEconomy] {} purchased global {} for {} {}",
                player.getUsername(),
                gag.getId(),
                price,
                CURRENCY);
        sendResult(player, gag.getId(), true, null, price);
    }

    /**
     * Plain server chat line, matching how Storm's low-RAM nag talks to players. {@code
     * sendServerAlertMessageToServerChat} is deliberately not used — alerts render bold red and are
     * mirrored to an on-screen banner, which is too loud for a purchase receipt.
     */
    private static void announceRedemption(IsoPlayer player, JumpscareGag gag, int price) {
        if (!ChatServer.isInited()) {
            return;
        }
        ChatServer.getInstance()
                .sendMessageToServerChat(
                        String.format(
                                "%s redeemed %s for %d %s",
                                player.getUsername(), gag.getId(), price, CURRENCY));
    }

    /**
     * Pays a 20% cut of the purchase price to Gus Puffy's economy account. The purchase has already
     * succeeded by the time this runs, so a failed commission is logged but never surfaced to the
     * buyer or refunded.
     */
    private static void payCommission(IsoPlayer buyer, JumpscareGag gag, int price) {
        int commission = (int) Math.floor(price * COMMISSION_PCT);
        if (commission <= 0) {
            return;
        }
        AtfEconomyBridge.GrantResult result =
                AtfEconomyBridge.grant(
                        COMMISSION_USERNAME,
                        COMMISSION_STEAM_ID,
                        CURRENCY,
                        commission,
                        COMMISSION_REASON_PREFIX + gag.getId());
        if (result.ok()) {
            LOGGER.info(
                    "[JumpscareBanEconomy] paid {} a {} {} commission on {}'s {} purchase",
                    COMMISSION_USERNAME,
                    commission,
                    CURRENCY,
                    buyer.getUsername(),
                    gag.getId());
        } else {
            LOGGER.warn(
                    "[JumpscareBanEconomy] commission of {} {} to {} failed on {}'s {} purchase: {}",
                    commission,
                    CURRENCY,
                    COMMISSION_USERNAME,
                    buyer.getUsername(),
                    gag.getId(),
                    result.reason());
        }
    }

    /** Mirrors the no-username branch of jumpscare-ban's /fart, /cry and /kachow commands. */
    private static void playGlobal(JumpscareGag gag) {
        ChatServer.getInstance().sendServerAlertMessageToServerChat(gag.getChatAlert());
        GameServer.sendServerCommand(JumpscareGag.JUMPSCARE_BAN_MODULE, gag.getPlayCommand(), null);
    }

    private static void sendResult(
            IsoPlayer player,
            @Nullable String gagId,
            boolean ok,
            @Nullable String reason,
            int price) {
        KahluaTable args = LuaManager.platform.newTable();
        args.rawset("ok", ok);
        args.rawset("gag", gagId == null ? "" : gagId);
        args.rawset("price", (double) price);
        if (reason != null) {
            args.rawset("reason", reason);
        }
        GameServer.sendServerCommand(player, MODULE, RESULT_COMMAND, args);
    }
}
