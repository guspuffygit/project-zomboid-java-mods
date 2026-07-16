package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.OnNewGameEvent;
import java.sql.Connection;
import java.util.LinkedHashMap;
import java.util.Map;
import zombie.characters.IsoPlayer;
import zombie.characters.skills.PerkFactory;

/**
 * Records each character's creation-time per-perk XP so {@link DeathEventHandler} can save
 * earned-only XP as {@code deathXp - baselineXp} instead of estimating the creation grant from the
 * traits held at death (which breaks for the Strength/Fitness tier traits PZ swaps as those perks
 * level — see {@code server/XpSystem/XpUpdate.lua}).
 *
 * <p>On a dedicated server the {@code OnNewGame} Lua event fires only from {@code
 * CreatePlayerPacket.processServer}, i.e. exactly once per freshly created character (first join or
 * respawn after death) and never on reconnect — so replacing the baseline here can't clobber a live
 * character's record. By trigger time the packet handler has already run {@code applyTraits}
 * (populating the XP map with every trait + profession grant) and set username/steamID, so the
 * snapshot is complete and keyed identically to the death rows.
 *
 * <p>Same two-thread split as {@link DeathEventHandler}: the XP map is snapshotted on the main
 * thread, the SQLite write goes through {@link DeathEventHandler#submitDbWrite} — the shared FIFO
 * queue guarantees a queued death write always reads the dying character's baseline before the
 * respawn's replace lands.
 */
public final class CharacterBaselineHandler {

    private CharacterBaselineHandler() {}

    @SubscribeEvent
    public static void onNewGame(OnNewGameEvent event) {
        IsoPlayer player = event.player;
        if (player == null) {
            return;
        }
        String username = player.getUsername();
        long steamId = player.getSteamID();
        if (username == null || username.isBlank()) {
            LOGGER.warn(
                    "[SurvivorSkillObelisk] OnNewGame for player with no username ({}); not"
                            + " recording creation baseline",
                    steamId);
            return;
        }
        Map<String, Float> baseline = new LinkedHashMap<>();
        for (PerkFactory.Perk perk : PerkFactory.PerkList) {
            baseline.put(perk.getId(), player.getXp().getXP(perk));
        }
        DeathEventHandler.submitDbWrite(() -> writeBaseline(steamId, username, baseline));
    }

    private static void writeBaseline(long steamId, String username, Map<String, Float> baseline) {
        try (SurvivorSkillObeliskDatabase db =
                new SurvivorSkillObeliskDatabase(DeathEventHandler.getDbPath())) {
            Connection conn = db.getConnection();
            conn.setAutoCommit(false);
            new SurvivorSkillObeliskRepository(conn)
                    .replaceCharacterBaseline(steamId, username, baseline);
            conn.commit();
            LOGGER.info(
                    "[SurvivorSkillObelisk] Recorded creation baseline for {} ({}): {} perks",
                    username,
                    steamId,
                    baseline.size());
        } catch (Exception e) {
            LOGGER.error(
                    "[SurvivorSkillObelisk] Failed to record creation baseline for {} ({})",
                    username,
                    steamId,
                    e);
        }
    }
}
