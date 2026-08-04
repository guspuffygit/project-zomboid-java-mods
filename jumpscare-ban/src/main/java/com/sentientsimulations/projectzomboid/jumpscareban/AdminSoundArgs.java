package com.sentientsimulations.projectzomboid.jumpscareban;

import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;

/**
 * Args table stamped onto every sound broadcast an admin triggered with {@code /kachow}, {@code
 * /fart} or {@code /cry}.
 *
 * <p>The client mutes these when the "Admin sound commands" mod option is off. The ban send-off in
 * {@link JumpscareBanService} deliberately sends {@code null} args instead, so the jumpscare, the
 * kachow and the thunderclap that accompany a real ban are never mutable — {@code playKachow} is
 * sent by both paths and this flag is the only thing that tells them apart on the client.
 */
final class AdminSoundArgs {

    private AdminSoundArgs() {}

    static KahluaTable forEveryone() {
        KahluaTable args = LuaManager.platform.newTable();
        args.rawset("fromCommand", Boolean.TRUE);
        return args;
    }

    static KahluaTable forPlayer(IsoPlayer player) {
        KahluaTable args = forEveryone();
        args.rawset("onlineID", (double) player.getOnlineID());
        return args;
    }
}
