package com.sentientsimulations.projectzomboid.jumpscarebanatfeconomy;

import zombie.SandboxOptions;
import zombie.config.BooleanConfigOption;
import zombie.config.ConfigOption;
import zombie.config.IntegerConfigOption;

public final class JumpscareBanEconomyConfig {

    public static final int DEFAULT_PRICE = 1_000_000;
    public static final boolean DEFAULT_ENABLED = false;

    private static final String PREFIX = "JumpscareBanEconomy.";
    private static final String ENABLED_OPTION = "Enabled";

    private JumpscareBanEconomyConfig() {}

    /** Master switch. When false the server rejects every purchase and clients hide the shop. */
    public static boolean isEnabled() {
        ConfigOption co = readOption(ENABLED_OPTION);
        if (co instanceof BooleanConfigOption bo) {
            return bo.getValue();
        }
        return DEFAULT_ENABLED;
    }

    public static int getPrice(JumpscareGag gag) {
        ConfigOption co = readOption(gag.getPriceOptionName());
        if (co instanceof IntegerConfigOption io) {
            return io.getValue();
        }
        return DEFAULT_PRICE;
    }

    private static ConfigOption readOption(String name) {
        SandboxOptions.SandboxOption opt = SandboxOptions.instance.getOptionByName(PREFIX + name);
        return opt == null ? null : opt.asConfigOption();
    }
}
