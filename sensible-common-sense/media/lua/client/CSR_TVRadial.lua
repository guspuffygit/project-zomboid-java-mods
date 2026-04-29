-- CSR_TVRadial.lua
-- Controller-friendly radial menu for nearby TVs / VCRs / radios.
-- Reuses vanilla getPlayerRadialMenu + ISRadioAction so it works with both
-- mouse/keyboard AND any controller button bound via the standard rebind UI.

require "CSR_FeatureFlags"
require "RadioCom/ISRadioAction"
require "ISUI/ISRadialMenu"

CSR_TVRadial = CSR_TVRadial or {}

local TV_RADIAL_DEFAULT_KEY = Keyboard and Keyboard.KEY_NUMPAD9 or 73
local tvRadialKeyBind = nil

if PZAPI and PZAPI.ModOptions and PZAPI.ModOptions.create then
    local opts = PZAPI.ModOptions:create("CommonSenseRebornTVRadial",
        "Common Sense Reborn - TV Radial")
    if opts and opts.addKeyBind then
        tvRadialKeyBind = opts:addKeyBind(
            "tvRadialToggle",
            "Open TV / VCR / Radio Radial",
            TV_RADIAL_DEFAULT_KEY)
    end
end

local function getBoundKey()
    if tvRadialKeyBind and tvRadialKeyBind.getValue then
        return tvRadialKeyBind:getValue()
    end
    return TV_RADIAL_DEFAULT_KEY
end

-- Find nearest IsoWaveSignal (TV / VCR / radio) within 1 tile of the player.
local function findNearestDevice(playerObj)
    local sq = playerObj and playerObj:getCurrentSquare()
    if not sq then return nil end
    local cell = sq:getCell()
    if not cell then return nil end

    local px, py, pz = sq:getX(), sq:getY(), sq:getZ()
    local best, bestDist = nil, math.huge

    for dx = -1, 1 do
        for dy = -1, 1 do
            local s = cell:getGridSquare(px + dx, py + dy, pz)
            if s then
                local objs = s:getObjects()
                for i = 0, objs:size() - 1 do
                    local o = objs:get(i)
                    if o and instanceof(o, "IsoWaveSignal") then
                        local dd = o.getDeviceData and o:getDeviceData()
                        if dd then
                            local d = dx * dx + dy * dy
                            if d < bestDist then
                                bestDist = d
                                best = o
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

-- Walk to the device, then queue an ISRadioAction.
local function queueRadioAction(playerObj, device, mode, secondary)
    if not device or not device.getSquare then return end
    if not luautils.walkAdj(playerObj, device:getSquare(), true) then return end
    ISTimedActionQueue.add(ISRadioAction:new(mode, playerObj, device, secondary))
end

-- Power toggle.
local function onPower(playerObj, device)
    queueRadioAction(playerObj, device, "ToggleOnOff", nil)
end

-- Volume up / down (clamped 0..1, step 0.1).
local function onVolume(playerObj, device, delta)
    local dd = device and device.getDeviceData and device:getDeviceData()
    if not dd then return end
    local cur = dd.getDeviceVolume and dd:getDeviceVolume() or 0.5
    local nv = math.max(0, math.min(1, cur + delta))
    queueRadioAction(playerObj, device, "SetVolume", nv)
end

-- Insert a specific media item.
local function onInsert(playerObj, device, item)
    if not device or not device.getSquare then return end
    if not luautils.walkAdj(playerObj, device:getSquare(), true) then return end
    ISTimedActionQueue.add(ISDeviceMediaAction:new(
        playerObj,
        false,
        item,
        ISDeviceBatteryAction:getDeviceDataParameter(playerObj, device, "IsoObject")
    ))
end

