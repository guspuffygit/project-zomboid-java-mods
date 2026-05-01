package com.sentientsimulations.projectzomboid.survivoreconomy;

import com.sentientsimulations.projectzomboid.survivoreconomy.records.TransactionDraft;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.TransferFailureReason;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.TransferResult;
import java.sql.SQLException;
import java.util.Map;

/**
 * Writes a {@code BANK_WIRE_TO_PLAYER} paired row crediting the recipient and debiting the sender,
 * with the same {@code event_id} on both sides — the underlying {@code insertPair} runs in a single
 * SQL transaction, so debit and credit either both land or both roll back.
 *
 * <p>This first slice moves {@code primary} → {@code primary} only. When {@code economy_accounts}
 * lands the {@code cash_*} bucket variant can be added alongside.
 */
public final class SurvivorEconomyTransfer {

    public static final String TRANSFER_TYPE = "BANK_WIRE_TO_PLAYER";
    public static final String TRANSFER_REASON = "wire";

    private SurvivorEconomyTransfer() {}

    /**
     * Validate and execute a transfer from {@code from} to {@code to} in {@code currency}. Returns
     * a success result with the generated event id, or a failure result naming the reason. Pure
     * logic — no IsoPlayer / SandboxOptions / GameServer dependencies; the bridge layer handles
     * range, online-state, and sandbox toggle before calling this.
     */
    public static TransferResult processTransfer(
            SurvivorEconomyRepository txRepo,
            SurvivorEconomyBalanceRepository balanceRepo,
            String fromUsername,
            long fromSteamId,
            String toUsername,
            long toSteamId,
            String currency,
            double amount,
            long nowMs)
            throws SQLException {
        if (!Double.isFinite(amount) || amount <= 0.0) {
            return TransferResult.failure(TransferFailureReason.INVALID_AMOUNT);
        }
        if (fromSteamId == toSteamId && fromUsername.equals(toUsername)) {
            return TransferResult.failure(TransferFailureReason.SAME_PLAYER);
        }
        Map<String, Double> senderBalances = balanceRepo.getBalances(fromUsername, fromSteamId);
        double senderBalance = senderBalances.getOrDefault(currency, 0.0);
        if (senderBalance < amount) {
            return TransferResult.failure(TransferFailureReason.INSUFFICIENT_BALANCE);
        }
        TransactionDraft fromDraft =
                new TransactionDraft(
                        TRANSFER_TYPE,
                        nowMs,
                        TRANSFER_REASON,
                        null,
                        fromUsername,
                        fromSteamId,
                        currency,
                        -amount,
                        null,
                        null,
                        null,
                        null,
                        null,
                        null,
                        null,
                        null,
                        null);
        TransactionDraft toDraft =
                new TransactionDraft(
                        TRANSFER_TYPE,
                        nowMs,
                        TRANSFER_REASON,
                        null,
                        toUsername,
                        toSteamId,
                        currency,
                        amount,
                        null,
                        null,
                        null,
                        null,
                        null,
                        null,
                        null,
                        null,
                        null);
        String eventId = txRepo.insertPair(fromDraft, toDraft);
        return TransferResult.success(eventId);
    }
}
