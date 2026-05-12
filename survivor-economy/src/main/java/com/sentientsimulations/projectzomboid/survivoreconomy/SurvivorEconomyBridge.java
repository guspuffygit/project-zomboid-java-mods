package com.sentientsimulations.projectzomboid.survivoreconomy;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.survivoreconomy.records.BountyResult;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.DiscordAccount;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.DiscordLink;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.DiscordLinkClaimResult;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.DiscordLinkCode;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.SqlExecutionResponse;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.TransactionDraft;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.TransactionEntry;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.TransferFailureReason;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.TransferResult;
import java.io.File;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ThreadLocalRandom;
import org.jspecify.annotations.Nullable;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.ZomboidFileSystem;
import zombie.characters.IsoPlayer;
import zombie.network.GameServer;

public final class SurvivorEconomyBridge {

    static final String MODULE = "SurvivorEconomy";
    private static final String DB_FILENAME = "survivor_economy.db";

    private SurvivorEconomyBridge() {}

    static String getDbPath() {
        File dbFile = ZomboidFileSystem.instance.getFileInCurrentSave(DB_FILENAME);
        String path = dbFile.getAbsolutePath();
        LOGGER.info("[SurvivorEconomy] DB path: {}", path);
        return path;
    }

    /**
     * Record a one-sided event (admin grant, withdraw, deposit, system income, money loss). The row
     * insert and the matching {@code economy_balance} delta commit together in one SQL transaction.
     * On success, pushes the new balances to the affected player if they are online. Returns the
     * generated event id, or null on database error.
     */
    public static @Nullable String recordSole(TransactionDraft draft) {
        try (SurvivorEconomyDatabase db = new SurvivorEconomyDatabase(getDbPath())) {
            SurvivorEconomyRepository repo = new SurvivorEconomyRepository(db.getConnection());
            String eventId = repo.insertSole(draft);
            LOGGER.info(
                    "[SurvivorEconomy] Recorded SOLE event {} type={} player={} amount={} {}",
                    eventId,
                    draft.type(),
                    draft.playerUsername(),
                    draft.amount(),
                    draft.currency());
            pushBalanceUpdatedToOnlinePlayer(
                    db.getConnection(), draft.playerUsername(), draft.playerSteamId());
            return eventId;
        } catch (SQLException e) {
            LOGGER.error(
                    "[SurvivorEconomy] Failed to record SOLE event type={} player={}",
                    draft.type(),
                    draft.playerUsername(),
                    e);
            return null;
        }
    }

    /**
     * Record a two-sided event (transfer, fee, tax, vending purchase). Both transaction rows and
     * both {@code economy_balance} deltas commit together in one SQL transaction. On success,
     * pushes the new balances to whichever of FROM / TO is online. Returns the event id, or null on
     * database error.
     */
    public static @Nullable String recordPair(TransactionDraft from, TransactionDraft to) {
        try (SurvivorEconomyDatabase db = new SurvivorEconomyDatabase(getDbPath())) {
            SurvivorEconomyRepository repo = new SurvivorEconomyRepository(db.getConnection());
            String eventId = repo.insertPair(from, to);
            LOGGER.info(
                    "[SurvivorEconomy] Recorded PAIR event {} type={} from={} to={} amount={} {}",
                    eventId,
                    from.type(),
                    from.playerUsername(),
                    to.playerUsername(),
                    to.amount(),
                    to.currency());
            pushBalanceUpdatedToOnlinePlayer(
                    db.getConnection(), from.playerUsername(), from.playerSteamId());
            pushBalanceUpdatedToOnlinePlayer(
                    db.getConnection(), to.playerUsername(), to.playerSteamId());
            return eventId;
        } catch (SQLException e) {
            LOGGER.error(
                    "[SurvivorEconomy] Failed to record PAIR event type={} from={} to={}",
                    from.type(),
                    from.playerUsername(),
                    to.playerUsername(),
                    e);
            return null;
        }
    }

    public static List<TransactionEntry> listTransactions(
            int limit, @Nullable String username, @Nullable Long steamId, @Nullable String type) {
        try (SurvivorEconomyDatabase db = new SurvivorEconomyDatabase(getDbPath())) {
            SurvivorEconomyRepository repo = new SurvivorEconomyRepository(db.getConnection());
            return repo.loadRecent(limit, username, steamId, type);
        } catch (SQLException e) {
            LOGGER.error("[SurvivorEconomy] Failed to list transactions", e);
            return List.of();
        }
    }

