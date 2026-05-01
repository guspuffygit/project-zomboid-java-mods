package com.sentientsimulations.projectzomboid.survivoreconomy;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.BalanceDTO;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.BalanceResponse;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.SqlExecutionResponse;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.TransactionDTO;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.TransactionEntry;
import com.sentientsimulations.projectzomboid.survivoreconomy.records.TransactionsResponse;
import io.pzstorm.storm.http.HttpEndpoint;
import io.pzstorm.storm.http.HttpRequestEvent;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.jspecify.annotations.Nullable;

public class SurvivorEconomyEndpoints {

    static final int DEFAULT_LIMIT = 50;
    static final int MAX_LIMIT = 1000;

    private static final ObjectMapper MAPPER = new ObjectMapper();

    @HttpEndpoint(path = "/economy/transactions")
    public static void transactions(HttpRequestEvent event) throws IOException {
        Map<String, String> params = event.getQueryParams();
        int limit = parseLimit(params.get("limit"));
        String username = parseStringParam(params.get("username"));
        String type = parseStringParam(params.get("type"));
        Long steamId;
        try {
            steamId = parseSteamIdParam(params.get("steamId"));
        } catch (NumberFormatException e) {
            sendInvalidSteamId(event);
            return;
        }

        List<TransactionEntry> rows =
                SurvivorEconomyBridge.listTransactions(limit, username, steamId, type);
        List<TransactionDTO> entries = rows.stream().map(TransactionDTO::from).toList();
        event.sendJson(200, MAPPER.writeValueAsString(new TransactionsResponse(entries)));
    }

    @HttpEndpoint(path = "/economy/balance")
    public static void balance(HttpRequestEvent event) throws IOException {
        Map<String, String> params = event.getQueryParams();
        String username = parseStringParam(params.get("username"));
        Long steamId;
        try {
            steamId = parseSteamIdParam(params.get("steamId"));
        } catch (NumberFormatException e) {
            sendInvalidSteamId(event);
            return;
        }
        if (username == null || steamId == null) {
            event.sendJson(
                    400,
                    MAPPER.writeValueAsString(
                            SqlExecutionResponse.error("Both username and steamId are required.")));
            return;
        }

        Map<String, Double> totals = SurvivorEconomyBridge.getBalances(username, steamId);
        List<BalanceDTO> balances = new ArrayList<>(totals.size());
        for (Map.Entry<String, Double> e : totals.entrySet()) {
            balances.add(new BalanceDTO(e.getKey(), e.getValue()));
        }
        event.sendJson(
                200, MAPPER.writeValueAsString(new BalanceResponse(username, steamId, balances)));
    }

    @HttpEndpoint(path = "/economy/event")
    public static void eventLookup(HttpRequestEvent event) throws IOException {
        Map<String, String> params = event.getQueryParams();
        String eventId = parseStringParam(params.get("eventId"));
        if (eventId == null) {
            event.sendJson(
                    400, MAPPER.writeValueAsString(SqlExecutionResponse.error("Missing eventId.")));
            return;
        }
        List<TransactionDTO> entries =
                SurvivorEconomyBridge.loadEvent(eventId).stream()
                        .map(TransactionDTO::from)
                        .toList();
        event.sendJson(200, MAPPER.writeValueAsString(new TransactionsResponse(entries)));
    }

    @HttpEndpoint(path = "/economy/sql")
    public static void sql(HttpRequestEvent event) throws IOException {
        String sql = event.getRequestBodyAsString();
        if (sql == null || sql.isBlank()) {
            sql = event.getQueryParams().get("sql");
        }
        if (sql == null || sql.isBlank()) {
            event.sendJson(
                    400,
                    MAPPER.writeValueAsString(
                            SqlExecutionResponse.error(
                                    "Missing SQL: provide in request body or ?sql= query"
                                            + " param.")));
            return;
        }
        SqlExecutionResponse response = SurvivorEconomyBridge.executeSql(sql);
        int status = response.error() != null ? 400 : 200;
        event.sendJson(status, MAPPER.writeValueAsString(response));
    }

    private static void sendInvalidSteamId(HttpRequestEvent event) throws IOException {
        event.sendJson(
                400,
                MAPPER.writeValueAsString(
                        SqlExecutionResponse.error("Invalid steamId: must be numeric.")));
    }

    static int parseLimit(String raw) {
        if (raw == null) return DEFAULT_LIMIT;
        try {
            int n = Integer.parseInt(raw.trim());
            if (n < 1) return DEFAULT_LIMIT;
            return Math.min(n, MAX_LIMIT);
        } catch (NumberFormatException e) {
            return DEFAULT_LIMIT;
        }
    }

    static @Nullable String parseStringParam(@Nullable String raw) {
        if (raw == null) return null;
        String trimmed = raw.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }

    static @Nullable Long parseSteamIdParam(@Nullable String raw) {
        if (raw == null) return null;
        String trimmed = raw.trim();
        if (trimmed.isEmpty()) return null;
        return Long.parseLong(trimmed);
    }
}
