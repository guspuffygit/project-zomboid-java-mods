package com.sentientsimulations.projectzomboid.survivoreconomy.records;

/**
 * A single character × currency balance reachable from a Discord user. Returned as part of {@link
 * DiscordAccountsResponse} to populate the "/tip" account picker on the bot side.
 */
public record DiscordAccount(String username, long steamId, String currency, double balance) {}
