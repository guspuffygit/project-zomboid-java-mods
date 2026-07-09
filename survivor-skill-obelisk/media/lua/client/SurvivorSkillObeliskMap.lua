--
-- SurvivorSkillObeliskMap.lua
-- Draws every placed obelisk as a gold dot on the in-game world map with a
-- label underneath ("<Perk> Obelisk" when configured, "Obelisk" otherwise).
-- Positions and types live server-side in obelisk_types (kept in sync by
-- ObeliskLifecycleHandler + SetObeliskTypeHandler); the client receives a full
-- list once per session and per-obelisk deltas thereafter.
--

require("ISUI/Maps/ISWorldMap")

local MODULE = "SurvivorSkillObelisk"
local LIST_COMMAND = "listAllObelisks"
local LIST_REPLY = "obeliskList"
local UPDATED_REPLY = "obeliskUpdated"
local REMOVED_REPLY = "obeliskRemoved"
local NONE_TYPE = "None"

-- SkillObelisk.MapObeliskVisibility enum values (1-based, matches sandbox-options.txt).
local VISIBILITY_ALL = 1
local VISIBILITY_GENERAL_ONLY = 2
local VISIBILITY_NONE = 3

local DOT_R, DOT_G, DOT_B = 52 / 255, 88 / 255, 235 / 255
local DOT_ALPHA_CONFIGURED = 0.95
local DOT_ALPHA_UNCONFIGURED = 0.55
-- Fixed pixel size so the dot is visible at every zoom level. World-tile-sized
-- dots disappear when the map is zoomed out to show the whole world.
local DOT_SIZE_PX = 8

---------------------------------------------------------------------------
-- Cache
---------------------------------------------------------------------------

-- Preserve cache across reloads so the map doesn't flash empty on /reload.
if not SurvivorSkillObeliskMapCache then
    SurvivorSkillObeliskMapCache = {
        -- keyed by "x,y,z" -> {x=,y=,z=,type=}
        obelisks = {},
        version = 0,
    }
end

local function obeliskKey(x, y, z)
    return tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
end

local function bumpVersion()
    SurvivorSkillObeliskMapCache.version = SurvivorSkillObeliskMapCache.version + 1
end

---------------------------------------------------------------------------
-- Server replies
---------------------------------------------------------------------------

local function onObeliskList(args)
    local obelisks = {}
    if args and args.rows then
        local count = args.count or 0
        for i = 1, count do
            local r = args.rows[i]
            if r and r.x and r.y and r.z then
                obelisks[obeliskKey(r.x, r.y, r.z)] = {
                    x = r.x,
                    y = r.y,
                    z = r.z,
                    type = r.type or NONE_TYPE,
                }
            end
        end
    end
    SurvivorSkillObeliskMapCache.obelisks = obelisks
    bumpVersion()
end

local function onObeliskUpdated(args)
    if args == nil or args.x == nil or args.y == nil or args.z == nil then
        return
    end
    SurvivorSkillObeliskMapCache.obelisks[obeliskKey(args.x, args.y, args.z)] = {
        x = args.x,
        y = args.y,
        z = args.z,
        type = args.type or NONE_TYPE,
    }
    bumpVersion()
end

local function onObeliskRemoved(args)
    if args == nil or args.x == nil or args.y == nil or args.z == nil then
        return
    end
    SurvivorSkillObeliskMapCache.obelisks[obeliskKey(args.x, args.y, args.z)] = nil
    bumpVersion()
end

-- Remove previous handler on reload to avoid duplicates.
if SurvivorSkillObeliskMapCache._onServerCommand then
    Events.OnServerCommand.Remove(SurvivorSkillObeliskMapCache._onServerCommand)
end

local function onServerCommand(module, command, args)
    if module ~= MODULE then
        return
    end
    if command == LIST_REPLY then
        onObeliskList(args)
    elseif command == UPDATED_REPLY then
        onObeliskUpdated(args)
    elseif command == REMOVED_REPLY then
        onObeliskRemoved(args)
    end
end

SurvivorSkillObeliskMapCache._onServerCommand = onServerCommand
Events.OnServerCommand.Add(onServerCommand)

---------------------------------------------------------------------------
-- Sync request on first tick
---------------------------------------------------------------------------

local function requestSync()
    local player = getSpecificPlayer(0)
    if player == nil then
        return
    end
    sendClientCommand(player, MODULE, LIST_COMMAND, {})
    Events.OnTick.Remove(requestSync)
end

Events.OnTick.Add(requestSync)

---------------------------------------------------------------------------
-- Filter checkbox
---------------------------------------------------------------------------

