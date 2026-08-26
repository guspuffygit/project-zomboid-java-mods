package com.sentientsimulations.projectzomboid.atfcasino.blackjack;

/**
 * One playing card. {@code rank} is 1 (ace) .. 13 (king); {@code suit} is one of {@code s h d c}.
 * {@link #code()} is the wire form the client renders, e.g. {@code "As"}, {@code "10h"}, {@code
 * "Kd"}.
 */
public record Card(int rank, char suit) {

    public static final String RANKS = "A23456789TJQK";

    public Card {
        if (rank < 1 || rank > 13) {
            throw new IllegalArgumentException("rank " + rank);
        }
        if ("shdc".indexOf(suit) < 0) {
            throw new IllegalArgumentException("suit " + suit);
        }
    }

    /** Blackjack pip value with the ace counted low; {@link Hand} promotes one ace to 11. */
    public int value() {
        return Math.min(rank, 10);
    }

    public boolean isAce() {
        return rank == 1;
    }

    public String code() {
        String r = rank == 10 ? "10" : String.valueOf(RANKS.charAt(rank - 1));
        return r + suit;
    }

    @Override
    public String toString() {
        return code();
    }
}
