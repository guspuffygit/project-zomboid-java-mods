package com.sentientsimulations.projectzomboid.survivoreconomy;

import com.sentientsimulations.projectzomboid.survivoreconomy.records.TransactionDraft;
import java.sql.SQLException;
import org.jspecify.annotations.Nullable;

/**
 * Bumps the per-player online_hours counter once per call, and when the threshold is reached emits
 * a {@code PAYCHECK} SOLE row (when {@code issuePaychecks} is true) and decrements hours by the
 * threshold.
 *
 * <p>The threshold-decrement happens regardless of {@code issuePaychecks} — toggling paychecks off
 * should not silently accumulate hours past the threshold.
 *
 * <p>This first slice credits {@code primary} directly — a {@code paycheck} bucket plus ATM-claim
 * flow can be added once {@code economy_accounts} exists.
 */
public final class SurvivorEconomyPaycheck {

    public static final String PAYCHECK_CURRENCY = "primary";
    public static final String PAYCHECK_TYPE = "PAYCHECK";

    private SurvivorEconomyPaycheck() {}

    /**
     * Run one clock-in tick for a player. Returns the generated paycheck event id if one was issued
     * this tick, or {@code null} if no payout occurred (below threshold, paychecks disabled, or
     * insertion failed).
     */
    public static @Nullable String processClockIn(
            SurvivorEconomyRepository txRepo,
            SurvivorEconomyPlayerStateRepository stateRepo,
            String username,
            long steamId,
            long nowMs,
            boolean issuePaychecks,
            int hoursUntilPaycheck,
            int paycheckValue)
            throws SQLException {
        int hours = stateRepo.getOnlineHours(username, steamId) + 1;
        String eventId = null;
        if (hours >= hoursUntilPaycheck) {
            if (issuePaychecks) {
                TransactionDraft draft =
                        TransactionDraft.basic(
                                PAYCHECK_TYPE,
                                nowMs,
                                username,
                                steamId,
                                PAYCHECK_CURRENCY,
                                paycheckValue);
                eventId = txRepo.insertSole(draft);
            }
            hours -= hoursUntilPaycheck;
        }
        stateRepo.setOnlineHours(username, steamId, hours, nowMs);
        return eventId;
    }
}
