package com.sentientsimulations.projectzomboid.survivorlootrespawn.config;

import zombie.SandboxOptions;
import zombie.config.ConfigOption;
import zombie.config.DoubleConfigOption;
import zombie.config.IntegerConfigOption;

public final class SurvivorLootRespawnConfig {

    public enum LootRespawnType {
        VANILLA(1),
        EXPONENTIAL(2);

        private final int value;

        LootRespawnType(int value) {
            this.value = value;
        }

        public int value() {
            return value;
        }

        public static LootRespawnType fromValue(int v) {
            for (LootRespawnType t : values()) {
                if (t.value == v) {
                    return t;
                }
            }
            return EXPONENTIAL;
        }
    }

    public static final LootRespawnType DEFAULT_LOOT_RESPAWN_TYPE = LootRespawnType.EXPONENTIAL;
    public static final int DEFAULT_HOURS_TILL_MAX_RESPAWN_CHANCE = 96;
    public static final int DEFAULT_MAX_RESPAWN_CHANCE = 100;
    public static final int DEFAULT_MIN_RESPAWN_CHANCE = 0;
    public static final int DEFAULT_CONTAINER_QUIET_PERIOD_HOURS = 0;
    public static final double DEFAULT_CURVE_STEEPNESS = 1.05;

    private static final String PREFIX = "SurvivorLootRespawn.";

    private SurvivorLootRespawnConfig() {}

    public static LootRespawnType getLootRespawnType() {
        return LootRespawnType.fromValue(
                readInt("LootRespawnType", DEFAULT_LOOT_RESPAWN_TYPE.value()));
    }

    public static boolean isModEnabled() {
        return getLootRespawnType() != LootRespawnType.VANILLA;
    }

    public static int getHoursTillMaxRespawnChance() {
        return readInt("HoursTillMaxRespawnChance", DEFAULT_HOURS_TILL_MAX_RESPAWN_CHANCE);
    }

    public static int getMaxRespawnChance() {
        return readInt("MaxRespawnChance", DEFAULT_MAX_RESPAWN_CHANCE);
    }

    public static int getMinRespawnChance() {
        return readInt("MinRespawnChance", DEFAULT_MIN_RESPAWN_CHANCE);
    }

    public static int getContainerQuietPeriodHours() {
        return readInt("ContainerQuietPeriodHours", DEFAULT_CONTAINER_QUIET_PERIOD_HOURS);
    }

    public static double getCurveSteepness() {
        return readDouble("CurveSteepness", DEFAULT_CURVE_STEEPNESS);
    }

    private static int readInt(String shortName, int fallback) {
        ConfigOption co = lookup(shortName);
        if (co instanceof IntegerConfigOption io) {
            return io.getValue();
        }
        return fallback;
    }

    private static double readDouble(String shortName, double fallback) {
        ConfigOption co = lookup(shortName);
        if (co instanceof DoubleConfigOption dco) {
            return dco.getValue();
        }
        return fallback;
    }

    private static ConfigOption lookup(String shortName) {
        SandboxOptions.SandboxOption opt =
                SandboxOptions.instance.getOptionByName(PREFIX + shortName);
        return opt == null ? null : opt.asConfigOption();
    }
}
