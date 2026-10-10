-- Add an entry point to the player's normal Health pane, including torn-off panes.
-- The native pane still owns its sizing, treatment controls and joypad handling.
require("XpSystem/ISUI/ISHealthPanel")
require("XpSystem/ISUI/ISCharacterInfoWindow")
require("ISUI/ISButton")

ATFPlayerMiniHUDHealthOpener = ATFPlayerMiniHUDHealthOpener or {}
local O = ATFPlayerMiniHUDHealthOpener
local SPACING = 10

local function ownPane(playerNum)
    local player = getSpecificPlayer(playerNum)
    if not player or not player:isLocalPlayer() or player:isDead() then
        return nil
    end
    local info = getPlayerInfoPanel and getPlayerInfoPanel(playerNum)
    local pane = info and info.healthView
    if pane and pane.character == player and not pane.otherPlayer then
        return pane, player
    end
end

local function toggle(pane)
    local current = ownPane(pane.playerNum)
    if current ~= pane then
        return false
    end
    if ATFCombatHealth and ATFCombatHealth.toggle then
        return ATFCombatHealth.toggle(pane.playerNum)
    end
    return false
end

local function layout(pane)
    local button = pane.atfMiniHUDButton
    local title = getText("UI_ATFCombatHealth_MiniHUD")
    local width = math.ceil(getTextManager():MeasureStringX(UIFont.Small, title) + SPACING * 2)
    -- Native Health reserves the Fitness row using the font height captured at
    -- Lua load. Match that row even if fonts change before the native UI reloads.
    local height = pane.fitness:getHeight()
    local x, y = pane.fitness:getRight() + SPACING, pane.healthPanel:getY()
    local previous = pane.atfMiniHUDGeometry
    if
        previous
        and previous.x == x
        and previous.y == y
        and previous.width == width
        and previous.height == height
        and previous.title == title
    then
        return
    end
    pane.atfMiniHUDGeometry = { x = x, y = y, width = width, height = height, title = title }
    button:setTitle(title)
    button:setX(x)
    button:setY(y)
    button:setWidth(width)
    button:setHeight(height)
    pane.atfMiniHUDWidthMin = x + width + SPACING + 1
    -- The native update computes the complete pane/parent width. Clamp that
    -- calculation rather than shrinking and growing the same window twice.
    if pane:getWidth() < pane.atfMiniHUDWidthMin then
        pane:setWidthAndParentWidth(pane.atfMiniHUDWidthMin)
    end
end

function O.bind(playerNum)
    local pane = ownPane(playerNum)
    if not pane or not pane.fitness or not pane.healthPanel then
        local info = getPlayerInfoPanel and getPlayerInfoPanel(playerNum)
        local previous = info and info.healthView and info.healthView.atfMiniHUDButton
        if previous and previous:getIsVisible() then
            previous:setVisible(false)
        end
        return false
    end
    if not pane.atfMiniHUDButton then
        local button = ISButton:new(0, 0, 1, 1, getText("UI_ATFCombatHealth_MiniHUD"), pane, toggle)
        button:initialise()
        button:instantiate()
        button:setAnchorLeft(true)
        button:setAnchorRight(false)
        button:setAnchorTop(true)
        button:setAnchorBottom(false)
        pane:addChild(button)
        pane.atfMiniHUDButton = button
        local nativeWidth = pane.setWidthAndParentWidth
        pane.setWidthAndParentWidth = function(self, width, ...)
            if ownPane(self.playerNum) == self then
                width = math.max(width, self.atfMiniHUDWidthMin or 0)
            end
            return nativeWidth(self, width, ...)
        end
    end
    if not pane.atfMiniHUDButton:getIsVisible() then
        pane.atfMiniHUDButton:setVisible(true)
    end
    layout(pane)
    return true
end

function O.clear(panel)
    if panel then
        panel.atfHealthOwner = nil
        panel.atfHealthPane = nil
        panel.atfHealthWasVisible = nil
    end
end

function O.observe(panel)
    if not panel then
        return false
    end
    local pane, player = ownPane(panel.playerNum)
    if not pane or player ~= panel.player then
        O.clear(panel)
        return false
    end
    local owner = pane.parent
    if not owner then
        O.clear(panel)
        return false
    end
    -- Native tab tear-off reparents the same pane into a collapsable window.
    -- Parent identity changes reset the baseline; hiding the old window during
    -- that operation must not be interpreted as closing the Health window.
    local steps = 0
    while owner.parent do
        owner = owner.parent
        steps = steps + 1
        if steps > 32 then
            O.clear(panel)
            return false
        end
    end
    local visible = owner:getIsVisible()
    if panel.atfHealthPane ~= pane or panel.atfHealthOwner ~= owner then
        panel.atfHealthPane = pane
        panel.atfHealthOwner = owner
        panel.atfHealthWasVisible = visible
        return false
    end
    local closed = panel.atfHealthWasVisible == true and not visible
    panel.atfHealthWasVisible = visible
    return closed
end

if not O.installed then
    O.installed = true
    local createChildren = ISHealthPanel.createChildren
    local function pack(...)
        return { n = select("#", ...), ... }
    end
    function ISHealthPanel:createChildren(...)
        local result = pack(createChildren(self, ...))
        if ownPane(self.playerNum) == self then
            O.bind(self.playerNum)
        end
        return unpack(result, 1, result.n)
    end
end

if not O.startupInstalled then
    O.startupInstalled = true
    local createChildren = ISCharacterInfoWindow.createChildren
    function ISCharacterInfoWindow:createChildren(...)
        local player = getSpecificPlayer(self.playerNum)
        if
            self.javaObject
            and not self.panel
            and self.visibleOnStartup == false
            and player
            and player:isLocalPlayer()
        then
            -- Java UIElement starts visible. Native createChildren captures
            -- that flag after RestoreLayout, making a new resolution open the
            -- full character window even though its constructor requests a
            -- hidden startup. Set only the new-window default; native saved
            -- visibility, active tabs and torn-off panes still restore normally.
            self.javaObject:setVisible(false)
        end
        return createChildren(self, ...)
    end
end

return O
