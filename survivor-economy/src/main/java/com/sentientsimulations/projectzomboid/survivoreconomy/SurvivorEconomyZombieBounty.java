package com.sentientsimulations.projectzomboid.survivoreconomy;

import com.sentientsimulations.projectzomboid.survivoreconomy.records.BountyResult;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.TransactionDraft;
import java.sql.SQLException;
import java.util.function.IntSupplier;
import org.jspecify.annotations.Nullable;

/**
 * Rolls a chance gate and an amount in [{@code minAmount}, {@code maxAmount}], then writes a single
 * {@code ZOMBIE_BOUNTY} SOLE row.
 *
 * <p>This first slice credits {@code primary} directly — a {@code cash_*} bucket model and
 * randomize/select-currency sandbox options can be added once {@code economy_accounts} exists.
 */
public final class SurvivorEconomyZombieBounty {

    public static final String BOUNTY_CURRENCY = "primary";
    public static final String BOUNTY_TYPE = "ZOMBIE_BOUNTY";
    public static final String BOUNTY_REASON = "zombie_bounty";

    private SurvivorEconomyZombieBounty() {}

    /**
     * Process one zombie kill for a player. Returns a {@link BountyResult} carrying the generated
     * event id and the rolled amount when a bounty is paid, or {@code null} when payouts are
     * disabled or the chance roll misses.
     *
     * <p>{@code rollChance} should return values in 0..100 inclusive; a hit is {@code roll <=
     * chancePct}. {@code rollAmount} is invoked only on a hit and should return a value in [{@code
     * minAmount}, {@code maxAmount}] inclusive.
     */
    public static @Nullable BountyResult processKill(
            SurvivorEconomyRepository txRepo,
            String username,
            long steamId,
            long nowMs,
            IntSupplier rollChance,
            IntSupplier rollAmount,
            boolean payBounty,
            int chancePct,
            int minAmount,
            int maxAmount)
            throws SQLException {
        if (!payBounty) {
            return null;
        }
        int chanceRoll = rollChance.getAsInt();
        if (chanceRoll > chancePct) {
            return null;
        }
        int amount = rollAmount.getAsInt();
        if (amount < minAmount) {
            amount = minAmount;
        }
        if (amount > maxAmount) {
            amount = maxAmount;
        }
        TransactionDraft draft =
                new TransactionDraft(
                        BOUNTY_TYPE,
                        nowMs,
                        BOUNTY_REASON,
                        null,
                        username,
                        steamId,
                        BOUNTY_CURRENCY,
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
        String eventId = txRepo.insertSole(draft);
        return new BountyResult(eventId, amount);
    }
}
