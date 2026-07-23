package com.sentientsimulations.projectzomboid.survivorskillobelisk;

import static io.pzstorm.storm.logging.StormLogger.LOGGER;

import io.pzstorm.storm.event.core.SubscribeEvent;
import io.pzstorm.storm.event.lua.OnServerStartedEvent;
import io.pzstorm.storm.event.zomboid.OnSandboxOptionsUpdateEvent;
import java.util.function.Consumer;
import java.util.function.IntConsumer;
import zombie.SandboxOptions;
import zombie.network.GameServer;

/**
 * Reads the {@code SkillObelisk.*} sandbox options at {@code OnServerStarted} and pushes them
 * through {@link SurvivorSkillObeliskConfig}'s setters. Missing or wrong-typed options are logged
 * and left at their compiled-in defaults so a stale {@code <SaveName>.ini} cannot zero out a value.
 *
 * <p>Gated on {@link GameServer#server} — recovery is an authoritative-server concern. The event
 * also fires on the client when hosting a coop server; that path is ignored.
 */
public final class SurvivorSkillObeliskSandboxApplier {

    public static final String OPT_RECOVER_SKILLS = "SkillObelisk.RecoverSkills";
    public static final String OPT_RECOVER_RECIPES = "SkillObelisk.RecoverRecipes";
    public static final String OPT_RECOVER_SKILL_MAGAZINES = "SkillObelisk.RecoverSkillMagazines";
    public static final String OPT_RECOVER_READ_PRINT_MEDIA = "SkillObelisk.RecoverReadPrintMedia";
    public static final String OPT_RECOVER_WATCHED_MEDIA = "SkillObelisk.RecoverWatchedMedia";
    public static final String OPT_RECOVER_LEARNED_SONGS = "SkillObelisk.RecoverLearnedSongs";
    public static final String OPT_RECOVER_AMBITIONS = "SkillObelisk.RecoverAmbitions";
    public static final String OPT_RECOVER_HIDDEN_SKILLS = "SkillObelisk.RecoverHiddenSkills";
    public static final String OPT_SKILL_RECOVERY_PERCENT = "SkillObelisk.SkillRecoveryPercent";
    public static final String OPT_CURSE_ON_SLEDGEHAMMER = "SkillObelisk.CurseOnSledgehammer";

    private SurvivorSkillObeliskSandboxApplier() {}

    @SubscribeEvent
    public static void onServerStarted(OnServerStartedEvent event) {
        applyAll();
    }

    /**
     * Re-apply after an admin pushes new sandbox options at runtime. Vanilla {@code
     * GameServer.receiveSandboxOptions} updates {@code SandboxOptions.instance} in place without
     * firing a Lua event; Storm fires this Java event from there so per-mod config caches don't
     * stay frozen at boot-time values.
     */
    @SubscribeEvent
    public static void onSandboxOptionsUpdate(OnSandboxOptionsUpdateEvent event) {
        applyAll();
    }

    public static void applyAll() {
        if (!GameServer.server) {
            return;
        }
        applyBool(OPT_RECOVER_SKILLS, SurvivorSkillObeliskConfig::setRecoverSkills);
        applyBool(OPT_RECOVER_RECIPES, SurvivorSkillObeliskConfig::setRecoverRecipes);
        applyBool(
                OPT_RECOVER_SKILL_MAGAZINES, SurvivorSkillObeliskConfig::setRecoverSkillMagazines);
        applyBool(
                OPT_RECOVER_READ_PRINT_MEDIA, SurvivorSkillObeliskConfig::setRecoverReadPrintMedia);
        applyBool(OPT_RECOVER_WATCHED_MEDIA, SurvivorSkillObeliskConfig::setRecoverWatchedMedia);
        applyBool(OPT_RECOVER_LEARNED_SONGS, SurvivorSkillObeliskConfig::setRecoverLearnedSongs);
        applyBool(OPT_RECOVER_AMBITIONS, SurvivorSkillObeliskConfig::setRecoverAmbitions);
        applyBool(OPT_RECOVER_HIDDEN_SKILLS, SurvivorSkillObeliskConfig::setRecoverHiddenSkills);
        applyInt(OPT_SKILL_RECOVERY_PERCENT, SurvivorSkillObeliskConfig::setSkillRecoveryPercent);
        applyBool(OPT_CURSE_ON_SLEDGEHAMMER, SurvivorSkillObeliskConfig::setCurseOnSledgehammer);
    }

    private static void applyBool(String name, Consumer<Boolean> setter) {
        Boolean value = readBoolOption(name);
        if (value == null) {
            return;
        }
        setter.accept(value);
    }

    private static void applyInt(String name, IntConsumer setter) {
        Integer value = readIntOption(name);
        if (value == null) {
            return;
        }
        setter.accept(value);
    }

    private static Boolean readBoolOption(String name) {
        SandboxOptions.SandboxOption option = lookup(name);
        if (option == null) {
            return null;
        }
        if (!(option instanceof SandboxOptions.BooleanSandboxOption booleanOption)) {
            LOGGER.warn(
                    "[SurvivorSkillObelisk] sandbox option {} is not a boolean option; skipping",
                    name);
            return null;
        }
        return booleanOption.getValue();
    }

    private static Integer readIntOption(String name) {
        SandboxOptions.SandboxOption option = lookup(name);
        if (option == null) {
            return null;
        }
        if (!(option instanceof SandboxOptions.IntegerSandboxOption integerOption)) {
            LOGGER.warn(
                    "[SurvivorSkillObelisk] sandbox option {} is not an integer option; skipping",
                    name);
            return null;
        }
        return integerOption.getValue();
    }

    private static SandboxOptions.SandboxOption lookup(String name) {
        try {
            SandboxOptions.SandboxOption option = SandboxOptions.instance.getOptionByName(name);
            if (option == null) {
                LOGGER.warn("[SurvivorSkillObelisk] sandbox option {} not found; skipping", name);
            }
            return option;
        } catch (Exception e) {
            LOGGER.warn("[SurvivorSkillObelisk] sandbox option {} lookup failed", name, e);
            return null;
        }
    }
}
