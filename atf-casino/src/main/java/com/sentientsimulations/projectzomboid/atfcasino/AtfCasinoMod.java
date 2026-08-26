package com.sentientsimulations.projectzomboid.atfcasino;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.atfcasino.npc.CasinoNpcManager;
import com.sentientsimulations.projectzomboid.atfcasino.patch.PlayerHitPlayerPacketParsePatch;
import io.pzstorm.storm.core.StormClassTransformer;
import io.pzstorm.storm.event.core.StormEventDispatcher;
import io.pzstorm.storm.mod.ZomboidMod;
import io.pzstorm.storm.util.StormEnv;
import java.util.List;

public class AtfCasinoMod implements ZomboidMod {

    @Override
    public List<StormClassTransformer> getClassTransformers() {
        // Gate on StormEnv.isStormServer(), not GameServer.server — the latter is still false
        // at collectTransformers() time and would silently drop the patch.
        if (!StormEnv.isStormServer()) {
            return List.of();
        }
        return List.of(new PlayerHitPlayerPacketParsePatch());
    }

    @Override
    public void registerEventHandlers() {
        if (!StormEnv.isStormServer()) {
            return;
        }
        LOGGER.info("[AtfCasino] Registering event handlers");
        StormEventDispatcher.registerEventHandler(PlaceBetHandler.class);
        StormEventDispatcher.registerEventHandler(CasinoNpcManager.class);
        StormEventDispatcher.registerEventHandler(BlackjackHandler.class);
        StormEventDispatcher.registerEventHandler(RouletteHandler.class);
        StormEventDispatcher.registerEventHandler(HoldemHandler.class);
    }
}
