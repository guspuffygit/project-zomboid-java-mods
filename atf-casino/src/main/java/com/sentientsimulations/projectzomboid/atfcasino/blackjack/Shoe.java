package com.sentientsimulations.projectzomboid.atfcasino.blackjack;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Random;

/** Multi-deck dealing shoe that reshuffles once it runs below a cut-card threshold. */
public final class Shoe {

    private static final int DECKS = 6;
    private static final int CUT_CARD = 78;

    private final Random rng;
    private final List<Card> cards = new ArrayList<>();

    public Shoe(Random rng) {
        this.rng = rng;
        shuffle();
    }

    public Card draw() {
        if (cards.isEmpty()) {
            shuffle();
        }
        return cards.remove(cards.size() - 1);
    }

    /** Reshuffle between rounds once the shoe is past the cut card, like a real table. */
    public void reshuffleIfLow() {
        if (cards.size() < CUT_CARD) {
            shuffle();
        }
    }

    public int remaining() {
        return cards.size();
    }

    private void shuffle() {
        cards.clear();
        for (int d = 0; d < DECKS; d++) {
            for (char suit : new char[] {'s', 'h', 'd', 'c'}) {
                for (int rank = 1; rank <= 13; rank++) {
                    cards.add(new Card(rank, suit));
                }
            }
        }
        Collections.shuffle(cards, rng);
    }
}
