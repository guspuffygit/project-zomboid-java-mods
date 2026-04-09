package com.sentientsimulations.projectzomboid.survivorleaderboard.records;

public record ZoneRecord(
        long id,
        long categoryId,
        double xStart,
        double yStart,
        double xEnd,
        double yEnd,
        String region) {}
