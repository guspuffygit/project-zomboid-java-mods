package com.sentientsimulations.projectzomboid.survivorleaderboard;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.sentientsimulations.projectzomboid.survivorleaderboard.records.KillLeaderboardResponse;
import com.sentientsimulations.projectzomboid.survivorleaderboard.records.KillerDTO;
import com.sentientsimulations.projectzomboid.survivorleaderboard.records.SurvivorDTO;
import com.sentientsimulations.projectzomboid.survivorleaderboard.records.SurvivorLeaderboardResponse;
import io.pzstorm.storm.http.HttpEndpoint;
import io.pzstorm.storm.http.HttpRequestEvent;
import java.io.IOException;
import java.util.List;

public class SurvivorLeaderboardEndpoints {

    static final int DEFAULT_LIMIT = 10;

    private static final ObjectMapper MAPPER = new ObjectMapper();

    @HttpEndpoint(path = "/leaderboard/survivors")
    public static void survivors(HttpRequestEvent event) throws IOException {
        int limit = parseLimit(event.getQueryParams().get("limit"));

        List<SurvivorDTO> top =
                SurvivorLeaderboardBridge.listSurvivors().stream()
                        .limit(limit)
                        .map(r -> new SurvivorDTO(r.username(), r.dayCount(), r.steamId()))
                        .toList();

        event.sendJson(200, MAPPER.writeValueAsString(new SurvivorLeaderboardResponse(top)));
    }

    @HttpEndpoint(path = "/leaderboard/killers")
    public static void killers(HttpRequestEvent event) throws IOException {
        int limit = parseLimit(event.getQueryParams().get("limit"));

        List<KillerDTO> top =
                SurvivorLeaderboardBridge.listKillers().stream()
                        .limit(limit)
                        .map(r -> new KillerDTO(r.username(), r.killCount(), r.steamId()))
                        .toList();

        event.sendJson(200, MAPPER.writeValueAsString(new KillLeaderboardResponse(top)));
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
}
