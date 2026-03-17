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

        KahluaTable data = getZoneData();
        KahluaTable categories = (KahluaTable) data.rawget("categories");

        // Find category by trying progressively longer matches from arg 0
        String category = null;
        int nameStart = -1;

        for (int catEnd = 1; catEnd < getCommandArgsCount(); catEnd++) {
            String candidate = joinArgs(this::getCommandArg, 0, catEnd);
            if (findCategoryIndex(categories, candidate) != -1) {
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

        KahluaTable zones = (KahluaTable) data.rawget("zones");
        KahluaTable categoryZones = (KahluaTable) zones.rawget(category);
        if (categoryZones == null || categoryZones.len() == 0) {
            return "No zones in category '" + category + "'.";
        }

        boolean removed = false;
        for (int i = categoryZones.len(); i >= 1; i--) {
            KahluaTable z = (KahluaTable) categoryZones.rawget(i);
            if (z != null && region.equals(z.rawget("region"))) {
                removeArrayElement(categoryZones, i);
                removed = true;
            }
        }

        if (removed) {
            broadcast();
            return "Removed '" + region + "' from " + category + ".";
        }
        return "Zone '" + region + "' not found in " + category + ".";
    }
}
