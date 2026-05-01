package com.sentientsimulations.projectzomboid.survivoreconomy.records;

import java.util.List;

public record BalanceResponse(String username, long steamId, List<BalanceDTO> balances) {}
