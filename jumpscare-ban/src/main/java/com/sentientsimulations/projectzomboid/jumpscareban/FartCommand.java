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

@CommandName(name = "fart")
@CommandArgs(optional = "(.+)")
@CommandHelp(
        helpText = "Play the fart sound. Usage: /fart [username] (omit to play for everyone)",
        shouldTranslated = false)
@RequiredCapability(requiredCapability = Capability.DebugConsole)
public class FartCommand extends CommandBase {

    private static final String[] HALO_PHRASES = {
        "tooooooot",
        "pfffffft",
        "bbbbrrrrrap",
        "phhhrrrtt",
        "ppppffffrrrt",
        "brraaap",
        "fffffrrrrt",
        "ppppthhhh",
        "squeeeeak",
        "blaaaarrrt",
        "thhhrrrrp",
        "plllllop",
        "brrrrump",
        "pffft",
        "fwoooosh",
        "baruuump",
        "squelch",
        "bbbbbtttt",
        "ploooop",
        "parp",
    };

    public FartCommand(String username, Role userRole, String command, UdpConnection connection) {
        super(username, userRole, command, connection);
    }

    @Override
    protected String Command() {
        if (this.getCommandArgsCount() == 0) {
            ChatServer.getInstance().sendServerAlertMessageToServerChat("Fart");
            GameServer.sendServerCommand("JumpscareBan", "playFart", null);
            return "Fart played for all players";
        }

        String targetUsername = this.getCommandArg(0);
        IsoPlayer player = GameServer.getPlayerByUserNameForCommand(targetUsername);
        if (player == null) {
            return "Player not found: " + targetUsername;
        }

        String phrase = HALO_PHRASES[ThreadLocalRandom.current().nextInt(HALO_PHRASES.length)];

        KahluaTable haloArgs = LuaManager.platform.newTable();
        haloArgs.rawset("onlineID", (double) player.getOnlineID());
        haloArgs.rawset("text", phrase);
        GameServer.sendServerCommand("JumpscareBan", "showFartHalo", haloArgs);

        KahluaTable fartArgs = LuaManager.platform.newTable();
        fartArgs.rawset("onlineID", (double) player.getOnlineID());
        GameServer.sendServerCommand(player, "JumpscareBan", "playFart3D", fartArgs);

        return "Fart played for " + player.getUsername();
    }
}
