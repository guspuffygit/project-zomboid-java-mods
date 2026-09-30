--[[
Redirects in-game support tickets to the After the Fall Discord.

The user panel's "Add Ticket" button normally opens a text box whose OK
sends an AddTicket packet to the server. Both entry points are replaced
here: the button opens a notice with the Discord invite instead of the text
box, and the OK handler never calls addTicket, so no request leaves the
client even if something else opens the vanilla text box.

openUrl and activateSteamOverlayToWebPage only accept Indie Stone domains,
so the invite rides Steam's link filter on steamcommunity.com, which shows a
one-click "Continue to external site" page and then lands on Discord. The
Steam overlay is preferred; the desktop browser is the fallback.

Hot-reload safe: the vanilla methods are captured once and every reload
re-points the overrides.
]]

if not isClient() then
    return
end

local DISCORD_INVITE = "https://discord.gg/after-the-fall"
local FILTERED_INVITE = "https://steamcommunity.com/linkfilter/?u=" .. DISCORD_INVITE

ATFPatches_TicketsToDiscord = ATFPatches_TicketsToDiscord or {}
local Patch = ATFPatches_TicketsToDiscord

Patch.originalOnClick = Patch.originalOnClick or ISTicketsUI.onClick

function Patch.onNoticeClick(_, button)
    if button.internal ~= "YES" then
        return
    end
    if isSteamOverlayEnabled() then
        activateSteamOverlayToWebPage(FILTERED_INVITE)
    else
        openUrl(FILTERED_INVITE)
    end
end

function Patch.showNotice(ticketsUI)
    local text = "Support tickets are handled on the After the Fall Discord:\n\n"
        .. DISCORD_INVITE
        .. "\n\nOpen the Discord invite?"
    local playerNum = ticketsUI.player and ticketsUI.player:getPlayerNum() or 0
    local modal = ISModalDialog:new(0, 0, 420, 0, text, true, nil, Patch.onNoticeClick, playerNum)
    modal:initialise()
    modal:addToUIManager()
    modal:bringToTop()
end

function ISTicketsUI:onClick(button)
    if button.internal == "ADDTICKET" then
        Patch.showNotice(self)
        return
    end
    return Patch.originalOnClick(self, button)
end

function ISTicketsUI:onAddTicket(button)
    if button.internal == "OK" then
        Patch.showNotice(self)
    end
end
