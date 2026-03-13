package com.sentientsimulations.projectzomboid.mapmetasqlite;

import static org.junit.jupiter.api.Assertions.*;

import io.pzstorm.storm.core.StormClassTransformer;
import java.util.List;
import org.junit.jupiter.api.Test;

class MapMetaSqliteModTest {

    @Test
    void shouldReturnTransformersOnServer() {
        System.setProperty("storm.server", "true");
        try {
            MapMetaSqliteMod mod = new MapMetaSqliteMod();
            List<StormClassTransformer> transformers = mod.getClassTransformers();

            assertEquals(1, transformers.size());
            assertInstanceOf(IsoMetaGridPatch.class, transformers.getFirst());
        } finally {
            System.clearProperty("storm.server");
        }
    }

    @Test
    void shouldReturnEmptyTransformersOnClient() {
        System.clearProperty("storm.server");
        MapMetaSqliteMod mod = new MapMetaSqliteMod();
        List<StormClassTransformer> transformers = mod.getClassTransformers();

        assertTrue(transformers.isEmpty());
    }
}
