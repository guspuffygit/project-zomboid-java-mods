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

@CommandName(name = "zoneaddcategory")
@CommandHelp(
        helpText =
                "Create a zone category with a color. Usage: /zoneaddcategory <r> <g> <b> [a]"
                        + " \"<name>\"",
        shouldTranslated = false)
@RequiredCapability(requiredCapability = Capability.DebugConsole)
@CommandArgs(varArgs = true)
public class ZoneCategoryAddCommand extends CommandBase {

    public ZoneCategoryAddCommand(
            String username, Role userRole, String command, UdpConnection connection) {
        super(username, userRole, command, connection);
    }

    @Override
    protected String Command() {
        if (getCommandArgsCount() < 4) {
            return "Usage: /zoneaddcategory <r> <g> <b> [a] \"<name>\"";
        }

        Double r = parseDouble(getCommandArg(0));
        Double g = parseDouble(getCommandArg(1));
        Double b = parseDouble(getCommandArg(2));
        if (r == null || g == null || b == null) {
            return "Invalid color values. Provide r, g, b as numbers (0-1).";
        }

        double a;
        int nameStart;
        Double maybeAlpha = parseDouble(getCommandArg(3));
        if (maybeAlpha != null && getCommandArgsCount() >= 5) {
            a = maybeAlpha;
            nameStart = 4;
        } else {
            a = 1.0;
            nameStart = 3;
        }

        if (nameStart >= getCommandArgsCount()) {
            return "Category name is required.";
        }

        String name = joinArgs(this::getCommandArg, nameStart, getCommandArgsCount());

        if (name.isEmpty()) {
            return "Category name is required.";
        }

        String error = addCategory(name, r, g, b, a);
        if (error != null) return error;

        broadcast();
        return "Created category '" + name + "'.";
    }
}