local filterEnabled = true

local filterOption = {}
function filterOption:getName()
    return "Skill Obelisks"
end
function filterOption:getType()
    return "boolean"
end
function filterOption:getValue()
    return filterEnabled
end
function filterOption:setValue(v)
    filterEnabled = v
end

WorldMapOptions_visibleOptionsHooks = WorldMapOptions_visibleOptionsHooks or {}

table.insert(WorldMapOptions_visibleOptionsHooks, function(result)
    table.insert(result, filterOption)
end)

-- Same shared patch used by zone-marker and AVCS. First mod to load installs it;
-- everyone else just pushes hooks into the shared table.
if not WorldMapOptions._visibleOptionsHooksPatched then
    local originalGetVisibleOptions = WorldMapOptions.getVisibleOptions
    function WorldMapOptions:getVisibleOptions()
        local result = originalGetVisibleOptions(self)
        for _, hook in ipairs(WorldMapOptions_visibleOptionsHooks) do
            hook(result)
        end
        return result
    end

    local originalSynchUI = WorldMapOptions.synchUI
    function WorldMapOptions:synchUI()
        local visibleOptions = self:getVisibleOptions()
        local boolCount = 0
        for _, opt in ipairs(visibleOptions) do
            if opt:getType() == "boolean" then
                boolCount = boolCount + 1
            end
        end
        if boolCount ~= (self._lastBoolCount or -1) then
            local children = {}
            for k, v in pairs(self:getChildren()) do
                table.insert(children, v)
            end
            for _, child in ipairs(children) do
                self:removeChild(child)
            end
            self:createChildren()
            self._lastBoolCount = boolCount
        end
        originalSynchUI(self)
    end

    WorldMapOptions._visibleOptionsHooksPatched = true
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)

local function obeliskLabel(typeId)
    if typeId == nil or typeId == "" or typeId == NONE_TYPE then
        return "Obelisk", false
    end
    local perk = PerkFactory.Perks.FromString(typeId)
    local perkName = perk and perk:getName() or typeId
    return perkName .. " Obelisk", true
end

local function renderObeliskLabel(javaObject, sx, sy, name)
    local textW = getTextManager():MeasureStringX(UIFont.Small, name) + 16
    local lineH = FONT_HGT_SMALL
    local boxH = math.ceil(lineH * 1.25)
    javaObject:DrawTextureScaledColor(nil, sx - textW / 2, sy + 4, textW, boxH, 0.0, 0.0, 0.0, 0.55)
    javaObject:DrawTextCentre(name, sx, sy + 4 + (boxH - lineH) / 2, 1, 1, 1, 1)
end

local function renderObelisk(mapUI, obelisk)
    local api = mapUI.mapAPI
    local javaObject = mapUI.javaObject

    local cx = PZMath.floor(api:worldToUIX(obelisk.x, obelisk.y))
    local cy = PZMath.floor(api:worldToUIY(obelisk.x, obelisk.y))

    local label, configured = obeliskLabel(obelisk.type)
    local alpha = configured and DOT_ALPHA_CONFIGURED or DOT_ALPHA_UNCONFIGURED
    local half = DOT_SIZE_PX / 2

    javaObject:DrawTextureScaledColor(
        nil,
        cx - half,
        cy - half,
        DOT_SIZE_PX,
        DOT_SIZE_PX,
        DOT_R,
        DOT_G,
        DOT_B,
        alpha
    )

    renderObeliskLabel(javaObject, cx, cy + half, label)
end

-- Sandbox-synced to the client by PZ; nil before world load, so guard and fall
-- back to "show all" (option1) to match the compiled-in default.
local function getVisibilityMode()
    local sv = SandboxVars and SandboxVars.SkillObelisk
    local mode = sv and sv.MapObeliskVisibility
    if type(mode) ~= "number" then
        return VISIBILITY_ALL
    end
    return mode
end

local function shouldRenderObelisk(obelisk, mode)
    if mode == VISIBILITY_NONE then
        return false
    end
    if mode == VISIBILITY_GENERAL_ONLY then
        local t = obelisk.type
        return t == nil or t == "" or t == NONE_TYPE
    end
    return true
end

local originalRender = ISWorldMap.render

function ISWorldMap:render()
    originalRender(self)

    if not filterEnabled then
        return
    end

    local mode = getVisibilityMode()
    if mode == VISIBILITY_NONE then
        return
    end

    for _, obelisk in pairs(SurvivorSkillObeliskMapCache.obelisks) do
        if shouldRenderObelisk(obelisk, mode) then
            renderObelisk(self, obelisk)
        end
    end
end
