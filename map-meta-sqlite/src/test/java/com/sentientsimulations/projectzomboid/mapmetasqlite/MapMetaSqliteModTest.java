package com.sentientsimulations.projectzomboid.mapmetasqlite;

import static org.junit.jupiter.api.Assertions.*;

import io.pzstorm.storm.core.StormClassTransformer;
import java.util.List;
import org.junit.jupiter.api.Test;

class MapMetaSqliteModTest {

    @Test
    void shouldLoadMod() {
        MapMetaSqliteMod mod = new MapMetaSqliteMod();
        List<StormClassTransformer> transformers = mod.getClassTransformers();

        assertTrue(transformers.isEmpty());
    }
}
