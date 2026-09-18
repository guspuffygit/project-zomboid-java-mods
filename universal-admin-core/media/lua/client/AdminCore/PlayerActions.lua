require("AdminCore/AdminTools")
require("AdminCore/Tools")
require("ISUI/PlayerStats/ISPlayerStatsUI")
local C = AdminCore
if C.playerActionsInstalled then
    return
end
C.playerActionsInstalled = true

local previous = ISUsersList.doContextMenu
function ISUsersList:doContextMenu(item, x, y)
    if not item then
        return
    end
    previous(self, item, x, y)
    local context = getPlayerContextMenu(self.player:getPlayerNum())
    local username = item:getUsername()
    local playerMenu = C.submenu(context, "Player")
    if Clipboard then
        playerMenu:addOption("Copy username", nil, function()
            Clipboard.setClipboard(username)
        end)
        local steamid = item:getSteamid()
        if steamid and steamid ~= "" then
            playerMenu:addOption("Copy SteamID", nil, function()
                Clipboard.setClipboard(steamid)
            end)
        end
    end
    local ping = playerMenu:addOption("Ping: " .. tostring(item:getPing()), nil, nil)
    ping.notAvailable = true
    if item:isOnline() and C.allowed(Capability.CanSeePlayersStats) then
        local option = playerMenu:addOption("Stats / traits / skills...", nil, function()
            if not C.allowed(Capability.CanSeePlayersStats) then
                return
            end
            local target = getPlayerFromUsername(username)
            if not target then
                return C.message(
                    "This player is outside your client's loaded area. Move near them to inspect live stats."
                )
            end
            if ISPlayerStatsUI.instance then
                ISPlayerStatsUI.instance:close()
            end
            local ui = ISPlayerStatsUI:new(
                50,
                50,
                800 + (getCore():getOptionFontSizeReal() * 50),
                800,
                target,
                getPlayer()
            )
            ui:initialise()
            ui:addToUIManager()
            ui:setVisible(true)
        end)
        option.notAvailable = getPlayerFromUsername(username) == nil
        if option.notAvailable then
            local tip = ISWorldObjectContextMenu.addToolTip()
            tip.description = "Live stats require this player to be loaded by your client."
            option.toolTip = tip
        end
    end
    context:calcHeight()
    context:setWidth(context:calcWidth())
end
