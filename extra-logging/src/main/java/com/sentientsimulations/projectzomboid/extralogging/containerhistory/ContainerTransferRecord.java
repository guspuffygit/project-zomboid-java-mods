package com.sentientsimulations.projectzomboid.extralogging.containerhistory;

public record ContainerTransferRecord(
        long id,
        long ts,
        String playerUsername,
        String playerSteamId,
        String itemType,
        String itemName,
        int itemId,
        String srcRef,
        String destRef,
        String uuid) {}
