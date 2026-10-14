package com.sentientsimulations.projectzomboid;

import static org.junit.jupiter.api.Assertions.*;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;
import org.json.JSONObject;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

/**
 * Verifies our UI_GameLoad overrides format through Translator. Its formatFixer turns %1 into %1$s
 * and leaves every other percent sign alone, so a literal percent sign must be written %%.
 */
class TranslatorFormatTest {

    private static final Map<String, String> fixedStrings = new HashMap<>();

    private static final Pattern FORMAT_TOKEN = Pattern.compile("%%|%([1-9])");

    /** Mirrors Translator.formatFixer, applied to every translation string at load. */
    private static String applyTranslatorEscaping(String raw) {
        return FORMAT_TOKEN
                .matcher(raw)
                .replaceAll(m -> m.group(1) == null ? "%%" : "%" + m.group(1) + "\\$s");
    }

    @BeforeAll
    static void loadStrings() throws IOException {
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
    void fixedPlaceInQueue_works() {
        String escaped = applyTranslatorEscaping(fixedStrings.get("UI_GameLoad_PlaceInQueue"));
        String result = String.format(escaped, 3);
        assertEquals("You occupy position 3 in the connection queue", result);
    }

    @Test
    void fixedPlayerPopulation_works() {
        String escaped = applyTranslatorEscaping(fixedStrings.get("UI_GameLoad_PlayerPopulation"));
        String result = String.format(escaped, 5, 10);
        assertEquals("Player population 5/10", result);
    }

    @Test
    void fixedTime_works() {
        String escaped = applyTranslatorEscaping(fixedStrings.get("UI_GameLoad_time"));
        String result = String.format(escaped, 14, 30);
        assertEquals("Current time: 14:30", result);
    }

    @Test
    void fixedTemperature_works() {
        String escaped = applyTranslatorEscaping(fixedStrings.get("UI_GameLoad_temperature"));
        String result = String.format(escaped, 23.5f);
        assertEquals("Temperature: 23.5 ºC", result);
    }

    @Test
    void fixedHumidity_works() {
        String escaped = applyTranslatorEscaping(fixedStrings.get("UI_GameLoad_humidity"));
        String result = String.format(escaped, 67.3f);
        assertEquals("Humidity: 67.3 %", result);
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
