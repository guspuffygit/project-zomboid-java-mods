package com.sentientsimulations.projectzomboid.survivoreconomy;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.survivoreconomy.records.BountyResult;
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
