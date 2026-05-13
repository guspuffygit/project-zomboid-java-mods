package com.sentientsimulations.projectzomboid.jumpscareban;

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

@CommandName(name = "kachow")
@CommandArgs(optional = "(.+)")
@CommandHelp(
        helpText = "Play the kachow sound. Usage: /kachow [username] (omit to play for everyone)",
        shouldTranslated = false)
@RequiredCapability(requiredCapability = Capability.DebugConsole)
public class KachowCommand extends CommandBase {

    public KachowCommand(String username, Role userRole, String command, UdpConnection connection) {
        super(username, userRole, command, connection);
    }

    @Override
    protected String Command() {
        if (this.getCommandArgsCount() == 0) {
            GameServer.sendServerCommand("JumpscareBan", "playKachow", null);
            return "Kachow played for all players";
        }

        String targetUsername = this.getCommandArg(0);
        IsoPlayer player = GameServer.getPlayerByUserNameForCommand(targetUsername);
        if (player == null) {
            return "Player not found: " + targetUsername;
        }

        GameServer.sendServerCommand(player, "JumpscareBan", "playKachow", null);
        return "Kachow played for " + player.getUsername();
    }
}
