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

@CommandName(name = "zoneadd")
@CommandHelp(
        helpText =
                "Add a zone to a category. Usage: /zoneadd \"<category>\" <xStart> <yStart> <xEnd> <yEnd> \"<name>\"",
        shouldTranslated = false)
@RequiredCapability(requiredCapability = Capability.DebugConsole)
@CommandArgs(varArgs = true)
public class ZoneAddCommand extends CommandBase {

    public ZoneAddCommand(
            String username, Role userRole, String command, UdpConnection connection) {
        super(username, userRole, command, connection);
    }

    @Override
    protected String Command() {
        if (getCommandArgsCount() < 6) {
            return "Usage: /zoneadd \"<category>\" <xStart> <yStart> <xEnd> <yEnd> \"<name>\"";
        }

        String category = null;
        int coordStart = -1;

        for (int catEnd = 1; catEnd <= getCommandArgsCount() - 5; catEnd++) {
            String candidate = joinArgs(this::getCommandArg, 0, catEnd);
            if (categoryExists(candidate)) {
                category = candidate;
                coordStart = catEnd;
            }
        }

        if (category == null) {
            return "Unknown category. Use /zonelist to see available categories.";
        }

        Double xStart = parseDouble(getCommandArg(coordStart));
        Double yStart = parseDouble(getCommandArg(coordStart + 1));
        Double xEnd = parseDouble(getCommandArg(coordStart + 2));
        Double yEnd = parseDouble(getCommandArg(coordStart + 3));

        if (xStart == null || yStart == null || xEnd == null || yEnd == null) {
            return "Invalid coordinates. Provide xStart, yStart, xEnd, yEnd as numbers.";
        }

        int nameStart = coordStart + 4;
        if (nameStart >= getCommandArgsCount()) {
            return "Zone name is required.";
        }
        String region = joinArgs(this::getCommandArg, nameStart, getCommandArgsCount());

        String error = addZone(category, xStart, yStart, xEnd, yEnd, region);
        if (error != null) return error;

        broadcast();
        return "Added '" + region + "' to " + category + ".";
    }
}
