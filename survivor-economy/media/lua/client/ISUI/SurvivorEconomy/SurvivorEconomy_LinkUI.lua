require("ISUI/ISPanel")
require("ISUI/ISButton")
require("ISUI/ISTextEntryBox")

ISSurvivorEconomyLinkUI = ISPanel:derive("ISSurvivorEconomyLinkUI")

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)

local SIDE_MARGIN = 12
local WINDOW_WIDTH = 320
local WINDOW_HEIGHT = 200
local CODE_MAX_LENGTH = 12

local activeWindow

function ISSurvivorEconomyLinkUI:initialise()
    ISPanel.initialise(self)

    local btnWid = 100
    local btnHgt = FONT_HGT_SMALL + 8

    local instructionsY = 10 + FONT_HGT_MEDIUM + 10
    local entryY = instructionsY + FONT_HGT_SMALL + 10
    local entryHgt = FONT_HGT_SMALL + 8

    self.codeEntry =
        ISTextEntryBox:new("", SIDE_MARGIN, entryY, self.width - (SIDE_MARGIN * 2), entryHgt)
    self.codeEntry:initialise()
    self.codeEntry:instantiate()
    self.codeEntry:setMaxTextLength(CODE_MAX_LENGTH)
    self:addChild(self.codeEntry)

    self.statusY = entryY + entryHgt + 10

    self.cancelBtn = ISButton:new(
        SIDE_MARGIN,
        self.height - SIDE_MARGIN - btnHgt,
        btnWid,
        btnHgt,
        getText("IGUI_SurvivorEconomy_LinkCancel"),
        self,
        ISSurvivorEconomyLinkUI.onClick
    )
    self.cancelBtn.internal = "CANCEL"
    self.cancelBtn:initialise()
    self.cancelBtn:instantiate()
    self.cancelBtn.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 0.9 }
    self:addChild(self.cancelBtn)

    self.submitBtn = ISButton:new(
        self.width - SIDE_MARGIN - btnWid,
        self.height - SIDE_MARGIN - btnHgt,
        btnWid,
        btnHgt,
        getText("IGUI_SurvivorEconomy_LinkSubmit"),
        self,
        ISSurvivorEconomyLinkUI.onClick
    )
    self.submitBtn.internal = "SUBMIT"
    self.submitBtn:initialise()
    self.submitBtn:instantiate()
    self.submitBtn.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 0.9 }
    self:addChild(self.submitBtn)

    self.statusText = nil
    self.statusColor = { 1, 1, 1 }
end

function ISSurvivorEconomyLinkUI:prerender()
    self:drawRect(
        0,
        0,
        self.width,
        self.height,
        self.backgroundColor.a,
        self.backgroundColor.r,
        self.backgroundColor.g,
        self.backgroundColor.b
    )
    self:drawRectBorder(
        0,
        0,
        self.width,
        self.height,
        self.borderColor.a,
        self.borderColor.r,
        self.borderColor.g,
        self.borderColor.b
    )

    local titleText = getText("IGUI_SurvivorEconomy_LinkTitle")
    self:drawText(
        titleText,
        self.width / 2 - (getTextManager():MeasureStringX(UIFont.Medium, titleText) / 2),
        10,
        1,
        1,
        1,
        1,
        UIFont.Medium
    )

    local instructions = getText("IGUI_SurvivorEconomy_LinkInstructions")
    self:drawText(instructions, SIDE_MARGIN, 10 + FONT_HGT_MEDIUM + 10, 1, 1, 1, 0.9, UIFont.Small)

    if self.statusText then
        local c = self.statusColor
        self:drawText(self.statusText, SIDE_MARGIN, self.statusY, c[1], c[2], c[3], 1, UIFont.Small)
    end
end

function ISSurvivorEconomyLinkUI:setStatus(text, r, g, b)
    self.statusText = text
    self.statusColor = { r, g, b }
end

function ISSurvivorEconomyLinkUI:onClick(button)
    if button.internal == "CANCEL" then
        self:close()
    elseif button.internal == "SUBMIT" then
        self:submit()
    end
end

function ISSurvivorEconomyLinkUI:submit()
    local raw = self.codeEntry:getText() or ""
    local code = raw:gsub("%s", ""):upper()
    if code == "" then
        return
    end
    local player = getSpecificPlayer(0)
    if player == nil then
        return
    end
    self.statusText = nil
    sendClientCommand(player, "SurvivorEconomy", "claimDiscordLink", { code = code })
end

function ISSurvivorEconomyLinkUI:onClaimResult(args)
    if args == nil then
        return
    end
    if args.ok == true then
        self:close()
        return
    end
    local reason = args.reason or "NOT_FOUND"
    local key = "IGUI_SurvivorEconomy_LinkFailed_" .. tostring(reason)
    self:setStatus(getText(key), 1, 0.5, 0.5)
end

function ISSurvivorEconomyLinkUI:close()
    self:setVisible(false)
    self:removeFromUIManager()
    activeWindow = nil
end

function ISSurvivorEconomyLinkUI:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.9 }
    o.width = width
    o.height = height
    o.moveWithMouse = true
    return o
end

function ISSurvivorEconomyLinkUI.open()
    if activeWindow then
        activeWindow:close()
    end
    local core = getCore()
    local x = (core:getScreenWidth() - WINDOW_WIDTH) / 2
    local y = (core:getScreenHeight() - WINDOW_HEIGHT) / 2
    activeWindow = ISSurvivorEconomyLinkUI:new(x, y, WINDOW_WIDTH, WINDOW_HEIGHT)
    activeWindow:initialise()
    activeWindow:addToUIManager()
    return activeWindow
end

local function onServerCommand(module, command, args)
    if module ~= "SurvivorEconomy" then
        return
    end
    if command ~= "discordLinkClaimResult" then
        return
    end
    if activeWindow then
        activeWindow:onClaimResult(args or {})
    end
end

Events.OnServerCommand.Add(onServerCommand)
