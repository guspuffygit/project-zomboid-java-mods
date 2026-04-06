package com.sentientsimulations.projectzomboid;

import static org.junit.jupiter.api.Assertions.*;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.json.JSONObject;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

/**
 * Reproduces the PZ Translator format-specifier bug and verifies our translation overrides fix it.
 *
 * <p>The game's Translator.tryFillMapFromFile() runs every translation string through: 1.
 * replaceAll("%", "%%") — escapes ALL percent signs 2. replaceAll("%%(\\d+)", "%$1\\$s") — converts
 * positional markers %%1 → %1$s
 *
 * <p>This means %d, %.1f, %s etc. get mangled into %%d, %%.1f, %%s which String.format() renders as
 * literal text. Only positional markers like %1, %2 survive the round-trip.
 */
class TranslatorFormatTest {

    private static final Map<String, String> vanillaStrings = new HashMap<>();
    private static final Map<String, String> fixedStrings = new HashMap<>();

    /** Simulates what Translator.tryFillMapFromFile() does to every translation string. */
    private static String applyTranslatorEscaping(String raw) {
        return raw.replaceAll("%", "%%").replaceAll("%%(\\d+)", "%$1\\$s");
    }

    @BeforeAll
    static void loadStrings() throws IOException {
        // Vanilla strings from the game's UI.json
        vanillaStrings.put(
                "UI_GameLoad_PlaceInQueue", "You occupy position %d in the connection queue");
        vanillaStrings.put("UI_GameLoad_PlayerPopulation", "Player population %d/%d");
        vanillaStrings.put(
                "UI_GameLoad_zombieKilledTodayN", "%d zombies killed on this server today.");
        vanillaStrings.put(
                "UI_GameLoad_zombifiedPlayersTodayN",
                "%d survivors turned into shambling corpses on this server today.");
        vanillaStrings.put(
                "UI_GameLoad_burnedZombiesTodayN",
                "%d zombie corpses burned on this server today.");
        vanillaStrings.put("UI_GameLoad_time", "Current data: %d:%d");
        vanillaStrings.put("UI_GameLoad_temperature", "Temperature: %.1f ºC");
        vanillaStrings.put("UI_GameLoad_humidity", "Humidity: %.1f %%");
        vanillaStrings.put("UI_GameLoad_windSpeed", "Wind: %s, %d knots, %d kph");

        // Load our fixed strings from the mod's UI.json
        Path uiJson = Path.of("common/media/lua/shared/Translate/EN/UI.json");
        assertTrue(
                Files.exists(uiJson), "Could not find mod UI.json at: " + uiJson.toAbsolutePath());
        String json = Files.readString(uiJson);
        JSONObject obj = new JSONObject(json);
        for (String key : obj.keySet()) {
            fixedStrings.put(key, obj.getString(key));
        }
    }

    @Test
    void vanillaPlaceInQueue_isBroken() {
        String escaped = applyTranslatorEscaping(vanillaStrings.get("UI_GameLoad_PlaceInQueue"));
        String result = String.format(escaped, 3);
        // %d got mangled — the number 3 never appears
        assertTrue(result.contains("%d"), "Should contain literal %%d but got: " + result);
        assertFalse(
                result.contains("3"), "Should NOT contain the formatted number but got: " + result);
    }

    @Test
    void fixedPlaceInQueue_works() {
        String escaped = applyTranslatorEscaping(fixedStrings.get("UI_GameLoad_PlaceInQueue"));
        String result = String.format(escaped, 3);
        assertEquals("You occupy position 3 in the connection queue", result);
    }

    @Test
    void vanillaPlayerPopulation_isBroken() {
        String escaped =
                applyTranslatorEscaping(vanillaStrings.get("UI_GameLoad_PlayerPopulation"));
        String result = String.format(escaped, 5, 10);
        assertTrue(result.contains("%d"), "Should contain literal %%d but got: " + result);
    }

