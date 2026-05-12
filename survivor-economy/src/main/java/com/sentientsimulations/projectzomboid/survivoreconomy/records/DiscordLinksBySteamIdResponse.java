package com.sentientsimulations.projectzomboid.survivoreconomy.records;

import java.util.List;

public record DiscordLinksBySteamIdResponse(long steamId, List<DiscordLink> links) {}
