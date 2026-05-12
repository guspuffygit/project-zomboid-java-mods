package com.sentientsimulations.projectzomboid.survivoreconomy.records;

import java.util.List;

/**
 * Response shape for {@code GET /economy/discord/accounts}. Lists every (character, currency)
 * balance reachable through any Steam ID linked to the given Discord user.
 */
public record DiscordAccountsResponse(String discordId, List<DiscordAccount> accounts) {}