    public static List<TransactionEntry> loadEvent(String eventId) {
        try (SurvivorEconomyDatabase db = new SurvivorEconomyDatabase(getDbPath())) {
            SurvivorEconomyRepository repo = new SurvivorEconomyRepository(db.getConnection());
            return repo.loadByEventId(eventId);
        } catch (SQLException e) {
            LOGGER.error("[SurvivorEconomy] Failed to load event {}", eventId, e);
            return List.of();
        }
    }

    static final String CMD_PAYCHECK_PAID = "paycheckPaid";

    /**
     * Run one paycheck clock-in tick for a player. Bumps online_hours; when the threshold is
     * reached, inserts a PAYCHECK row, decrements hours, and pushes a {@code paycheckPaid}
     * server→client command to {@code player} so the client can pop a halo / chat message. Returns
     * the paycheck event id if one was issued, or null otherwise.
     */
    public static @Nullable String processClockIn(IsoPlayer player) {
        if (player == null) {
            return null;
        }
        String username = player.getUsername();
        if (username == null) {
            return null;
        }
        long steamId = player.getSteamID();
        boolean issuePaychecks = SurvivorEconomyConfig.issuePaychecks();
        int hoursUntilPaycheck = SurvivorEconomyConfig.hoursUntilPaycheck();
        int paycheckValue = SurvivorEconomyConfig.paycheckValue();
        try (SurvivorEconomyDatabase db = new SurvivorEconomyDatabase(getDbPath())) {
            SurvivorEconomyRepository txRepo = new SurvivorEconomyRepository(db.getConnection());
            SurvivorEconomyPlayerStateRepository stateRepo =
                    new SurvivorEconomyPlayerStateRepository(db.getConnection());
            String eventId =
                    SurvivorEconomyPaycheck.processClockIn(
                            txRepo,
                            stateRepo,
                            username,
                            steamId,
                            System.currentTimeMillis(),
                            issuePaychecks,
                            hoursUntilPaycheck,
                            paycheckValue);
            if (eventId != null) {
                LOGGER.info(
                        "[SurvivorEconomy] Paycheck issued event={} player={} ({}) amount={} {}",
                        eventId,
                        username,
                        steamId,
                        paycheckValue,
                        SurvivorEconomyPaycheck.PAYCHECK_CURRENCY);
                sendPaycheckPaidCommand(player, paycheckValue);
                pushBalanceUpdated(player, db.getConnection());
            }
            return eventId;
        } catch (SQLException e) {
            LOGGER.error(
                    "[SurvivorEconomy] processClockIn failed for {} ({})", username, steamId, e);
            return null;
        }
    }

    /**
     * Push a {@code paycheckPaid} server→client command to a single player. The Lua handler in
     * {@code media/lua/client/SurvivorEconomyClient.lua} consumes this and pops a halo message.
     */
    private static void sendPaycheckPaidCommand(IsoPlayer player, int amount) {
        KahluaTable args = LuaManager.platform.newTable();
        args.rawset("amount", (double) amount);
        args.rawset("currency", SurvivorEconomyPaycheck.PAYCHECK_CURRENCY);
        GameServer.sendServerCommand(player, MODULE, CMD_PAYCHECK_PAID, args);
    }

    static final String CMD_ZOMBIE_BOUNTY_PAID = "zombieBountyPaid";

    /**
     * Process one zombie kill for a player. Reads sandbox values via {@link SurvivorEconomyConfig},
     * rolls chance + amount via {@link ThreadLocalRandom}, and on a hit inserts a {@code
     * ZOMBIE_BOUNTY} SOLE row crediting the {@code primary} bucket and pushes a {@code
     * zombieBountyPaid} server→client command to {@code player} so the client can pop a halo / chat
     * message. Returns the event id when a bounty is paid, or {@code null} otherwise.
     */
    public static @Nullable String processZombieKill(IsoPlayer player) {
        if (player == null) {
            return null;
        }
        String username = player.getUsername();
        if (username == null) {
            return null;
        }
        long steamId = player.getSteamID();
        boolean payBounty = SurvivorEconomyConfig.payZombieBounty();
        int chancePct = SurvivorEconomyConfig.zombieBountyChance();
        int minAmount = SurvivorEconomyConfig.zombieBountyMinAmount();
        int maxAmount = SurvivorEconomyConfig.zombieBountyMaxAmount();
        if (maxAmount < minAmount) {
            maxAmount = minAmount;
        }
        final int min = minAmount;
        final int max = maxAmount;
        try (SurvivorEconomyDatabase db = new SurvivorEconomyDatabase(getDbPath())) {
            SurvivorEconomyRepository txRepo = new SurvivorEconomyRepository(db.getConnection());
            BountyResult result =
                    SurvivorEconomyZombieBounty.processKill(
                            txRepo,
                            username,
                            steamId,
                            System.currentTimeMillis(),
                            () -> ThreadLocalRandom.current().nextInt(0, 101),
                            () -> ThreadLocalRandom.current().nextInt(min, max + 1),
                            payBounty,
                            chancePct,
                            min,
                            max);
            if (result == null) {
                return null;
            }
            LOGGER.info(
                    "[SurvivorEconomy] Zombie bounty paid event={} player={} ({}) amount={} {}",
                    result.eventId(),
                    username,
                    steamId,
                    result.amount(),
                    SurvivorEconomyZombieBounty.BOUNTY_CURRENCY);
            sendBountyPaidCommand(player, result.amount());
            pushBalanceUpdated(player, db.getConnection());
            return result.eventId();
        } catch (SQLException e) {
            LOGGER.error(
                    "[SurvivorEconomy] processZombieKill failed for {} ({})", username, steamId, e);
            return null;
        }
    }

