package com.sentientsimulations.projectzomboid.survivoreconomy.records;

/**
 * Reason a player→player transfer was rejected. Pure-logic rejections come from {@code
 * SurvivorEconomyTransfer.processTransfer}; bridge-level rejections are layered on top by {@code
 * SurvivorEconomyBridge.processTransfer} (range, online-state, sandbox toggle).
 */
public enum TransferFailureReason {
    INVALID_AMOUNT,
    SAME_PLAYER,
    INSUFFICIENT_BALANCE,
    TARGET_OFFLINE,
    OUT_OF_RANGE,
    DISABLED
}
