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

@CommandName(name = "zoneadd")
@CommandHelp(
        helpText =
                "Add a zone to a category. Usage: /zoneadd \"<category>\" <xStart> <yStart> <xEnd>"
                        + " <yEnd> \"<name>\"",
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
        // zoneadd "<category>" <xStart> <yStart> <xEnd> <yEnd> "<name>"
        if (getCommandArgsCount() < 6) {
            return "Usage: /zoneadd \"<category>\" <xStart> <yStart> <xEnd> <yEnd> \"<name>\"";
        }

        KahluaTable data = getZoneData();
        KahluaTable categories = (KahluaTable) data.rawget("categories");

        // Find the category by trying progressively longer matches from arg 0
        String category = null;
        int coordStart = -1;

        for (int catEnd = 1; catEnd <= getCommandArgsCount() - 5; catEnd++) {
            String candidate = joinArgs(this::getCommandArg, 0, catEnd);
            if (findCategoryIndex(categories, candidate) != -1) {
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

        KahluaTable zones = (KahluaTable) data.rawget("zones");
        KahluaTable categoryZones = (KahluaTable) zones.rawget(category);
        if (categoryZones == null) {
            categoryZones = newTable();
            zones.rawset(category, categoryZones);
        }

        KahluaTable zone = newTable();
        zone.rawset("xStart", xStart);
        zone.rawset("xEnd", xEnd);
        zone.rawset("yStart", yStart);
        zone.rawset("yEnd", yEnd);
        zone.rawset("region", region);
        categoryZones.rawset(categoryZones.len() + 1, zone);

        broadcast();
        return "Added '" + region + "' to " + category + ".";
    }
}
