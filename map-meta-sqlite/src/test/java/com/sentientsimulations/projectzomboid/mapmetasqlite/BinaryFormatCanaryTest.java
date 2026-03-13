package com.sentientsimulations.projectzomboid.mapmetasqlite;

import static org.junit.jupiter.api.Assertions.*;

import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.util.Map;
import java.util.TreeMap;
import java.util.stream.Collectors;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;

/**
 * Canary test that uses reflection to verify the Project Zomboid game classes serialized into
 * map_meta.bin still have the fields our parser expects. If a PZ update adds, removes, renames, or
 * retypes a field, this test fails — signalling that {@link MapMetaBinParser} may need updating.
 *
 * <p>Only non-static, non-synthetic declared fields are checked, since static fields (like list
 * singletons) are not part of the binary serialization.
 */
class BinaryFormatCanaryTest {

    /**
     * Returns a sorted map of field-name → type-name for all non-static, non-synthetic declared
     * fields.
     */
    private static Map<String, String> instanceFields(Class<?> clazz) {
        return Stream.of(clazz.getDeclaredFields())
                .filter(f -> !Modifier.isStatic(f.getModifiers()))
                .filter(f -> !f.isSynthetic())
                .collect(
                        Collectors.toMap(
                                Field::getName,
                                f -> f.getType().getName(),
                                (a, b) -> a,
                                TreeMap::new));
    }

    @Test
    void safeHouseFields() throws ClassNotFoundException {
        Class<?> clazz = Class.forName("zombie.iso.areas.SafeHouse");
        Map<String, String> fields = instanceFields(clazz);

        Map<String, String> expected =
                new TreeMap<>(
                        Map.ofEntries(
                                Map.entry("x", "int"),
                                Map.entry("y", "int"),
                                Map.entry("w", "int"),
                                Map.entry("h", "int"),
                                Map.entry("owner", "java.lang.String"),
                                Map.entry("lastVisited", "long"),
                                Map.entry("datetimeCreated", "long"),
                                Map.entry("location", "java.lang.String"),
                                Map.entry("title", "java.lang.String"),
                                Map.entry("playerConnected", "int"),
                                Map.entry("openTimer", "int"),
                                Map.entry("hitPoints", "int"),
                                Map.entry("id", "java.lang.String"),
                                Map.entry("players", "java.util.ArrayList"),
                                Map.entry("playersRespawn", "java.util.ArrayList"),
                                Map.entry("onlineId", "int")));

        assertEquals(
                expected, fields, "SafeHouse fields changed — MapMetaBinParser may need updating");
    }

    @Test
    void nonPvpZoneFields() throws ClassNotFoundException {
        Class<?> clazz = Class.forName("zombie.iso.areas.NonPvpZone");
        Map<String, String> fields = instanceFields(clazz);

        Map<String, String> expected =
                new TreeMap<>(
                        Map.ofEntries(
                                Map.entry("x", "int"),
                                Map.entry("y", "int"),
                                Map.entry("x2", "int"),
                                Map.entry("y2", "int"),
                                Map.entry("size", "int"),
                                Map.entry("title", "java.lang.String")));

        assertEquals(
                expected, fields, "NonPvpZone fields changed — MapMetaBinParser may need updating");
    }

    @Test
    void factionFields() throws ClassNotFoundException {
        Class<?> clazz = Class.forName("zombie.characters.Faction");
        Map<String, String> fields = instanceFields(clazz);

        Map<String, String> expected =
                new TreeMap<>(
                        Map.ofEntries(
                                Map.entry("name", "java.lang.String"),
                                Map.entry("owner", "java.lang.String"),
                                Map.entry("tag", "java.lang.String"),
                                Map.entry("tagColor", "zombie.core.textures.ColorInfo"),
                                Map.entry("players", "java.util.ArrayList")));

        assertEquals(
                expected, fields, "Faction fields changed — MapMetaBinParser may need updating");
    }

    @Test
    void designationZoneFields() throws ClassNotFoundException {
        Class<?> clazz = Class.forName("zombie.iso.areas.DesignationZone");
        Map<String, String> fields = instanceFields(clazz);

        Map<String, String> expected =
                new TreeMap<>(
                        Map.ofEntries(
                                Map.entry("id", "java.lang.Double"),
                                Map.entry("hourLastSeen", "int"),
                                Map.entry("lastActionTimestamp", "int"),
                                Map.entry("name", "java.lang.String"),
                                Map.entry("type", "java.lang.String"),
                                Map.entry("x", "int"),
                                Map.entry("y", "int"),
                                Map.entry("z", "int"),
                                Map.entry("w", "int"),
                                Map.entry("h", "int"),
                                Map.entry("streamed", "boolean")));

        assertEquals(
                expected,
                fields,
                "DesignationZone fields changed — MapMetaBinParser may need updating");
    }

    @Test
    void stashBuildingFields() throws ClassNotFoundException {
        Class<?> clazz = Class.forName("zombie.core.stash.StashBuilding");
        Map<String, String> fields = instanceFields(clazz);

        Map<String, String> expected =
                new TreeMap<>(
                        Map.ofEntries(
                                Map.entry("buildingX", "int"),
                                Map.entry("buildingY", "int"),
                                Map.entry("stashName", "java.lang.String")));

        assertEquals(
                expected,
                fields,
                "StashBuilding fields changed — MapMetaBinParser may need updating");
    }
}
