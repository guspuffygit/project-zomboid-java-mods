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

@CommandName(name = "zoneremove")
@CommandHelp(
        helpText = "Remove a zone from a category. Usage: /zoneremove \"<category>\" \"<name>\"",
        shouldTranslated = false)
@RequiredCapability(requiredCapability = Capability.DebugConsole)
@CommandArgs(varArgs = true)
public class ZoneRemoveCommand extends CommandBase {

    public ZoneRemoveCommand(
            String username, Role userRole, String command, UdpConnection connection) {
        super(username, userRole, command, connection);
    }

    @Override
    protected String Command() {
        if (getCommandArgsCount() < 2) {
            return "Usage: /zoneremove \"<category>\" \"<name>\"";
        }

        String category = null;
        int nameStart = -1;

        for (int catEnd = 1; catEnd < getCommandArgsCount(); catEnd++) {
            String candidate = joinArgs(this::getCommandArg, 0, catEnd);
            if (categoryExists(candidate)) {
                category = candidate;
                nameStart = catEnd;
            }
        }

        if (category == null) {
            return "Unknown category. Use /zonelist to see available categories.";
        }

        if (nameStart >= getCommandArgsCount()) {
            return "Zone name is required.";
        }

        String region = joinArgs(this::getCommandArg, nameStart, getCommandArgsCount());

        String error = removeZone(category, region);
        if (error != null) return error;

        broadcast();
        return "Removed '" + region + "' from " + category + ".";
    }
}
