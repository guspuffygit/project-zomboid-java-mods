package com.sentientsimulations.projectzomboid.survivoreconomy.records;

/**
 * Result of a successful zombie-bounty payout. Returned by {@code
 * SurvivorEconomyZombieBounty.processKill} when a row is inserted, and consumed by the bridge to
 * include the amount in the server→client {@code zombieBountyPaid} command without re-querying.
 */
public record BountyResult(String eventId, int amount) {}
