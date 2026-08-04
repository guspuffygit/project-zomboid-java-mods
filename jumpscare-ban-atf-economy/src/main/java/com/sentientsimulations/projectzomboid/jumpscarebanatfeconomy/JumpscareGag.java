package com.sentientsimulations.projectzomboid.jumpscarebanatfeconomy;

import org.jetbrains.annotations.Nullable;

/**
 * The three purchasable gags. Each maps to the exact global broadcast the matching jumpscare-ban
 * server command performs when run with no username argument: a server-alert chat line plus a
 * {@code JumpscareBan} module server command that every connected client's jumpscare-ban Lua
 * listens for.
 */
public enum JumpscareGag {
    FART("fart", "Fart", "playFart", "FartPrice"),
    CRY("cry", "Cry", "playCry", "CryPrice"),
    KACHOW("kachow", "Kachow", "playKachow", "KachowPrice");

    /** Module string the jumpscare-ban client Lua listens on — not this mod's own module. */
    public static final String JUMPSCARE_BAN_MODULE = "JumpscareBan";

    private final String id;
    private final String chatAlert;
    private final String playCommand;
    private final String priceOptionName;

    JumpscareGag(String id, String chatAlert, String playCommand, String priceOptionName) {
        this.id = id;
        this.chatAlert = chatAlert;
        this.playCommand = playCommand;
        this.priceOptionName = priceOptionName;
    }

    public String getId() {
        return id;
    }

    public String getChatAlert() {
        return chatAlert;
    }

    public String getPlayCommand() {
        return playCommand;
    }

    public String getPriceOptionName() {
        return priceOptionName;
    }

    @Nullable
    public static JumpscareGag fromId(@Nullable String id) {
        if (id == null) {
            return null;
        }
        for (JumpscareGag gag : values()) {
            if (gag.id.equalsIgnoreCase(id)) {
                return gag;
            }
        }
        return null;
    }
}
