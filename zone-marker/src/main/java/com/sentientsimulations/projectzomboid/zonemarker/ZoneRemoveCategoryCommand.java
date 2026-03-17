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

@CommandName(name = "zoneremovecategory")
@CommandHelp(
        helpText =
                "Remove a zone category and all its zones. Usage: /zoneremovecategory \"<name>\"",
        shouldTranslated = false)
@RequiredCapability(requiredCapability = Capability.DebugConsole)
@CommandArgs(varArgs = true)
public class ZoneRemoveCategoryCommand extends CommandBase {

    public ZoneRemoveCategoryCommand(
            String username, Role userRole, String command, UdpConnection connection) {
        super(username, userRole, command, connection);
    }

    @Override
    protected String Command() {
        if (getCommandArgsCount() < 1) {
            return "Usage: /zoneremovecategory \"<name>\"";
        }

        String name = joinArgs(this::getCommandArg, 0, getCommandArgsCount());

        KahluaTable data = getZoneData();
        KahluaTable categories = (KahluaTable) data.rawget("categories");

        int idx = findCategoryIndex(categories, name);
        if (idx == -1) {
            return "Category '" + name + "' not found.";
        }

        removeArrayElement(categories, idx);

        KahluaTable zones = (KahluaTable) data.rawget("zones");
        zones.rawset(name, null);

        broadcast();
        return "Removed category '" + name + "' and all its zones.";
    }
}
