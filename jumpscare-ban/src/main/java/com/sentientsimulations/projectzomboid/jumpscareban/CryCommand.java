package com.sentientsimulations.projectzomboid.jumpscareban;

import java.util.concurrent.ThreadLocalRandom;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.Capability;
import zombie.characters.IsoPlayer;
import zombie.characters.Role;
import zombie.commands.CommandArgs;
import zombie.commands.CommandBase;
import zombie.commands.CommandHelp;
import zombie.commands.CommandName;
import zombie.commands.RequiredCapability;
import zombie.core.raknet.UdpConnection;
import zombie.network.GameServer;
import zombie.network.chat.ChatServer;

@CommandName(name = "cry")
@CommandArgs(optional = "(.+)")
@CommandHelp(
        helpText = "Play the cry sound. Usage: /cry [username] (omit to play for everyone)",
        shouldTranslated = false)
@RequiredCapability(requiredCapability = Capability.DebugConsole)
public class CryCommand extends CommandBase {

    private static final String[] HALO_PHRASES = {
        "waaaaah",
        "boohoooo",
        "sniffle",
        "wahhhhhh",
        "hicc-up",
        "*sob*",
        "boo-hoo",
        "waaaaaaaa",
        "hnnnggg",
        "uuuhhhh",
        "nooooooo",
        "*cries*",
        "*whimper*",
        "waaah",
        "wahh",
        "snifff",
        "*tears*",
        "owwwwie",
        "huuuhhh",
        "wahhwah",
    };

    public CryCommand(String username, Role userRole, String command, UdpConnection connection) {
        super(username, userRole, command, connection);
    }

    @Override
    protected String Command() {
        if (this.getCommandArgsCount() == 0) {
            ChatServer.getInstance().sendServerAlertMessageToServerChat("Cry");
            GameServer.sendServerCommand("JumpscareBan", "playCry", null);
            return "Cry played for all players";
        }

        String targetUsername = this.getCommandArg(0);
        IsoPlayer player = GameServer.getPlayerByUserNameForCommand(targetUsername);
        if (player == null) {
            return "Player not found: " + targetUsername;
        }

        String phrase = HALO_PHRASES[ThreadLocalRandom.current().nextInt(HALO_PHRASES.length)];

        KahluaTable args = LuaManager.platform.newTable();
        args.rawset("onlineID", (double) player.getOnlineID());
        args.rawset("text", phrase);
        GameServer.sendServerCommand("JumpscareBan", "playCry3D", args);
        GameServer.sendServerCommand("JumpscareBan", "showCryHalo", args);

        return "Cry played for " + player.getUsername();
    }
}