-- Eject loaded media.
local function onEject(playerObj, device)
    if not device or not device.getSquare then return end
    if not luautils.walkAdj(playerObj, device:getSquare(), true) then return end
    ISTimedActionQueue.add(ISDeviceMediaAction:new(
        playerObj,
        true,
        nil,
        ISDeviceBatteryAction:getDeviceDataParameter(playerObj, device, "IsoObject")
    ))
end

-- Sub-menu for choosing which media to insert.
local function openInsertSubMenu(playerNum, playerObj, device)
    local dd = device:getDeviceData()
    local mediaType = dd:getMediaType()
    if mediaType < 0 then return end

    local menu = getPlayerRadialMenu(playerNum)
    menu:clear()

    local inv = playerObj:getInventory():getItems()
    local count = 0
    for i = 0, inv:size() - 1 do
        local it = inv:get(i)
        if it and it.isRecordedMedia and it:isRecordedMedia()
           and it.getMediaType and it:getMediaType() == mediaType then
            menu:addSlice(it:getDisplayName(), nil, onInsert, playerObj, device, it)
            count = count + 1
        end
    end

    if count == 0 then
        menu:addSlice("(no compatible media)", nil, function() end)
    end

    -- Re-center & re-show on top of the same radial widget.
    local x = getPlayerScreenLeft(playerNum) + getPlayerScreenWidth(playerNum) / 2
    local y = getPlayerScreenTop(playerNum)  + getPlayerScreenHeight(playerNum) / 2
    menu:setX(x - menu:getWidth() / 2)
    menu:setY(y - menu:getHeight() / 2)
    menu:addToUIManager()
    if JoypadState.players[playerNum + 1] then
        setJoypadFocus(playerNum, menu)
    end
end

local function openMainRadial(playerNum, playerObj, device)
    local dd = device:getDeviceData()
    local menu = getPlayerRadialMenu(playerNum)
    menu:clear()

    local powerLabel = (dd.getIsTurnedOn and dd:getIsTurnedOn()) and "Power: ON" or "Power: OFF"
    menu:addSlice(powerLabel, nil, onPower, playerObj, device)

    -- Volume (only meaningful when on).
    menu:addSlice("Volume +", nil, onVolume, playerObj, device,  0.1)
    menu:addSlice("Volume -", nil, onVolume, playerObj, device, -0.1)

    -- Media slots: only show if the device has a media slot.
    local mediaType = dd.getMediaType and dd:getMediaType() or -1
    if mediaType >= 0 then
        if dd.hasMedia and dd:hasMedia() then
            menu:addSlice("Eject", nil, onEject, playerObj, device)
        else
            menu:addSlice("Insert...", nil, openInsertSubMenu, playerNum, playerObj, device)
        end
    end

    local x = getPlayerScreenLeft(playerNum) + getPlayerScreenWidth(playerNum) / 2
    local y = getPlayerScreenTop(playerNum)  + getPlayerScreenHeight(playerNum) / 2
    menu:setX(x - menu:getWidth() / 2)
    menu:setY(y - menu:getHeight() / 2)
    menu:addToUIManager()

    if JoypadState.players[playerNum + 1] then
        setJoypadFocus(playerNum, menu)
    end
end

function CSR_TVRadial.open(playerNum)
    if not CSR_FeatureFlags or not CSR_FeatureFlags.isTVRadialEnabled
        or not CSR_FeatureFlags.isTVRadialEnabled() then
        return
    end

    local playerObj = getSpecificPlayer(playerNum or 0)
    if not playerObj or playerObj:isDead() then return end

    local device = findNearestDevice(playerObj)
    if not device then
        if HaloTextHelper and HaloTextHelper.addBadText then
            HaloTextHelper.addBadText(playerObj, "No TV / VCR / radio nearby")
        end
        return
    end

    openMainRadial(playerNum or 0, playerObj, device)
end

local function onKeyPressed(key)
    if key ~= getBoundKey() then return end
    CSR_TVRadial.open(0)
end

Events.OnKeyPressed.Add(onKeyPressed)

return CSR_TVRadial
