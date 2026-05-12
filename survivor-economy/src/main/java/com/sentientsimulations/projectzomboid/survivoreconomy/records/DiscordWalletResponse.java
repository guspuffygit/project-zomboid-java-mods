package com.sentientsimulations.projectzomboid.survivoreconomy.records;

import java.util.List;

/**
 * Response shape for {@code GET /economy/discord/wallet}. Per-currency escrow balances held under
 * the Discord user's synthetic identity (negated snowflake as steamid).
 */
public record DiscordWalletResponse(String discordId, List<BalanceDTO> balances) {}
