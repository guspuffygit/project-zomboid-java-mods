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

@CommandName(name = "zonelist")
@CommandHelp(
        helpText = "List zone categories or zones in a category. Usage: /zonelist [\"<category>\"]",
        shouldTranslated = false)
@RequiredCapability(requiredCapability = Capability.DebugConsole)
@CommandArgs(varArgs = true)
public class ZoneListCommand extends CommandBase {

    public ZoneListCommand(
            String username, Role userRole, String command, UdpConnection connection) {
        super(username, userRole, command, connection);
    }

    @Override
    protected String Command() {
        KahluaTable data = getZoneData();
        KahluaTable categories = (KahluaTable) data.rawget("categories");
        KahluaTable zones = (KahluaTable) data.rawget("zones");

        if (getCommandArgsCount() >= 1) {
            String category = joinArgs(this::getCommandArg, 0, getCommandArgsCount());
            if (findCategoryIndex(categories, category) == -1) {
                return "Category '" + category + "' does not exist.";
            }
            KahluaTable categoryZones = (KahluaTable) zones.rawget(category);
            int count = categoryZones != null ? categoryZones.len() : 0;
            if (count == 0) {
                return category + ": 0 zones";
            }
            StringBuilder sb = new StringBuilder();
            sb.append(category).append(" (").append(count).append("): ");
            for (int i = 1; i <= count; i++) {
                KahluaTable z = (KahluaTable) categoryZones.rawget(i);
                if (i > 1) sb.append(", ");
                sb.append(z.rawget("region"));
            }
            return sb.toString();
        }

        if (categories.len() == 0) {
            return "No categories defined. Use /zoneaddcategory to create one.";
        }

        StringBuilder sb = new StringBuilder();
        for (int i = 1; i <= categories.len(); i++) {
            KahluaTable cat = (KahluaTable) categories.rawget(i);
            String catName = (String) cat.rawget("name");
            KahluaTable categoryZones = (KahluaTable) zones.rawget(catName);
            int count = categoryZones != null ? categoryZones.len() : 0;
            if (i > 1) sb.append(" | ");
            sb.append(catName).append(": ").append(count).append(" zones");
        }
        return sb.toString();
    }
}