    /**
     * Push a {@code zombieBountyPaid} server→client command to a single player. The Lua handler in
     * {@code media/lua/client/SurvivorEconomyClient.lua} consumes this and pops a halo message.
     */
    private static void sendBountyPaidCommand(IsoPlayer player, int amount) {
        KahluaTable args = LuaManager.platform.newTable();
        args.rawset("amount", (double) amount);
        args.rawset("currency", SurvivorEconomyZombieBounty.BOUNTY_CURRENCY);
        GameServer.sendServerCommand(player, MODULE, CMD_ZOMBIE_BOUNTY_PAID, args);
    }

    static final String CMD_TRANSFER_SENT = "transferSent";
    static final String CMD_TRANSFER_RECEIVED = "transferReceived";
    static final String CMD_TRANSFER_FAILED = "transferFailed";

    /**
     * Process a player→player transfer initiated by {@code sender}. Validates the sandbox toggle,
     * resolves the target in {@link GameServer#Players}, re-checks the range gate server-side, then
     * delegates to {@link SurvivorEconomyTransfer#processTransfer}. On success {@code recordPair}
     * pushes {@code balanceUpdated} to both sides; this method additionally pushes {@code
     * transferSent} to the sender and {@code transferReceived} to the recipient. On failure pushes
     * {@code transferFailed} to the sender with the rejection reason.
     */
    public static TransferResult processTransfer(
            IsoPlayer sender,
            String targetUsername,
            long targetSteamId,
            String currency,
            double amount) {
        if (sender == null || targetUsername == null || currency == null) {
            return TransferResult.failure(TransferFailureReason.INVALID_AMOUNT);
        }
        String fromUsername = sender.getUsername();
        if (fromUsername == null) {
            return TransferResult.failure(TransferFailureReason.INVALID_AMOUNT);
        }
        if (!SurvivorEconomyConfig.allowPlayerTransfers()) {
            sendTransferFailedCommand(sender, TransferFailureReason.DISABLED);
            return TransferResult.failure(TransferFailureReason.DISABLED);
        }
        IsoPlayer target = findOnlinePlayer(targetUsername, targetSteamId);
        if (target == null) {
            sendTransferFailedCommand(sender, TransferFailureReason.TARGET_OFFLINE);
            return TransferResult.failure(TransferFailureReason.TARGET_OFFLINE);
        }
        int maxDistance = SurvivorEconomyConfig.playerTransferMaxDistance();
        float distSq = sender.DistToSquared(target);
        if (distSq > (float) maxDistance * (float) maxDistance) {
            sendTransferFailedCommand(sender, TransferFailureReason.OUT_OF_RANGE);
            return TransferResult.failure(TransferFailureReason.OUT_OF_RANGE);
        }
        long fromSteamId = sender.getSteamID();
        try (SurvivorEconomyDatabase db = new SurvivorEconomyDatabase(getDbPath())) {
            SurvivorEconomyRepository txRepo = new SurvivorEconomyRepository(db.getConnection());
            SurvivorEconomyBalanceRepository balanceRepo =
                    new SurvivorEconomyBalanceRepository(db.getConnection());
            TransferResult result =
                    SurvivorEconomyTransfer.processTransfer(
                            txRepo,
                            balanceRepo,
                            fromUsername,
                            fromSteamId,
                            targetUsername,
                            targetSteamId,
                            currency,
                            amount,
                            System.currentTimeMillis());
            if (!result.ok()) {
                sendTransferFailedCommand(sender, result.failureReason());
                return result;
            }
            LOGGER.info(
                    "[SurvivorEconomy] Transfer event={} from={} ({}) to={} ({}) amount={} {}",
                    result.eventId(),
                    fromUsername,
                    fromSteamId,
                    targetUsername,
                    targetSteamId,
                    amount,
                    currency);
            pushBalanceUpdated(sender, db.getConnection());
            pushBalanceUpdated(target, db.getConnection());
            sendTransferSentCommand(sender, target, currency, amount);
            sendTransferReceivedCommand(target, sender, currency, amount);
            return result;
        } catch (SQLException e) {
            LOGGER.error(
                    "[SurvivorEconomy] processTransfer failed from={} ({}) to={} ({})",
                    fromUsername,
                    fromSteamId,
                    targetUsername,
                    targetSteamId,
                    e);
            sendTransferFailedCommand(sender, TransferFailureReason.INVALID_AMOUNT);
            return TransferResult.failure(TransferFailureReason.INVALID_AMOUNT);
        }
    }

