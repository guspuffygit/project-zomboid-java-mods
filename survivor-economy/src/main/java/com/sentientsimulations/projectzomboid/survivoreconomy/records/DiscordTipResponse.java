package com.sentientsimulations.projectzomboid.survivoreconomy.records;

import org.jspecify.annotations.Nullable;

/**
 * Response shape for {@code POST /economy/discord/tip}. On success {@code eventId} is the paired
 * {@code economy_transactions} event id; on failure {@code reason} carries a {@link
 * TransferFailureReason} name and {@code eventId} is null.
 */
public record DiscordTipResponse(boolean ok, @Nullable String eventId, @Nullable String reason) {

    public static DiscordTipResponse success(String eventId) {
        return new DiscordTipResponse(true, eventId, null);
    }

    public static DiscordTipResponse failure(TransferFailureReason reason) {
        return new DiscordTipResponse(false, null, reason.name());
    }
}
