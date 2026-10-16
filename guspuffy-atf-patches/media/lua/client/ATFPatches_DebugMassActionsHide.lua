--[[
Hides two debug menu options that act on the whole server with one click.

Debug > Animals > Remove All sends "/remove animals", which deletes every
animal on the server rather than the ones near the admin. The server patch
RemoveAnimalsCommandBlockPatch also refuses that command.

Debug > Players > Teleport Players pulls every online player to the admin.
It sends one ordinary teleport request per player, which the server can't
tell apart from a single admin teleport, so the client handler is also
replaced with a no-op.

Hot-reload safe: the vanilla functions are captured once and every reload
re-points the overrides.
]]

require("DebugUIs/DebugContextMenu")

ATFPatches_DebugMassActionsHide = ATFPatches_DebugMassActionsHide or {}
local Patch = ATFPatches_DebugMassActionsHide

Patch.originalDoDebugAnimalMenu = Patch.originalDoDebugAnimalMenu
    or DebugContextMenu.doDebugAnimalMenu
Patch.originalDoDebugPlayerMenu = Patch.originalDoDebugPlayerMenu
    or DebugContextMenu.doDebugPlayerMenu

local function removeSubMenuOption(context, subMenuKey, optionKey)
    local option = context:getOptionFromName(getText(subMenuKey))
    if not option or not option.subOption then
        return
    end
    local subMenu = context:getSubMenu(option.subOption)
    if subMenu then
        subMenu:removeOptionByName(getText(optionKey))
    end
end

function Patch.doDebugAnimalMenu(playerObj, context, worldobjects, test, square)
    Patch.originalDoDebugAnimalMenu(playerObj, context, worldobjects, test, square)
    removeSubMenuOption(context, "IGUI_DebugContext_Animals", "IGUI_DebugContext_RemoveAll")
end

function Patch.doDebugPlayerMenu(playerObj, context, worldobjects)
    Patch.originalDoDebugPlayerMenu(playerObj, context, worldobjects)
    removeSubMenuOption(context, "IGUI_DebugContext_Players", "IGUI_DebugContext_TeleportPlayers")
end

function Patch.onTeleportPlayers() end

DebugContextMenu.doDebugAnimalMenu = Patch.doDebugAnimalMenu
DebugContextMenu.doDebugPlayerMenu = Patch.doDebugPlayerMenu
DebugContextMenu.onTeleportPlayers = Patch.onTeleportPlayers