    private static void sendTransferSentCommand(
            IsoPlayer sender, IsoPlayer recipient, String currency, double amount) {
        KahluaTable args = LuaManager.platform.newTable();
        args.rawset("amount", amount);
        args.rawset("currency", currency);
        args.rawset("otherUsername", recipient.getUsername());
        args.rawset("otherDisplayName", recipient.getDisplayName());
        GameServer.sendServerCommand(sender, MODULE, CMD_TRANSFER_SENT, args);
    }

    private static void sendTransferReceivedCommand(
            IsoPlayer recipient, IsoPlayer sender, String currency, double amount) {
        KahluaTable args = LuaManager.platform.newTable();
        args.rawset("amount", amount);
        args.rawset("currency", currency);
        args.rawset("otherUsername", sender.getUsername());
        args.rawset("otherDisplayName", sender.getDisplayName());
        GameServer.sendServerCommand(recipient, MODULE, CMD_TRANSFER_RECEIVED, args);
    }

    private static void sendTransferFailedCommand(IsoPlayer sender, TransferFailureReason reason) {
        if (sender == null || reason == null) {
            return;
        }
        KahluaTable args = LuaManager.platform.newTable();
        args.rawset("reason", reason.name());
        GameServer.sendServerCommand(sender, MODULE, CMD_TRANSFER_FAILED, args);
    }

    static final String CMD_BALANCE_UPDATED = "balanceUpdated";

    /**
     * Read the player's current balances and push a {@code balanceUpdated} server→client command
     * with the full per-currency map. Called every time a transaction is recorded for the player
     * and in response to a {@code requestBalance} client→server command. Always pushes — even with
     * an empty balance map — so the client can clear its cache if a row was wiped.
     */
    public static void pushBalanceUpdated(IsoPlayer player) {
        if (player == null) {
            return;
        }
        try (SurvivorEconomyDatabase db = new SurvivorEconomyDatabase(getDbPath())) {
            pushBalanceUpdated(player, db.getConnection());
        } catch (SQLException e) {
            LOGGER.error(
                    "[SurvivorEconomy] Failed to push balanceUpdated for {} ({})",
                    player.getUsername(),
                    player.getSteamID(),
                    e);
        }
    }

    /**
     * Variant that reuses a caller-supplied connection so we don't reopen the DB after a successful
     * insert in the same call site. Caller still owns the connection.
     */
    private static void pushBalanceUpdated(IsoPlayer player, Connection connection)
            throws SQLException {
        SurvivorEconomyBalanceRepository balanceRepo =
                new SurvivorEconomyBalanceRepository(connection);
        Map<String, Double> balances =
                balanceRepo.getBalances(player.getUsername(), player.getSteamID());
        sendBalanceUpdatedCommand(player, balances);
    }

    /**
     * Look up the affected player by username + steamId in {@link GameServer#Players} and push a
     * {@code balanceUpdated} command if they're online. Used by {@link #recordSole} / {@link
     * #recordPair} call sites which don't have an {@link IsoPlayer} reference. Offline players
     * silently fall through — they'll fetch on next connect via {@code requestBalance}.
     */
    private static void pushBalanceUpdatedToOnlinePlayer(
            Connection connection, String username, long steamId) throws SQLException {
        IsoPlayer player = findOnlinePlayer(username, steamId);
        if (player == null) {
            return;
        }
        pushBalanceUpdated(player, connection);
    }

