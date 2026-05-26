package com.sentientsimulations.projectzomboid.jumpscareban;

import io.pzstorm.storm.halo.StormHalo;
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

@CommandName(name = "kachow")
@CommandArgs(optional = "(.+)")
@CommandHelp(
        helpText = "Play the kachow sound. Usage: /kachow [username] (omit to play for everyone)",
        shouldTranslated = false)
@RequiredCapability(requiredCapability = Capability.DebugConsole)
public class KachowCommand extends CommandBase {

    private static final String[] HALO_PHRASES = {
        "KA-CHOW!",
        "ka-chow",
        "ka-ch-ch-chow",
        "kachoooow",
        "ka-CHOW",
        "kkk-ca-chow",
        "ka-chigga",
        "speed!",
        "vroooom",
        "lightning!",
        "ka-chow-chow",
        "zoooom",
        "kaCHOW!",
        "screeech",
        "nyooom",
        "ka-pow",
        "floor it!",
        "ka-chowza",
        "kachow~",
        "BRRRM",
    };

    public KachowCommand(String username, Role userRole, String command, UdpConnection connection) {
        super(username, userRole, command, connection);
    }

    @Override
    protected String Command() {
        if (this.getCommandArgsCount() == 0) {
            ChatServer.getInstance().sendServerAlertMessageToServerChat("Kachow");
            GameServer.sendServerCommand("JumpscareBan", "playKachow", null);
            return "Kachow played for all players";
        }

        String targetUsername = this.getCommandArg(0);
        IsoPlayer player = GameServer.getPlayerByUserNameForCommand(targetUsername);
        if (player == null) {
            return "Player not found: " + targetUsername;
        }

        String phrase = HALO_PHRASES[ThreadLocalRandom.current().nextInt(HALO_PHRASES.length)];

        KahluaTable args = LuaManager.platform.newTable();
        args.rawset("onlineID", (double) player.getOnlineID());
        GameServer.sendServerCommand("JumpscareBan", "playKachow3D", args);

        StormHalo.setHalo(player, phrase, 230, 60, 50);

        return "Kachow played for " + player.getUsername();
    }
}
