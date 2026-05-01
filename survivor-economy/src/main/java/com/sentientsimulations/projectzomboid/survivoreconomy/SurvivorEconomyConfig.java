package com.sentientsimulations.projectzomboid.survivoreconomy;

import zombie.SandboxOptions;

/**
 * Static accessors for {@code media/sandbox-options.txt}. Each call reads the live PZ {@link
 * SandboxOptions} value at invocation time so admins changing the option mid-server take effect on
 * the next read (PZ persists changes through {@code Save}/restart, but the in-memory value updates
 * immediately).
 *
 * <p>Falls back to the hardcoded default when the option is absent — happens when the mod's
 * sandbox-options file isn't installed or the lookup is made before {@code SandboxOptions} is
 * populated.
 */
public final class SurvivorEconomyConfig {

    public static final boolean DEFAULT_ISSUE_PAYCHECKS = true;
    public static final int DEFAULT_HOURS_UNTIL_PAYCHECK = 24;
    public static final int DEFAULT_PAYCHECK_VALUE = 200;
    public static final boolean DEFAULT_PAY_ZOMBIE_BOUNTY = true;
    public static final int DEFAULT_ZOMBIE_BOUNTY_CHANCE = 10;
    public static final int DEFAULT_ZOMBIE_BOUNTY_MIN_AMOUNT = 1;
    public static final int DEFAULT_ZOMBIE_BOUNTY_MAX_AMOUNT = 10;
    public static final boolean DEFAULT_ALLOW_PLAYER_TRANSFERS = true;
    public static final int DEFAULT_PLAYER_TRANSFER_MAX_DISTANCE = 4;

    static final String OPT_ISSUE_PAYCHECKS = "SurvivorEconomy.IssuePaychecks";
    static final String OPT_HOURS_UNTIL_PAYCHECK = "SurvivorEconomy.HoursUntilPaycheck";
    static final String OPT_PAYCHECK_VALUE = "SurvivorEconomy.PaycheckValue";
    static final String OPT_PAY_ZOMBIE_BOUNTY = "SurvivorEconomy.PayZombieBounty";
    static final String OPT_ZOMBIE_BOUNTY_CHANCE = "SurvivorEconomy.ZombieBountyChance";
    static final String OPT_ZOMBIE_BOUNTY_MIN_AMOUNT = "SurvivorEconomy.ZombieBountyMinAmount";
    static final String OPT_ZOMBIE_BOUNTY_MAX_AMOUNT = "SurvivorEconomy.ZombieBountyMaxAmount";
    static final String OPT_ALLOW_PLAYER_TRANSFERS = "SurvivorEconomy.AllowPlayerTransfers";
    static final String OPT_PLAYER_TRANSFER_MAX_DISTANCE =
            "SurvivorEconomy.PlayerTransferMaxDistance";

    private SurvivorEconomyConfig() {}

    public static boolean issuePaychecks() {
        SandboxOptions.SandboxOption opt =
                SandboxOptions.instance.getOptionByName(OPT_ISSUE_PAYCHECKS);
        if (opt instanceof SandboxOptions.BooleanSandboxOption b) {
            return b.getValue();
        }
        return DEFAULT_ISSUE_PAYCHECKS;
    }

    public static int hoursUntilPaycheck() {
        SandboxOptions.SandboxOption opt =
                SandboxOptions.instance.getOptionByName(OPT_HOURS_UNTIL_PAYCHECK);
        if (opt instanceof SandboxOptions.IntegerSandboxOption i) {
            return i.getValue();
        }
        return DEFAULT_HOURS_UNTIL_PAYCHECK;
    }

    public static int paycheckValue() {
        SandboxOptions.SandboxOption opt =
                SandboxOptions.instance.getOptionByName(OPT_PAYCHECK_VALUE);
        if (opt instanceof SandboxOptions.IntegerSandboxOption i) {
            return i.getValue();
        }
        return DEFAULT_PAYCHECK_VALUE;
    }

    public static boolean payZombieBounty() {
        SandboxOptions.SandboxOption opt =
                SandboxOptions.instance.getOptionByName(OPT_PAY_ZOMBIE_BOUNTY);
        if (opt instanceof SandboxOptions.BooleanSandboxOption b) {
            return b.getValue();
        }
        return DEFAULT_PAY_ZOMBIE_BOUNTY;
    }

    public static int zombieBountyChance() {
        SandboxOptions.SandboxOption opt =
                SandboxOptions.instance.getOptionByName(OPT_ZOMBIE_BOUNTY_CHANCE);
        if (opt instanceof SandboxOptions.IntegerSandboxOption i) {
            return i.getValue();
        }
        return DEFAULT_ZOMBIE_BOUNTY_CHANCE;
    }

    public static int zombieBountyMinAmount() {
        SandboxOptions.SandboxOption opt =
                SandboxOptions.instance.getOptionByName(OPT_ZOMBIE_BOUNTY_MIN_AMOUNT);
        if (opt instanceof SandboxOptions.IntegerSandboxOption i) {
            return i.getValue();
        }
        return DEFAULT_ZOMBIE_BOUNTY_MIN_AMOUNT;
    }

    public static int zombieBountyMaxAmount() {
        SandboxOptions.SandboxOption opt =
                SandboxOptions.instance.getOptionByName(OPT_ZOMBIE_BOUNTY_MAX_AMOUNT);
        if (opt instanceof SandboxOptions.IntegerSandboxOption i) {
            return i.getValue();
        }
        return DEFAULT_ZOMBIE_BOUNTY_MAX_AMOUNT;
    }

    public static boolean allowPlayerTransfers() {
        SandboxOptions.SandboxOption opt =
                SandboxOptions.instance.getOptionByName(OPT_ALLOW_PLAYER_TRANSFERS);
        if (opt instanceof SandboxOptions.BooleanSandboxOption b) {
            return b.getValue();
        }
        return DEFAULT_ALLOW_PLAYER_TRANSFERS;
    }

    public static int playerTransferMaxDistance() {
        SandboxOptions.SandboxOption opt =
                SandboxOptions.instance.getOptionByName(OPT_PLAYER_TRANSFER_MAX_DISTANCE);
        if (opt instanceof SandboxOptions.IntegerSandboxOption i) {
            return i.getValue();
        }
        return DEFAULT_PLAYER_TRANSFER_MAX_DISTANCE;
    }
}
