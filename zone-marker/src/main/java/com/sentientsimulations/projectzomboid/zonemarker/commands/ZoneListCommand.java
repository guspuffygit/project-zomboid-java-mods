package com.sentientsimulations.projectzomboid.zonemarker.commands;

import static com.sentientsimulations.projectzomboid.zonemarker.ZoneMarkerBridge.*;

import java.util.List;

import com.sentientsimulations.projectzomboid.zonemarker.records.ZoneCategoryRecord;
import com.sentientsimulations.projectzomboid.zonemarker.records.ZoneRecord;
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
        if (getCommandArgsCount() >= 1) {
            String category = joinArgs(this::getCommandArg, 0, getCommandArgsCount());
            if (!categoryExists(category)) {
                return "Category '%s' does not exist.".formatted(category);
            }
            List<ZoneRecord> zones = listZonesInCategory(category);
            if (zones.isEmpty()) {
                return category + ": 0 zones";
            }
            StringBuilder sb = new StringBuilder();
            sb.append(category).append(" (").append(zones.size()).append("): ");
            for (int i = 0; i < zones.size(); i++) {
                if (i > 0) sb.append(", ");
                sb.append(zones.get(i).region());
            }
            return sb.toString();
        }

        List<ZoneCategoryRecord> categories = listCategories();
        if (categories.isEmpty()) {
            return "No categories defined. Use /zoneaddcategory to create one.";
        }

        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < categories.size(); i++) {
            ZoneCategoryRecord cat = categories.get(i);
            List<ZoneRecord> zones = listZonesInCategory(cat.name());
            if (i > 0) sb.append(" | ");
            sb.append(cat.name()).append(": ").append(zones.size()).append(" zones");
        }
        return sb.toString();
    }
}