    private static @Nullable IsoPlayer findOnlinePlayer(String username, long steamId) {
        for (IsoPlayer p : GameServer.Players) {
            if (p == null) {
                continue;
            }
            if (p.getSteamID() == steamId && username.equals(p.getUsername())) {
                return p;
            }
        }
        return null;
    }

    private static void sendBalanceUpdatedCommand(IsoPlayer player, Map<String, Double> balances) {
        KahluaTable args = LuaManager.platform.newTable();
        KahluaTable balancesTable = LuaManager.platform.newTable();
        for (Map.Entry<String, Double> e : balances.entrySet()) {
            balancesTable.rawset(e.getKey(), e.getValue());
        }
        args.rawset("balances", balancesTable);
        GameServer.sendServerCommand(player, MODULE, CMD_BALANCE_UPDATED, args);
    }

    /**
     * Mint a new {@code DISCORD}-direction link code on behalf of a Discord user. The bot calls
     * this when a user runs {@code /link} in chat; the returned code is shown to the user and later
     * consumed by an in-game claim. Returns null on database error.
     */
    public static @Nullable DiscordLinkCode createDiscordLinkCode(
            String discordId, @Nullable String discordUsername) {
        if (discordId == null || discordId.isBlank()) {
            return null;
        }
        try (SurvivorEconomyDatabase db = new SurvivorEconomyDatabase(getDbPath())) {
            DiscordLinkRepository repo = new DiscordLinkRepository(db.getConnection());
            DiscordLinkCode code =
                    repo.createDiscordCode(
                            discordId,
                            discordUsername,
                            System.currentTimeMillis(),
                            DiscordLinkRepository.DEFAULT_CODE_TTL_MS);
            LOGGER.info(
                    "[SurvivorEconomy] Minted DISCORD link code {} for discord_id={} expires_at_ms={}",
                    code.code(),
                    discordId,
                    code.expiresAtMs());
            return code;
        } catch (SQLException e) {
            LOGGER.error(
                    "[SurvivorEconomy] Failed to mint discord link code for discord_id={}",
                    discordId,
                    e);
            return null;
        }
    }

    /**
     * List the Discord ↔ Steam ID associations belonging to a Discord user. Returns an empty list
     * on error or if no links exist.
     */
    public static List<DiscordLink> listDiscordLinks(String discordId) {
        if (discordId == null || discordId.isBlank()) {
            return List.of();
        }
        try (SurvivorEconomyDatabase db = new SurvivorEconomyDatabase(getDbPath())) {
            DiscordLinkRepository repo = new DiscordLinkRepository(db.getConnection());
            return repo.listLinksForDiscord(discordId);
        } catch (SQLException e) {
            LOGGER.error(
                    "[SurvivorEconomy] Failed to list discord links for discord_id={}",
                    discordId,
                    e);
            return List.of();
        }
    }

    /**
     * List the Discord ↔ Steam ID associations attached to a given Steam ID. Inverse of {@link
     * #listDiscordLinks(String)}. Returns an empty list on error or if no links exist.
     */
    public static List<DiscordLink> listDiscordLinksForSteamId(long steamId) {
        try (SurvivorEconomyDatabase db = new SurvivorEconomyDatabase(getDbPath())) {
            DiscordLinkRepository repo = new DiscordLinkRepository(db.getConnection());
            return repo.listLinksForSteamId(steamId);
        } catch (SQLException e) {
            LOGGER.error(
                    "[SurvivorEconomy] Failed to list discord links for steam_id={}", steamId, e);
            return List.of();
        }
    }

    /**
     * Atomically consume a {@code DISCORD}-direction code as the given player and create the
     * resulting link. Returns the claim outcome — success carries the resolved Discord identity,
     * failure carries a {@code FAILURE_*} reason.
     */
    public static DiscordLinkClaimResult claimDiscordCodeAsPlayer(
            String code, long steamId, String username) {
        if (code == null || code.isBlank() || username == null || username.isBlank()) {
            return DiscordLinkClaimResult.failure(DiscordLinkClaimResult.FAILURE_NOT_FOUND);
        }
        try (SurvivorEconomyDatabase db = new SurvivorEconomyDatabase(getDbPath())) {
            DiscordLinkRepository repo = new DiscordLinkRepository(db.getConnection());
            DiscordLinkClaimResult result =
                    repo.consumeDiscordCodeAsPlayer(
                            code, steamId, username, System.currentTimeMillis());
            if (result.ok()) {
                LOGGER.info(
                        "[SurvivorEconomy] Claimed DISCORD link code {} discord_id={} player={} ({})",
                        code,
                        result.discordId(),
                        username,
                        steamId);
            } else {
                LOGGER.info(
                        "[SurvivorEconomy] Rejected DISCORD link claim code={} reason={} player={} ({})",
                        code,
                        result.failureReason(),
                        username,
                        steamId);
            }
            return result;
        } catch (SQLException e) {
            LOGGER.error(
                    "[SurvivorEconomy] claimDiscordCodeAsPlayer failed code={} player={} ({})",
                    code,
                    username,
                    steamId,
                    e);
            return DiscordLinkClaimResult.failure(DiscordLinkClaimResult.FAILURE_NOT_FOUND);
        }
    }

