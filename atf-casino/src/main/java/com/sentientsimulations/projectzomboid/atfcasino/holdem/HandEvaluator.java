package com.sentientsimulations.projectzomboid.atfcasino.holdem;

import com.sentientsimulations.projectzomboid.atfcasino.blackjack.Card;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * Ranks poker hands. {@link #best(List)} takes 5..7 cards (hole cards + board) and returns the
 * strongest five-card hand as a comparable score plus a human-readable name ("Full House, Aces over
 * Kings"). Aces are high except in the wheel (A-2-3-4-5).
 */
public final class HandEvaluator {

    private static final int CATEGORY_SHIFT = 20;
    private static final String[] NAMES = {
        null, null, "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Jack",
        "Queen", "King", "Ace"
    };

    /** Higher {@code score} beats lower; equal scores split. */
    public record HandValue(long score, String name) implements Comparable<HandValue> {
        @Override
        public int compareTo(HandValue o) {
            return Long.compare(score, o.score);
        }
    }

    private HandEvaluator() {}

    public static HandValue best(List<Card> cards) {
        int n = cards.size();
        if (n < 5 || n > 7) {
            throw new IllegalArgumentException("need 5..7 cards, got " + n);
        }
        Card[] all = cards.toArray(new Card[0]);
        if (n == 5) {
            return evaluate5(all);
        }
        HandValue best = null;
        // Drop one card (6) or two cards (7) in every way and keep the strongest five.
        int dropped = n - 5;
        for (int a = 0; a < n; a++) {
            for (int b = a + 1; b <= n; b++) {
                if (dropped == 1 && b != n) {
                    continue;
                }
                if (dropped == 2 && b == n) {
                    continue;
                }
                HandValue v = evaluate5(without(all, a, b));
                if (best == null || v.score > best.score) {
                    best = v;
                }
            }
        }
        return best;
    }

    private static Card[] without(Card[] all, int a, int b) {
        Card[] five = new Card[5];
        int k = 0;
        for (int i = 0; i < all.length; i++) {
            if (i == a || i == b) {
                continue;
            }
            five[k++] = all[i];
        }
        return five;
    }

    static HandValue evaluate5(Card[] five) {
        int[] values = new int[5];
        boolean flush = true;
        for (int i = 0; i < 5; i++) {
            values[i] = highValue(five[i]);
            if (five[i].suit() != five[0].suit()) {
                flush = false;
            }
        }
        Arrays.sort(values);
        // descending
        for (int i = 0; i < 2; i++) {
            int t = values[i];
            values[i] = values[4 - i];
            values[4 - i] = t;
        }
        int straightHigh = straightHigh(values);

        // group by count
        List<int[]> groups = new ArrayList<>(); // {value, count}
        for (int v : values) {
            boolean found = false;
            for (int[] g : groups) {
                if (g[0] == v) {
                    g[1]++;
                    found = true;
                    break;
                }
            }
            if (!found) {
                groups.add(new int[] {v, 1});
            }
        }
        // count desc, then value desc
        groups.sort((x, y) -> x[1] != y[1] ? y[1] - x[1] : y[0] - x[0]);

        if (straightHigh > 0 && flush) {
            String name =
                    straightHigh == 14
                            ? "Royal Flush"
                            : "Straight Flush, " + NAMES[straightHigh] + " high";
            return new HandValue(score(8, straightHigh, 0, 0, 0, 0), name);
        }
        if (groups.get(0)[1] == 4) {
            int q = groups.get(0)[0];
            int k = groups.get(1)[0];
            return new HandValue(score(7, q, k, 0, 0, 0), "Four of a Kind, " + plural(q));
        }
        if (groups.get(0)[1] == 3 && groups.get(1)[1] == 2) {
            int t = groups.get(0)[0];
            int p = groups.get(1)[0];
            return new HandValue(
                    score(6, t, p, 0, 0, 0), "Full House, " + plural(t) + " over " + plural(p));
        }
        if (flush) {
            return new HandValue(
                    score(5, values[0], values[1], values[2], values[3], values[4]),
                    "Flush, " + NAMES[values[0]] + " high");
        }
        if (straightHigh > 0) {
            return new HandValue(
                    score(4, straightHigh, 0, 0, 0, 0),
                    "Straight, " + NAMES[straightHigh] + " high");
        }
        if (groups.get(0)[1] == 3) {
            int t = groups.get(0)[0];
            return new HandValue(
                    score(3, t, groups.get(1)[0], groups.get(2)[0], 0, 0),
                    "Three of a Kind, " + plural(t));
        }
        if (groups.get(0)[1] == 2 && groups.get(1)[1] == 2) {
            int hp = groups.get(0)[0];
            int lp = groups.get(1)[0];
            return new HandValue(
                    score(2, hp, lp, groups.get(2)[0], 0, 0),
                    "Two Pair, " + plural(hp) + " and " + plural(lp));
        }
        if (groups.get(0)[1] == 2) {
            int p = groups.get(0)[0];
            return new HandValue(
                    score(1, p, groups.get(1)[0], groups.get(2)[0], groups.get(3)[0], 0),
                    "Pair of " + plural(p));
        }
        return new HandValue(
                score(0, values[0], values[1], values[2], values[3], values[4]),
                NAMES[values[0]] + " high");
    }

    /** Ace counts 14 here; {@link Card#rank()} stores it as 1. */
    static int highValue(Card c) {
        return c.rank() == 1 ? 14 : c.rank();
    }

    /** High card of the straight formed by {@code desc} (five values, descending), else 0. */
    private static int straightHigh(int[] desc) {
        boolean run = true;
        for (int i = 1; i < 5; i++) {
            if (desc[i] != desc[i - 1] - 1) {
                run = false;
                break;
            }
        }
        if (run) {
            return desc[0];
        }
        if (desc[0] == 14 && desc[1] == 5 && desc[2] == 4 && desc[3] == 3 && desc[4] == 2) {
            return 5;
        }
        return 0;
    }

    private static long score(int category, int a, int b, int c, int d, int e) {
        return ((long) category << CATEGORY_SHIFT)
                | ((long) a << 16)
                | ((long) b << 12)
                | ((long) c << 8)
                | ((long) d << 4)
                | e;
    }

    static String plural(int value) {
        String n = NAMES[value];
        return n.equals("Six") ? "Sixes" : n + "s";
    }
}
