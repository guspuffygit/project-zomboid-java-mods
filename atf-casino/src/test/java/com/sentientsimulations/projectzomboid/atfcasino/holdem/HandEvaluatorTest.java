package com.sentientsimulations.projectzomboid.atfcasino.holdem;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.sentientsimulations.projectzomboid.atfcasino.blackjack.Card;
import com.sentientsimulations.projectzomboid.atfcasino.holdem.HandEvaluator.HandValue;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

class HandEvaluatorTest {

    static List<Card> cards(String... codes) {
        List<Card> out = new ArrayList<>();
        for (String c : codes) {
            String r = c.substring(0, c.length() - 1);
            int rank =
                    switch (r) {
                        case "A" -> 1;
                        case "T", "10" -> 10;
                        case "J" -> 11;
                        case "Q" -> 12;
                        case "K" -> 13;
                        default -> Integer.parseInt(r);
                    };
            out.add(new Card(rank, c.charAt(c.length() - 1)));
        }
        return out;
    }

    private static HandValue v(String... codes) {
        return HandEvaluator.best(cards(codes));
    }

    @Test
    void namesEveryCategory() {
        assertEquals("Royal Flush", v("As", "Ks", "Qs", "Js", "Ts").name());
        assertEquals("Straight Flush, Nine high", v("9h", "8h", "7h", "6h", "5h").name());
        assertEquals("Four of a Kind, Sevens", v("7s", "7h", "7d", "7c", "Kd").name());
        assertEquals("Full House, Aces over Kings", v("As", "Ah", "Ad", "Ks", "Kd").name());
        assertEquals("Flush, King high", v("Kc", "9c", "7c", "4c", "2c").name());
        assertEquals("Straight, Ten high", v("Ts", "9h", "8d", "7c", "6s").name());
        assertEquals("Straight, Five high", v("As", "2h", "3d", "4c", "5s").name());
        assertEquals("Three of a Kind, Queens", v("Qs", "Qh", "Qd", "8c", "2s").name());
        assertEquals("Two Pair, Jacks and Sixes", v("Js", "Jh", "6d", "6c", "As").name());
        assertEquals("Pair of Twos", v("2s", "2h", "Ad", "Kc", "9s").name());
        assertEquals("Ace high", v("As", "Jh", "9d", "7c", "4s").name());
    }

    @Test
    void categoriesRankInOrder() {
        long[] scores = {
            v("As", "Jh", "9d", "7c", "4s").score(),
            v("2s", "2h", "Ad", "Kc", "9s").score(),
            v("Js", "Jh", "6d", "6c", "As").score(),
            v("Qs", "Qh", "Qd", "8c", "2s").score(),
            v("As", "2h", "3d", "4c", "5s").score(),
            v("Kc", "9c", "7c", "4c", "2c").score(),
            v("As", "Ah", "Ad", "Ks", "Kd").score(),
            v("7s", "7h", "7d", "7c", "Kd").score(),
            v("9h", "8h", "7h", "6h", "5h").score(),
            v("As", "Ks", "Qs", "Js", "Ts").score(),
        };
        for (int i = 1; i < scores.length; i++) {
            assertTrue(scores[i] > scores[i - 1], "index " + i);
        }
    }

    @Test
    void kickersBreakTies() {
        assertTrue(
                v("As", "Ah", "Kd", "9c", "2s").score() > v("Ad", "Ac", "Qd", "Jc", "Ts").score());
        assertTrue(
                v("9s", "8h", "7d", "6c", "5s").score() > v("As", "2h", "3d", "4c", "5d").score());
        assertEquals(
                v("Ks", "Kh", "9d", "5c", "2s").score(), v("Kd", "Kc", "9h", "5d", "2h").score());
    }

    @Test
    void picksBestFiveOfSeven() {
        HandValue hv = v("As", "Ad", "3h", "5d", "8c", "9s", "Jh");
        assertEquals("Pair of Aces", hv.name());
        HandValue flush = v("2c", "9c", "Kh", "Kd", "4c", "Jc", "7c");
        assertEquals("Flush, Jack high", flush.name());
        HandValue straight = v("Ah", "Kd", "Qc", "Js", "Th", "2c", "2d");
        assertEquals("Straight, Ace high", straight.name());
        HandValue six = v("Qs", "Qh", "Qd", "8c", "8s", "2d");
        assertEquals("Full House, Queens over Eights", six.name());
    }
}