    public static final String DISCORD_TIP_TYPE = "DISCORD_TIP";
    public static final String DISCORD_WALLET_CLAIM_TYPE = "DISCORD_WALLET_CLAIM";

    static final String CMD_DISCORD_CLAIM_RESULT = "discordClaimResult";

    /**
     * Move funds from a sender's character bank account to a recipient Discord user's escrow
     * wallet. Sender's character must be linked to {@code senderDiscordId} via {@code
     * discord_links}. Recipient does not need to be linked at tip time — funds accumulate in escrow
     * under the synthetic {@link DiscordPlayerIdentity} until they pull from it in-game.
     *
     * <p>Single {@code insertPair} → atomic debit/credit, identical guarantee to the
     * player-to-player transfer path.
     */
    public static TransferResult processDiscordTip(
            String senderDiscordId,
            String fromUsername,
            long fromSteamId,
            String currency,
            double amount,
            String recipientDiscordId) {
        if (senderDiscordId == null
                || senderDiscordId.isBlank()
                || recipientDiscordId == null
                || recipientDiscordId.isBlank()
                || fromUsername == null
                || fromUsername.isBlank()
                || currency == null
                || currency.isBlank()) {
            return TransferResult.failure(TransferFailureReason.INVALID_AMOUNT);
        }
        if (!Double.isFinite(amount) || amount <= 0.0) {
            return TransferResult.failure(TransferFailureReason.INVALID_AMOUNT);
        }
        if (senderDiscordId.equals(recipientDiscordId)) {
            return TransferResult.failure(TransferFailureReason.SAME_PLAYER);
        }
        DiscordPlayerIdentity recipient;
        try {
            recipient = DiscordPlayerIdentity.of(recipientDiscordId);
        } catch (IllegalArgumentException e) {
            return TransferResult.failure(TransferFailureReason.INVALID_AMOUNT);
        }
        long nowMs = System.currentTimeMillis();
        try (SurvivorEconomyDatabase db = new SurvivorEconomyDatabase(getDbPath())) {
            DiscordLinkRepository linkRepo = new DiscordLinkRepository(db.getConnection());
            if (!linkRepo.isLinked(senderDiscordId, fromSteamId)) {
                return TransferResult.failure(TransferFailureReason.SENDER_NOT_LINKED);
            }
            SurvivorEconomyBalanceRepository balanceRepo =
                    new SurvivorEconomyBalanceRepository(db.getConnection());
            double senderBalance =
                    balanceRepo.getBalances(fromUsername, fromSteamId).getOrDefault(currency, 0.0);
            if (senderBalance < amount) {
                return TransferResult.failure(TransferFailureReason.INSUFFICIENT_BALANCE);
            }
            TransactionDraft fromDraft =
                    TransactionDraft.basic(
                            DISCORD_TIP_TYPE, nowMs, fromUsername, fromSteamId, currency, -amount);
            TransactionDraft toDraft =
                    TransactionDraft.basic(
                            DISCORD_TIP_TYPE,
                            nowMs,
                            recipient.username(),
                            recipient.steamId(),
                            currency,
                            amount);
            SurvivorEconomyRepository txRepo = new SurvivorEconomyRepository(db.getConnection());
            String eventId = txRepo.insertPair(fromDraft, toDraft);
            LOGGER.info(
                    "[SurvivorEconomy] Discord tip event={} from=discord:{}/{} ({}) to=discord:{} amount={} {}",
                    eventId,
                    senderDiscordId,
                    fromUsername,
                    fromSteamId,
                    recipient.discordId(),
                    amount,
                    currency);
            // Push balance update to sender's character if online; synthetic recipient never
            // matches GameServer.Players, so the helper falls through silently.
            pushBalanceUpdatedToOnlinePlayer(db.getConnection(), fromUsername, fromSteamId);
            return TransferResult.success(eventId);
        } catch (SQLException e) {
            LOGGER.error(
                    "[SurvivorEconomy] processDiscordTip failed sender={} recipient={}",
                    senderDiscordId,
                    recipientDiscordId,
                    e);
            return TransferResult.failure(TransferFailureReason.INVALID_AMOUNT);
        }
    }

