package com.sentientsimulations.projectzomboid.survivoreconomy;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.BalanceDTO;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.CreateDiscordCodeRequest;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.DiscordAccount;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.DiscordAccountsResponse;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.DiscordLink;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.DiscordLinkCode;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.DiscordLinksBySteamIdResponse;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.DiscordLinksResponse;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.DiscordTipRequest;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.DiscordTipResponse;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.DiscordWalletResponse;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.SqlExecutionResponse;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.TransferResult;
import io.pzstorm.storm.http.HttpEndpoint;
import io.pzstorm.storm.http.HttpRequestEvent;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * HTTP surface for the Discord ↔ Steam ID linking system. Mirrors the {@link
 * SurvivorEconomyEndpoints} pattern: static methods annotated with {@link HttpEndpoint}, registered
 * once at startup via {@code StormEventDispatcher.registerEventHandler}. Field names are camelCase
 * to match the rest of the survivor-economy API.
 */
public class DiscordLinkEndpoints {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    /**
     * Mint a new {@code DISCORD}-direction link code on behalf of a Discord user. Body fields:
     * {@code discordId} (required), {@code discordUsername} (optional). Returns the generated
     * {@link DiscordLinkCode} JSON.
     */
    @HttpEndpoint(path = "/economy/discord/link/code/discord", method = "POST")
    public static void createDiscordCode(HttpRequestEvent event, CreateDiscordCodeRequest body)
            throws IOException {
        DiscordLinkCode code =
                SurvivorEconomyBridge.createDiscordLinkCode(
                        body.discordId(), body.discordUsername());
        if (code == null) {
            event.sendJson(
                    500,
                    MAPPER.writeValueAsString(
                            SqlExecutionResponse.error("Failed to mint code; see server logs.")));
            return;
        }
        event.sendJson(200, MAPPER.writeValueAsString(code));
    }

    /**
     * List the established Discord ↔ Steam ID associations for a Discord user. Query: {@code
     * discordId} (required). Returns {@link DiscordLinksResponse} JSON.
     */
    @HttpEndpoint(path = "/economy/discord/link")
    public static void listLinks(HttpRequestEvent event) throws IOException {
        Map<String, String> params = event.getQueryParams();
        String discordId = trimToNull(params.get("discordId"));
        if (discordId == null) {
            event.sendJson(
                    400,
                    MAPPER.writeValueAsString(SqlExecutionResponse.error("Missing discordId.")));
            return;
        }
        List<DiscordLink> links = SurvivorEconomyBridge.listDiscordLinks(discordId);
        event.sendJson(200, MAPPER.writeValueAsString(new DiscordLinksResponse(discordId, links)));
    }

    /**
     * Inverse of {@link #listLinks}: list the Discord users linked to a given Steam ID. Used by the
     * Beacon Discord bot's {@code /playerinfo} command to surface self-attested Discord links
     * alongside its staff-managed associations. Query: {@code steamId} (required, numeric).
     */
    @HttpEndpoint(path = "/economy/discord/link/by-steam")
    public static void listLinksBySteamId(HttpRequestEvent event) throws IOException {
        Map<String, String> params = event.getQueryParams();
        String raw = trimToNull(params.get("steamId"));
        if (raw == null) {
            event.sendJson(
                    400, MAPPER.writeValueAsString(SqlExecutionResponse.error("Missing steamId.")));
            return;
        }
        long steamId;
        try {
            steamId = Long.parseLong(raw);
        } catch (NumberFormatException e) {
            event.sendJson(
                    400,
                    MAPPER.writeValueAsString(
                            SqlExecutionResponse.error("steamId must be a number.")));
            return;
        }
        List<DiscordLink> links = SurvivorEconomyBridge.listDiscordLinksForSteamId(steamId);
        event.sendJson(
                200, MAPPER.writeValueAsString(new DiscordLinksBySteamIdResponse(steamId, links)));
    }

    /**
     * List every (character × currency) balance reachable through the given Discord user's linked
     * Steam IDs. Only positive balances are included. Query: {@code discordId} (required).
     */
    @HttpEndpoint(path = "/economy/discord/accounts")
    public static void listAccounts(HttpRequestEvent event) throws IOException {
        Map<String, String> params = event.getQueryParams();
        String discordId = trimToNull(params.get("discordId"));
        if (discordId == null) {
            event.sendJson(
                    400,
                    MAPPER.writeValueAsString(SqlExecutionResponse.error("Missing discordId.")));
            return;
        }
        List<DiscordAccount> accounts = SurvivorEconomyBridge.listDiscordAccounts(discordId);
        event.sendJson(
                200, MAPPER.writeValueAsString(new DiscordAccountsResponse(discordId, accounts)));
    }

    /**
     * Tip endpoint — debits the sender's chosen character × currency account and credits the
     * recipient's Discord escrow wallet. Single paired transaction; either both sides commit or
     * neither does.
     */
    @HttpEndpoint(path = "/economy/discord/tip", method = "POST")
    public static void tip(HttpRequestEvent event, DiscordTipRequest body) throws IOException {
        TransferResult result =
                SurvivorEconomyBridge.processDiscordTip(
                        body.senderDiscordId(),
                        body.fromUsername(),
                        body.fromSteamId(),
                        body.currency(),
                        body.amount(),
                        body.recipientDiscordId());
        if (!result.ok()) {
            event.sendJson(
                    400,
                    MAPPER.writeValueAsString(DiscordTipResponse.failure(result.failureReason())));
            return;
        }
        event.sendJson(
                200, MAPPER.writeValueAsString(DiscordTipResponse.success(result.eventId())));
    }

    /**
     * Per-currency escrow wallet balances for the Discord user, read from the synthetic identity's
     * row in {@code economy_balance}. Query: {@code discordId} (required).
     */
    @HttpEndpoint(path = "/economy/discord/wallet")
    public static void wallet(HttpRequestEvent event) throws IOException {
        Map<String, String> params = event.getQueryParams();
        String discordId = trimToNull(params.get("discordId"));
        if (discordId == null) {
            event.sendJson(
                    400,
                    MAPPER.writeValueAsString(SqlExecutionResponse.error("Missing discordId.")));
            return;
        }
        Map<String, Double> totals = SurvivorEconomyBridge.getDiscordWalletBalances(discordId);
        List<BalanceDTO> balances = new ArrayList<>(totals.size());
        for (Map.Entry<String, Double> e : totals.entrySet()) {
            balances.add(new BalanceDTO(e.getKey(), e.getValue()));
        }
        event.sendJson(
                200, MAPPER.writeValueAsString(new DiscordWalletResponse(discordId, balances)));
    }

    private static String trimToNull(String raw) {
        if (raw == null) {
            return null;
        }
        String trimmed = raw.trim();
        if (trimmed.isEmpty()) {
            return null;
        }
        return trimmed;
    }
}
