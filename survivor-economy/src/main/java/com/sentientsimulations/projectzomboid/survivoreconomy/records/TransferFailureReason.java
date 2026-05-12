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
    DISABLED,
    /** Sender's chosen character is not linked to their Discord account. */
    SENDER_NOT_LINKED,
    /** The claiming character is not linked to the Discord wallet being pulled from. */
    NOT_LINKED
}
