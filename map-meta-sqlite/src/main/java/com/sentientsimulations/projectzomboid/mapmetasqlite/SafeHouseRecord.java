package com.sentientsimulations.projectzomboid.mapmetasqlite;

import java.util.List;

public record SafeHouseRecord(
        int x,
        int y,
        int w,
        int h,
        String owner,
        int hitPoints,
        List<String> players,
        long lastVisited,
        String title,
        long datetimeCreated,
        String location,
        List<String> playersRespawn) {}
