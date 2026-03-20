package com.sentientsimulations.projectzomboid.zonemarker.commands;

import static com.sentientsimulations.projectzomboid.zonemarker.ZoneMarkerBridge.*;

import zombie.characters.Capability;
import zombie.characters.Role;
import zombie.commands.CommandArgs;
import zombie.commands.CommandBase;
import zombie.commands.CommandHelp;
import zombie.commands.CommandName;
import zombie.commands.RequiredCapability;
import zombie.core.raknet.UdpConnection;

@CommandName(name = "zoneremovecategory")
@CommandHelp(
        helpText =
                "Remove a zone category and all its zones. Usage: /zoneremovecategory \"<name>\"",
        shouldTranslated = false)
@RequiredCapability(requiredCapability = Capability.DebugConsole)
@CommandArgs(varArgs = true)
public class ZoneCategoryRemoveCommand extends CommandBase {

    public ZoneCategoryRemoveCommand(
            String username, Role userRole, String command, UdpConnection connection) {
        super(username, userRole, command, connection);
    }

    @Override
    protected String Command() {
        if (getCommandArgsCount() < 1) {
            return "Usage: /zoneremovecategory \"<name>\"";
        }

        String name = joinArgs(this::getCommandArg, 0, getCommandArgsCount());

        String error = removeCategory(name);
        if (error != null) return error;

        broadcast();
        return "Removed category '" + name + "' and all its zones.";
    }
}