    /**
     * Pull funds from {@code fromDiscordId}'s escrow wallet into the claiming character's bank
     * account. The character must be linked to that Discord ID. Inverse of {@link
     * #processDiscordTip} — same {@code insertPair} primitive, just with the synthetic identity on
     * the FROM side.
     */
    public static TransferResult claimDiscordWallet(
            IsoPlayer claimer, String fromDiscordId, String currency, double amount) {
        if (claimer == null
                || fromDiscordId == null
                || fromDiscordId.isBlank()
                || currency == null
                || currency.isBlank()) {
            return TransferResult.failure(TransferFailureReason.INVALID_AMOUNT);
        }
        if (!Double.isFinite(amount) || amount <= 0.0) {
            return TransferResult.failure(TransferFailureReason.INVALID_AMOUNT);
        }
        String username = claimer.getUsername();
        long steamId = claimer.getSteamID();
        if (username == null) {
            return TransferResult.failure(TransferFailureReason.INVALID_AMOUNT);
        }
        DiscordPlayerIdentity wallet;
        try {
            wallet = DiscordPlayerIdentity.of(fromDiscordId);
        } catch (IllegalArgumentException e) {
            sendDiscordClaimResultCommand(
                    claimer, false, TransferFailureReason.INVALID_AMOUNT, currency, 0.0);
            return TransferResult.failure(TransferFailureReason.INVALID_AMOUNT);
        }
        long nowMs = System.currentTimeMillis();
        try (SurvivorEconomyDatabase db = new SurvivorEconomyDatabase(getDbPath())) {
            DiscordLinkRepository linkRepo = new DiscordLinkRepository(db.getConnection());
            if (!linkRepo.isLinked(fromDiscordId, steamId)) {
                sendDiscordClaimResultCommand(
                        claimer, false, TransferFailureReason.NOT_LINKED, currency, 0.0);
                return TransferResult.failure(TransferFailureReason.NOT_LINKED);
            }
            SurvivorEconomyBalanceRepository balanceRepo =
                    new SurvivorEconomyBalanceRepository(db.getConnection());
            double walletBalance =
                    balanceRepo
                            .getBalances(wallet.username(), wallet.steamId())
                            .getOrDefault(currency, 0.0);
            if (walletBalance < amount) {
                sendDiscordClaimResultCommand(
                        claimer, false, TransferFailureReason.INSUFFICIENT_BALANCE, currency, 0.0);
                return TransferResult.failure(TransferFailureReason.INSUFFICIENT_BALANCE);
            }
            TransactionDraft fromDraft =
                    TransactionDraft.basic(
                            DISCORD_WALLET_CLAIM_TYPE,
                            nowMs,
                            wallet.username(),
                            wallet.steamId(),
                            currency,
                            -amount);
            TransactionDraft toDraft =
                    TransactionDraft.basic(
                            DISCORD_WALLET_CLAIM_TYPE, nowMs, username, steamId, currency, amount);
            SurvivorEconomyRepository txRepo = new SurvivorEconomyRepository(db.getConnection());
            String eventId = txRepo.insertPair(fromDraft, toDraft);
            LOGGER.info(
                    "[SurvivorEconomy] Discord wallet claim event={} discord={} player={} ({}) amount={} {}",
                    eventId,
                    fromDiscordId,
                    username,
                    steamId,
                    amount,
                    currency);
            pushBalanceUpdated(claimer, db.getConnection());
            sendDiscordClaimResultCommand(claimer, true, null, currency, amount);
            return TransferResult.success(eventId);
        } catch (SQLException e) {
            LOGGER.error(
                    "[SurvivorEconomy] claimDiscordWallet failed discord={} player={} ({})",
                    fromDiscordId,
                    username,
                    steamId,
                    e);
            sendDiscordClaimResultCommand(
                    claimer, false, TransferFailureReason.INVALID_AMOUNT, currency, 0.0);
            return TransferResult.failure(TransferFailureReason.INVALID_AMOUNT);
        }
    }

