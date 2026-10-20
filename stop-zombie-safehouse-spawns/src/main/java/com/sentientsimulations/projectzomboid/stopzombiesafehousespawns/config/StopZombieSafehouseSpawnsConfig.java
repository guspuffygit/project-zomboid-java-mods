package com.sentientsimulations.projectzomboid.stopzombiesafehousespawns.config;

import zombie.SandboxOptions;
import zombie.config.BooleanConfigOption;
import zombie.config.ConfigOption;

public final class StopZombieSafehouseSpawnsConfig {

    public static final boolean DEFAULT_ENABLED = true;
    public static final boolean DEFAULT_BLOCK_PVE_ZONES = false;

    private static final String PREFIX = "StopZombieSafehouseSpawns.";

    private StopZombieSafehouseSpawnsConfig() {}

    public static boolean isEnabled() {
        return readBoolean("Enabled", DEFAULT_ENABLED);
    }

    public static boolean isBlockPveZones() {
        return readBoolean("BlockPveZones", DEFAULT_BLOCK_PVE_ZONES);
    }

    private static boolean readBoolean(String shortName, boolean fallback) {
        ConfigOption co = lookup(shortName);
        if (co instanceof BooleanConfigOption bco) {
            return bco.getValue();
        }
        return fallback;
    }

    private static ConfigOption lookup(String shortName) {
        SandboxOptions.SandboxOption opt =
                SandboxOptions.instance.getOptionByName(PREFIX + shortName);
        return opt == null ? null : opt.asConfigOption();
    }
}
