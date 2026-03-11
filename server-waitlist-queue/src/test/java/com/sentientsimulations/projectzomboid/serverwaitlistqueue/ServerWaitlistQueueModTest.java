package com.sentientsimulations.projectzomboid.serverwaitlistqueue;

import static org.junit.jupiter.api.Assertions.*;

import io.pzstorm.storm.core.StormClassTransformer;
import java.util.List;
import org.junit.jupiter.api.Test;

class ServerWaitlistQueueModTest {

    @Test
    void shouldReturnTransformersOnServer() {
        System.setProperty("storm.server", "true");
        try {
            ServerWaitlistQueueMod mod = new ServerWaitlistQueueMod();
            List<StormClassTransformer> transformers = mod.getClassTransformers();

            assertEquals(1, transformers.size());
            assertInstanceOf(GameServerPatch.class, transformers.get(0));
        } finally {
            System.clearProperty("storm.server");
        }
    }

    @Test
    void shouldReturnNoTransformersOnClient() {
        System.clearProperty("storm.server");

        ServerWaitlistQueueMod mod = new ServerWaitlistQueueMod();
        List<StormClassTransformer> transformers = mod.getClassTransformers();

        assertTrue(transformers.isEmpty());
    }

    @Test
    void gameServerPatchTargetsCorrectClass() {
        GameServerPatch patch = new GameServerPatch();
        assertEquals("zombie.network.GameServer", patch.getClassName());
    }
}