    /**
     * Every (character × currency) balance reachable through any Steam ID linked to {@code
     * discordId}, with positive balance only. Drives the {@code /tip} account picker on the bot
     * side.
     */
    public static List<DiscordAccount> listDiscordAccounts(String discordId) {
        if (discordId == null || discordId.isBlank()) {
            return List.of();
        }
        try (SurvivorEconomyDatabase db = new SurvivorEconomyDatabase(getDbPath())) {
            DiscordLinkRepository repo = new DiscordLinkRepository(db.getConnection());
            return repo.listAccountsForDiscord(discordId);
        } catch (SQLException e) {
            LOGGER.error(
                    "[SurvivorEconomy] Failed to list discord accounts for discord_id={}",
                    discordId,
                    e);
            return List.of();
        }
    }

    /**
     * Per-currency escrow wallet balances held under the Discord user's synthetic identity. Returns
     * an empty map if the wallet has never received a tip.
     */
    public static Map<String, Double> getDiscordWalletBalances(String discordId) {
        if (discordId == null || discordId.isBlank()) {
            return Map.of();
        }
        DiscordPlayerIdentity identity;
        try {
            identity = DiscordPlayerIdentity.of(discordId);
        } catch (IllegalArgumentException e) {
            return Map.of();
        }
        try (SurvivorEconomyDatabase db = new SurvivorEconomyDatabase(getDbPath())) {
            SurvivorEconomyBalanceRepository balanceRepo =
                    new SurvivorEconomyBalanceRepository(db.getConnection());
            return balanceRepo.getBalances(identity.username(), identity.steamId());
        } catch (SQLException e) {
            LOGGER.error(
                    "[SurvivorEconomy] Failed to load discord wallet for discord_id={}",
                    discordId,
                    e);
            return Map.of();
        }
    }

    private static void sendDiscordClaimResultCommand(
            IsoPlayer player,
            boolean ok,
            @Nullable TransferFailureReason reason,
            String currency,
            double amount) {
        if (player == null) {
            return;
        }
        KahluaTable args = LuaManager.platform.newTable();
        args.rawset("ok", ok);
        if (reason != null) {
            args.rawset("reason", reason.name());
        }
        args.rawset("currency", currency);
        args.rawset("amount", amount);
        GameServer.sendServerCommand(player, MODULE, CMD_DISCORD_CLAIM_RESULT, args);
    }

    public static Map<String, Double> getBalances(String username, long steamId) {
        try (SurvivorEconomyDatabase db = new SurvivorEconomyDatabase(getDbPath())) {
            SurvivorEconomyRepository repo = new SurvivorEconomyRepository(db.getConnection());
            return repo.loadBalances(username, steamId);
        } catch (SQLException e) {
            LOGGER.error(
                    "[SurvivorEconomy] Failed to load balances for {} ({})", username, steamId, e);
            return Map.of();
        }
    }

    /**
     * Execute arbitrary SQL against the economy database. If the statement produces a result set,
     * the rows are materialized and returned; otherwise the update count is returned. Intended as
     * an admin/debug tool — there is no sanitization.
     */
    public static SqlExecutionResponse executeSql(String sql) {
        try (SurvivorEconomyDatabase db = new SurvivorEconomyDatabase(getDbPath())) {
            return executeSql(sql, db.getConnection());
        } catch (SQLException e) {
            LOGGER.error("[SurvivorEconomy] SQL execution failed: {}", sql, e);
            return SqlExecutionResponse.error(e.getMessage());
        }
    }

    /** Package-private overload used by the public entry point and by tests. */
    static SqlExecutionResponse executeSql(String sql, Connection conn) {
        try (Statement stmt = conn.createStatement()) {
            boolean hasResultSet = stmt.execute(sql);
            if (hasResultSet) {
                try (ResultSet rs = stmt.getResultSet()) {
                    ResultSetMetaData meta = rs.getMetaData();
                    int columnCount = meta.getColumnCount();
                    List<String> columns = new ArrayList<>(columnCount);
                    for (int i = 1; i <= columnCount; i++) {
                        columns.add(meta.getColumnLabel(i));
                    }
                    List<List<Object>> rows = new ArrayList<>();
                    while (rs.next()) {
                        List<Object> row = new ArrayList<>(columnCount);
                        for (int i = 1; i <= columnCount; i++) {
                            row.add(rs.getObject(i));
                        }
                        rows.add(row);
                    }
                    return SqlExecutionResponse.rows(columns, rows);
                }
            }
            return SqlExecutionResponse.update(stmt.getUpdateCount());
        } catch (SQLException e) {
            LOGGER.error("[SurvivorEconomy] SQL execution failed: {}", sql, e);
            return SqlExecutionResponse.error(e.getMessage());
        }
    }
}
