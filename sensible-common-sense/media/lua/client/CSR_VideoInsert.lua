require "CSR_FeatureFlags"

CSR_VideoInsert = CSR_VideoInsert or {}

if not CSR_FeatureFlags then
    return CSR_VideoInsert
end

-- Returns true if the player is adjacent to the device (proximity check only, no walk queued).
local function playerCanReachTV(playerObj, device)
    return device
        and device.getSquare
        and device:getSquare() ~= nil
        and luautils.walkAdj(playerObj, device:getSquare(), false)
end

local function getDeviceName(deviceData, fallback)
    if deviceData and deviceData.getDeviceName then
        local name = deviceData:getDeviceName()
        if name and name ~= "" then return name end
    end
    return fallback or "Device"
end

local function createTooltip(name, description)
    local tooltip = ISToolTip:new()
    tooltip:initialise()
    tooltip:setVisible(false)
    tooltip:setName(name or "")
    tooltip.description = description or ""
    tooltip.maxLineWidth = 512
    return tooltip
end

-- Collect all inventory items compatible with the device's media slot.
local function getCompatibleMedia(playerObj, deviceData)
    local inv = playerObj:getInventory()
    local mediaType = deviceData:getMediaType()
    local results = {}
    local items = inv:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item
            and item.isRecordedMedia and item:isRecordedMedia()
            and item.getMediaType and item:getMediaType() == mediaType
        then
            results[#results + 1] = item
        end
    end
    return results
end

-- Context menu callback: eject the loaded tape/disc.
local function doEject(playerObj, device)
    if not luautils.walkAdj(playerObj, device:getSquare(), true) then return end
    ISTimedActionQueue.add(ISDeviceMediaAction:new(
        playerObj,
        true,
        nil,
        ISDeviceBatteryAction:getDeviceDataParameter(playerObj, device, "IsoObject")
    ))
end

-- Context menu callback: insert a specific item into the device.
local function doInsert(playerObj, device, item)
    if not luautils.walkAdj(playerObj, device:getSquare(), true) then return end
    ISTimedActionQueue.add(ISDeviceMediaAction:new(
        playerObj,
        false,
        item,
        ISDeviceBatteryAction:getDeviceDataParameter(playerObj, device, "IsoObject")
    ))
end

function CSR_VideoInsert.addWorldContext(playerNum, context, worldobjects, test)
    if test or not CSR_FeatureFlags.isVideoInsertEnabled() then return end

    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj or not context or not worldobjects then return end

    local seen = {}
    for _, object in ipairs(worldobjects) do
        if object and instanceof(object, "IsoWaveSignal") and not seen[object] then
            local deviceData = object:getDeviceData()
            if deviceData
                and deviceData:getMediaType() >= 0
                and playerCanReachTV(playerObj, object)
            then
                seen[object] = true
                local devName = getDeviceName(deviceData, "TV")

                if deviceData:hasMedia() then
                    -- Media already loaded — offer eject (controller-friendly).
                    context:addOption("Eject Video", playerObj, doEject, object)
                else
                    local mediaItems = getCompatibleMedia(playerObj, deviceData)
                    if #mediaItems > 0 then
                        -- One or more compatible items found: sub-menu per item.
                        local root = context:addOption("Insert Video", playerObj, nil)
                        local subMenu = ISContextMenu:getNew(context)
                        context:addSubMenu(root, subMenu)
                        for _, item in ipairs(mediaItems) do
                            subMenu:addOption(item:getDisplayName(), playerObj, doInsert, object, item)
                        end
                    else
                        -- No compatible media: greyed-out option with tooltip.
                        local opt = context:addOption("Insert Video", playerObj, nil)
                        opt.notAvailable = true
                        opt.toolTip = createTooltip(devName, "No compatible media in inventory.")
                    end
                end
            end
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(CSR_VideoInsert.addWorldContext)

return CSR_VideoInsert
