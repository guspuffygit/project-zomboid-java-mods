require("ISUI/Maps/ISWorldMap")

--
-- getDetailedVehicleList - moved from jar-injected Lua to vanilla client Lua
--

local function getVehicleDisplayName(name)
    local cleanName = string.gsub(name, "^Base%.", "")
    local translationKey = "IGUI_VehicleName" .. cleanName
    local displayName = getText(translationKey)
    if displayName == translationKey then
        return name
    end
    return displayName
end

local function getDetailedVehicleList()
    local response = {}

    if AVCS == nil or AVCS.dbByPlayerID == nil or AVCS.dbByVehicleSQLID == nil then
        return response
    end

    local function addVehiclesForPlayer(playerID, carType)
        local playerVehicles = AVCS.dbByPlayerID[playerID]
        if playerVehicles then
            for vehicleID, _ in pairs(playerVehicles) do
                if vehicleID ~= "LastKnownLogonTime" then
                    local vehicleData = AVCS.dbByVehicleSQLID[vehicleID]
                    if vehicleData then
                        table.insert(response, {
                            vehicleID = vehicleID,
                            ownerPlayerId = vehicleData.OwnerPlayerID,
                            claimDateTime = vehicleData.ClaimDateTime,
                            carModel = vehicleData.CarModel,
                            displayName = getVehicleDisplayName(vehicleData.CarModel),
                            lastLocationX = vehicleData.LastLocationX,
                            lastLocationY = vehicleData.LastLocationY,
                            lastLocationUpdateTime = vehicleData.LastLocationUpdateDateTime,
                            carType = carType,
                        })
                    end
                end
            end
        end
    end

    local player = getPlayer()
    if player == nil then
        return response
    end

    local currentPlayer = player:getUsername()
    addVehiclesForPlayer(currentPlayer, "personal")

    if SafeHouse then
        local safehouseObj = SafeHouse.hasSafehouse(player)
        if safehouseObj then
            local members = safehouseObj:getPlayers()
            for i = 0, members:size() - 1 do
                local memberID = members:get(i)
                if memberID ~= currentPlayer then
                    addVehiclesForPlayer(memberID, "safehouse")
                end
            end
        end
    end

    if Faction then
        local factionObj = Faction.getPlayerFaction(player)
        if factionObj then
            local ownerID = factionObj:getOwner()
            if ownerID ~= currentPlayer then
                addVehiclesForPlayer(ownerID, "faction")
            end

            local members = factionObj:getPlayers()
            for i = 0, members:size() - 1 do
                local memberID = members:get(i)
                if memberID ~= currentPlayer and memberID ~= ownerID then
                    addVehiclesForPlayer(memberID, "faction")
                end
            end
        end
    end

    return response
end

--
-- Filter option for map UI
--

local avcsFilterEnabled = true

local avcsFilterOption = {}
function avcsFilterOption:getName()
    return "Claimed Vehicles"
end
function avcsFilterOption:getType()
    return "boolean"
end
function avcsFilterOption:getValue()
    return avcsFilterEnabled
end
function avcsFilterOption:setValue(v)
    avcsFilterEnabled = v
end

WorldMapOptions_visibleOptionsHooks = WorldMapOptions_visibleOptionsHooks or {}

table.insert(WorldMapOptions_visibleOptionsHooks, function(result)
    table.insert(result, avcsFilterOption)
end)

-- Monkey-patch getVisibleOptions/synchUI to iterate the shared hooks table.
-- Multiple mods add hooks to the same table; only the first mod to load does the patch.
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

--
-- Vehicle point rendering
--

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)

local function renderVehicleLabel(javaObject, api, worldX, worldY, name)
    local sx = PZMath.floor(api:worldToUIX(worldX, worldY))
    local sy = PZMath.floor(api:worldToUIY(worldX, worldY))
    local textW = getTextManager():MeasureStringX(UIFont.Small, name) + 16
    local lineH = FONT_HGT_SMALL
    local boxH = math.ceil(lineH * 1.25)
    -- background
    javaObject:DrawTextureScaledColor(nil, sx - textW / 2, sy + 4, textW, boxH, 0.5, 0.5, 0.5, 0.5)
    -- text
    javaObject:DrawTextCentre(name, sx, sy + 4 + (boxH - lineH) / 2, 1, 1, 1, 1)
end

local function renderVehiclePoint(mapUI, vehicle)
    local api = mapUI.mapAPI
    local javaObject = mapUI.javaObject

    local worldX = vehicle.lastLocationX
    local worldY = vehicle.lastLocationY
    if worldX == nil or worldY == nil then
        return
    end

    -- dot: draw a 1x1 world-unit square
    local x1 = api:worldToUIX(worldX, worldY)
    local y1 = api:worldToUIY(worldX, worldY)
    local x2 = api:worldToUIX(worldX + 1, worldY + 1)
    local y2 = api:worldToUIY(worldX + 1, worldY + 1)

    local r, g, b, a = 0, 1, 0, 0.9
    if vehicle.carType == "faction" then
        r, g, b = 0.2, 0.6, 1
    elseif vehicle.carType == "safehouse" then
        r, g, b = 1, 0.8, 0
    end

    javaObject:DrawTextureScaledColor(
        nil,
        PZMath.floor(x1),
        PZMath.floor(y1),
        x2 - x1,
        y2 - y1,
        r,
        g,
        b,
        a
    )

    renderVehicleLabel(javaObject, api, worldX, worldY, vehicle.displayName)
end

--
-- Patch ISWorldMap:render()
--

local originalRender = ISWorldMap.render

function ISWorldMap:render()
    originalRender(self)

    if not avcsFilterEnabled then
        return
    end

    local vehicles = getDetailedVehicleList()
    for _, vehicle in ipairs(vehicles) do
        renderVehiclePoint(self, vehicle)
    end
end
