package com.sentientsimulations.projectzomboid.guspuffyatfpatches;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import com.sentientsimulations.projectzomboid.guspuffyatfpatches.patch.FBORenderCutawaysRecreateLevelGuardPatch;
import com.sentientsimulations.projectzomboid.guspuffyatfpatches.patch.IsoChunkBackupBlamPatch;
import com.sentientsimulations.projectzomboid.guspuffyatfpatches.patch.IsoChunkSetMinMaxLevelGuardPatch;
import io.pzstorm.storm.core.StormClassTransformer;
import io.pzstorm.storm.mod.ZomboidMod;
import io.pzstorm.storm.util.StormEnv;
import java.util.ArrayList;
import java.util.List;

public class GuspuffyAtfPatchesMod implements ZomboidMod {

    @Override
    public void registerEventHandlers() {
        if (!StormEnv.isStormServer()) {
            return;
        }
        LOGGER.debug(
                "[GuspuffyAtfPatches] Registering for {}", GuspuffyAtfPatchesMod.class.getName());
    }

    @Override
    public List<StormClassTransformer> getClassTransformers() {
        // Chunk-corruption defenses (ATF 2026-08-08 torn-chunk incident). Deliberately NOT
        // gated on isStormServer: the level clamp and the BackupBlam observability advice
        // protect both JVMs (the server hits the same unvalidated header when loading a
        // corrupt map/<wx>/<wy>.bin from disk — see the save's blam/ history).
        List<StormClassTransformer> transformers = new ArrayList<>();
        transformers.add(new IsoChunkSetMinMaxLevelGuardPatch());
        transformers.add(new IsoChunkBackupBlamPatch());
        // Client-only: the FBO cutaway render path never runs on the dedicated server.
        if (!StormEnv.isStormServer()) {
            transformers.add(new FBORenderCutawaysRecreateLevelGuardPatch());
        }
        return transformers;
    }
}
