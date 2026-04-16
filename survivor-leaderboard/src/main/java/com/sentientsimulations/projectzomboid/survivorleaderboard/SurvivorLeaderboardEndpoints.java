package com.sentientsimulations.projectzomboid.survivorleaderboard;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.sentientsimulations.projectzomboid.survivorleaderboard.records.KillLeaderboardResponse;
import com.sentientsimulations.projectzomboid.survivorleaderboard.records.KillLogDTO;
import com.sentientsimulations.projectzomboid.survivorleaderboard.records.KillLogResponse;
import com.sentientsimulations.projectzomboid.survivorleaderboard.records.KillerDTO;
import com.sentientsimulations.projectzomboid.survivorleaderboard.records.SqlExecutionResponse;
import com.sentientsimulations.projectzomboid.survivorleaderboard.records.SurvivorDTO;
import com.sentientsimulations.projectzomboid.survivorleaderboard.records.SurvivorLeaderboardResponse;
import com.sentientsimulations.projectzomboid.survivorleaderboard.records.ZombieKillerDTO;
import com.sentientsimulations.projectzomboid.survivorleaderboard.records.ZombieLeaderboardResponse;
import io.pzstorm.storm.http.HttpEndpoint;
import io.pzstorm.storm.http.HttpRequestEvent;
import java.io.IOException;
import java.util.List;
import java.util.Map;
import org.jspecify.annotations.Nullable;

public class SurvivorLeaderboardEndpoints {

    static final int DEFAULT_LIMIT = 10;
    static final int KILL_LOG_DEFAULT_LIMIT = 50;
    static final int KILL_LOG_MAX_LIMIT = 500;

    private static final ObjectMapper MAPPER = new ObjectMapper();

    @HttpEndpoint(path = "/leaderboard/survivors")
    public static void survivors(HttpRequestEvent event) throws IOException {
        Map<String, String> params = event.getQueryParams();
        int limit = parseLimit(params.get("limit"));
        String username = parseUsernameParam(params.get("username"));
        Long steamId;
        try {
            steamId = parseSteamIdParam(params.get("steamId"));
        } catch (NumberFormatException e) {
            sendInvalidSteamId(event);
            return;
        }

        List<SurvivorDTO> top =
                SurvivorLeaderboardBridge.listSurvivors(username, steamId).stream()
                        .limit(limit)
                        .map(r -> new SurvivorDTO(r.username(), r.dayCount(), r.steamId()))
                        .toList();

        event.sendJson(200, MAPPER.writeValueAsString(new SurvivorLeaderboardResponse(top)));
    }

    @HttpEndpoint(path = "/leaderboard/killers")
    public static void killers(HttpRequestEvent event) throws IOException {
        Map<String, String> params = event.getQueryParams();
        int limit = parseLimit(params.get("limit"));
        String username = parseUsernameParam(params.get("username"));
        Long steamId;
        try {
            steamId = parseSteamIdParam(params.get("steamId"));
        } catch (NumberFormatException e) {
            sendInvalidSteamId(event);
            return;
        }

        List<KillerDTO> top =
                SurvivorLeaderboardBridge.listKillers(username, steamId).stream()
                        .limit(limit)
                        .map(r -> new KillerDTO(r.username(), r.killCount(), r.steamId()))
                        .toList();

        event.sendJson(200, MAPPER.writeValueAsString(new KillLeaderboardResponse(top)));
    }

    @HttpEndpoint(path = "/leaderboard/zombies")
    public static void zombies(HttpRequestEvent event) throws IOException {
        Map<String, String> params = event.getQueryParams();
        int limit = parseLimit(params.get("limit"));
        String username = parseUsernameParam(params.get("username"));
        Long steamId;
        try {
            steamId = parseSteamIdParam(params.get("steamId"));
        } catch (NumberFormatException e) {
            sendInvalidSteamId(event);
            return;
        }

        List<ZombieKillerDTO> top =
                SurvivorLeaderboardBridge.listZombieKillers(username, steamId).stream()
                        .limit(limit)
                        .map(r -> new ZombieKillerDTO(r.username(), r.zombieKills(), r.steamId()))
                        .toList();

        event.sendJson(200, MAPPER.writeValueAsString(new ZombieLeaderboardResponse(top)));
    }

    @HttpEndpoint(path = "/leaderboard/kills")
    public static void kills(HttpRequestEvent event) throws IOException {
        Map<String, String> params = event.getQueryParams();
        int limit = parseLimit(params.get("limit"), KILL_LOG_DEFAULT_LIMIT, KILL_LOG_MAX_LIMIT);
        String username = parseUsernameParam(params.get("username"));
        Long steamId;
        try {
            steamId = parseSteamIdParam(params.get("steamId"));
        } catch (NumberFormatException e) {
            sendInvalidSteamId(event);
            return;
        }

        List<KillLogDTO> entries =
                SurvivorLeaderboardBridge.listKills(limit, username, steamId).stream()
                        .map(
                                k ->
                                        new KillLogDTO(
                                                k.killerSteamId(),
                                                k.killerUsername(),
                                                k.victimSteamId(),
                                                k.victimUsername(),
                                                k.isAlly(),
                                                k.createdAt()))
                        .toList();

        event.sendJson(200, MAPPER.writeValueAsString(new KillLogResponse(entries)));
    }

    private static void sendInvalidSteamId(HttpRequestEvent event) throws IOException {
        event.sendJson(
                400,
                MAPPER.writeValueAsString(
                        SqlExecutionResponse.error("Invalid steamId: must be numeric.")));
    }

    @HttpEndpoint(path = "/leaderboard/sql")
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
                                    "Missing SQL: provide in request body or ?sql= query param.")));
            return;
        }

        SqlExecutionResponse response = SurvivorLeaderboardBridge.executeSql(sql);
        int status = response.error() != null ? 400 : 200;
        event.sendJson(status, MAPPER.writeValueAsString(response));
    }

    static int parseLimit(String raw) {
        if (raw == null) {
            return DEFAULT_LIMIT;
        }
        try {
            int n = Integer.parseInt(raw.trim());
            return n >= 1 ? n : DEFAULT_LIMIT;
        } catch (NumberFormatException e) {
            return DEFAULT_LIMIT;
        }
    }

    static int parseLimit(String raw, int defaultLimit, int maxLimit) {
        if (raw == null) {
            return defaultLimit;
        }
        try {
            int n = Integer.parseInt(raw.trim());
            if (n < 1) return defaultLimit;
            return Math.min(n, maxLimit);
        } catch (NumberFormatException e) {
            return defaultLimit;
        }
    }

    /** null/blank → null (no filter); otherwise the trimmed value. */
    static @Nullable String parseUsernameParam(@Nullable String raw) {
        if (raw == null) {
            return null;
        }
        String trimmed = raw.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }

    /**
     * null/blank → null (no filter). A non-blank value that is not a valid {@code long} throws
     * {@link NumberFormatException} so callers can return 400.
     */
    static @Nullable Long parseSteamIdParam(@Nullable String raw) {
        if (raw == null) {
            return null;
        }
        String trimmed = raw.trim();
        if (trimmed.isEmpty()) {
            return null;
        }
        return Long.parseLong(trimmed);
    }
}