    @Test
    void fixedPlayerPopulation_works() {
        String escaped = applyTranslatorEscaping(fixedStrings.get("UI_GameLoad_PlayerPopulation"));
        String result = String.format(escaped, 5, 10);
        assertEquals("Player population 5/10", result);
    }

    @Test
    void vanillaTime_isBroken() {
        String escaped = applyTranslatorEscaping(vanillaStrings.get("UI_GameLoad_time"));
        String result = String.format(escaped, 14, 30);
        assertTrue(result.contains("%d"), "Should contain literal %%d but got: " + result);
    }

    @Test
    void fixedTime_works() {
        String escaped = applyTranslatorEscaping(fixedStrings.get("UI_GameLoad_time"));
        String result = String.format(escaped, 14, 30);
        assertEquals("Current time: 14:30", result);
    }

    @Test
    void vanillaTemperature_isBroken() {
        String escaped = applyTranslatorEscaping(vanillaStrings.get("UI_GameLoad_temperature"));
        String result = String.format(escaped, 23.5f);
        assertTrue(
                result.contains("%.1f") || result.contains("%"),
                "Should be broken but got: " + result);
        assertFalse(
                result.contains("23"),
                "Should NOT contain the formatted number but got: " + result);
    }

    @Test
    void fixedTemperature_works() {
        String escaped = applyTranslatorEscaping(fixedStrings.get("UI_GameLoad_temperature"));
        String result = String.format(escaped, 23.5f);
        assertEquals("Temperature: 23.5 ºC", result);
    }

    @Test
    void vanillaHumidity_isBroken() {
        String escaped = applyTranslatorEscaping(vanillaStrings.get("UI_GameLoad_humidity"));
        String result = String.format(escaped, 67.3f);
        assertFalse(
                result.contains("67"),
                "Should NOT contain the formatted number but got: " + result);
    }

    @Test
    void fixedHumidity_works() {
        String escaped = applyTranslatorEscaping(fixedStrings.get("UI_GameLoad_humidity"));
        String result = String.format(escaped, 67.3f);
        assertEquals("Humidity: 67.3 %", result);
    }

    @Test
    void vanillaWindSpeed_isBroken() {
        String escaped = applyTranslatorEscaping(vanillaStrings.get("UI_GameLoad_windSpeed"));
        String result = String.format(escaped, "Gentle Breeze", 12, 22);
        assertTrue(
                result.contains("%s") || result.contains("%d"),
                "Should contain literal format specifiers but got: " + result);
    }

    @Test
    void fixedWindSpeed_works() {
        String escaped = applyTranslatorEscaping(fixedStrings.get("UI_GameLoad_windSpeed"));
        String result = String.format(escaped, "Gentle Breeze", 12, 22);
        assertEquals("Wind: Gentle Breeze, 12 knots, 22 kph", result);
    }

    @Test
    void allFixedStrings_surviveTranslatorEscaping() {
        List<String> keys =
                List.of(
                        "UI_GameLoad_PlaceInQueue",
                        "UI_GameLoad_PlayerPopulation",
                        "UI_GameLoad_zombieKilledTodayN",
                        "UI_GameLoad_zombifiedPlayersTodayN",
                        "UI_GameLoad_burnedZombiesTodayN",
                        "UI_GameLoad_time",
                        "UI_GameLoad_temperature",
                        "UI_GameLoad_humidity",
                        "UI_GameLoad_windSpeed");

        for (String key : keys) {
            String fixed = fixedStrings.get(key);
            assertNotNull(fixed, "Missing fixed string for key: " + key);

            String escaped = applyTranslatorEscaping(fixed);

            // After escaping, positional markers like %1 should become %1$s
            // No raw %d, %s, or %.1f should be present
            assertFalse(
                    escaped.matches(".*(?<!%)%[dfs].*"),
                    key + ": escaped string still contains raw format specifiers: " + escaped);
            assertFalse(
                    escaped.contains("%%."),
                    key + ": escaped string contains broken float specifier: " + escaped);
        }
    }
}
