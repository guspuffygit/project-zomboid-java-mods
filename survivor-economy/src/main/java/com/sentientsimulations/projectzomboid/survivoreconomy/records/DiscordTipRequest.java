package com.sentientsimulations.projectzomboid.survivoreconomy.records;

import com.fasterxml.jackson.annotation.JsonProperty;

/**
 * Request body for {@code POST /economy/discord/tip}. The chosen sending account is identified by
 * {@code (fromUsername, fromSteamId, currency)} — that triple maps to one row in {@code
 * economy_balance}. The character must be linked to {@code senderDiscordId} via {@code
 * discord_links}.
 */
public record DiscordTipRequest(
        @JsonProperty(required = true) String senderDiscordId,
        @JsonProperty(required = true) String fromUsername,
        @JsonProperty(required = true) long fromSteamId,
        @JsonProperty(required = true) String currency,
        @JsonProperty(required = true) double amount,
        @JsonProperty(required = true) String recipientDiscordId) {}
