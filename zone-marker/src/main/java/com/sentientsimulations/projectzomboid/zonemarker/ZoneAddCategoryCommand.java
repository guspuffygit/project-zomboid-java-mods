package com.sentientsimulations.projectzomboid.zonemarker;

import static com.sentientsimulations.projectzomboid.zonemarker.ZoneModDataHelper.*;

import se.krka.kahlua.vm.KahluaTable;
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
public class ZoneAddCategoryCommand extends CommandBase {

    public ZoneAddCategoryCommand(
            String username, Role userRole, String command, UdpConnection connection) {
        super(username, userRole, command, connection);
    }

    @Override
    protected String Command() {
        // zoneaddcategory <r> <g> <b> [a] "<name>"
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

        KahluaTable data = getZoneData();
        KahluaTable categories = (KahluaTable) data.rawget("categories");

        if (findCategoryIndex(categories, name) != -1) {
            return "Category '" + name + "' already exists.";
        }

        KahluaTable cat = newTable();
        cat.rawset("name", name);
        cat.rawset("r", r);
        cat.rawset("g", g);
        cat.rawset("b", b);
        cat.rawset("a", a);
        categories.rawset(categories.len() + 1, cat);

        KahluaTable zones = (KahluaTable) data.rawget("zones");
        if (zones.rawget(name) == null) {
            zones.rawset(name, newTable());
        }

        broadcast();
        return "Created category '" + name + "'.";
    }
}
