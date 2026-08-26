package com.sentientsimulations.projectzomboid.atfcasino.blackjack;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/** Cards held by one seat or the dealer, with blackjack scoring. */
public final class Hand {

    private final List<Card> cards = new ArrayList<>();

    public void add(Card card) {
        cards.add(card);
    }

    public void clear() {
        cards.clear();
    }

    public List<Card> cards() {
        return Collections.unmodifiableList(cards);
    }

    public int size() {
        return cards.size();
    }

    /** Best total: aces count 11 while that does not bust, otherwise 1. */
    public int total() {
        int total = 0;
        boolean hasAce = false;
        for (Card c : cards) {
            total += c.value();
            hasAce |= c.isAce();
        }
        if (hasAce && total + 10 <= 21) {
            total += 10;
        }
        return total;
    }

    /** True when an ace is currently being counted as 11. */
    public boolean isSoft() {
        int hard = 0;
        boolean hasAce = false;
        for (Card c : cards) {
            hard += c.value();
            hasAce |= c.isAce();
        }
        return hasAce && hard + 10 <= 21;
    }

    public boolean isBust() {
        return total() > 21;
    }

    /** A natural: exactly two cards totalling 21. */
    public boolean isBlackjack() {
        return cards.size() == 2 && total() == 21;
    }
}
