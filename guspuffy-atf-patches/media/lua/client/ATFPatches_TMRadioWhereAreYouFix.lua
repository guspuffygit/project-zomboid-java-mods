--[[
True Music Radio (workshop 2688884420 family) has a typo in
TMRadio.whereAreYou(device, index): the container-fallback branch reads
`t.device:getOutermostContainer():...` but no local `t` is declared in that
scope, so `t` resolves to a nil global and the assignment throws
"attempted index: device of non-table: null".

The branch fires whenever a Radio-typed item (any walkie-talkie, including
Premium Tech and Tactical from the workshop content packs) is transferred
through ISInventoryTransferAction:perform into a container the mod treats as
"inventory device" while the item isn't on a square and isn't in player
inventory. The mod's own perform override calls whereAreYou(self.item) on
every retry, so the timed-action framework re-invokes it every frame until
the player hits ESC - the "ramping errors" symptom in the field report
(2026-08-15 log rf4cpa9ns5).

Fix reimplements whereAreYou with the same branch order and fallbacks as
upstream, substituting `device` for the phantom `t.device`. Idempotent via
TMRadio.__atfWhereAreYouShimApplied so hot-reload starts from originals.
]]

if not isClient() then
    return
end

local function applyPatch()
    if type(TMRadio) ~= "table" or type(TMRadio.whereAreYou) ~= "function" then
        return false
    end
    if TMRadio.__atfWhereAreYouShimApplied then
        return true
    end
    TMRadio.__atfWhereAreYouShimApplied = true

    TMRadio.whereAreYou = function(device, index)
        if not device then
            return { x = 0, y = 0, z = 0 }
        end

        local deviceData = device.getDeviceData and device:getDeviceData() or nil
        if not deviceData then
            return { x = 0, y = 0, z = 0 }
        end

        local x, y, z

        if deviceData.isVehicleDevice and deviceData:isVehicleDevice() then
            local parent = deviceData:getParent()
            local vehicle = parent and parent:getVehicle()
            if vehicle then
                x, y, z = vehicle:getX(), vehicle:getY(), vehicle:getZ()
            end
        end

        if not x and device.isInPlayerInventory and device:isInPlayerInventory() then
            local player = getPlayer()
            if player then
                x, y, z = player:getX(), player:getY(), player:getZ()
            end
        end

        if not x and device.getSquare and device:getSquare() then
            x, y, z = device:getX(), device:getY(), device:getZ()
        end

        if not x and device.getSquare and device:getSquare() then
            local sq = device:getSquare()
            x, y, z = sq:getX(), sq:getY(), sq:getZ()
        end

        if not x and deviceData.isInventoryDevice and deviceData:isInventoryDevice()
                and device.getOutermostContainer and device:getOutermostContainer() then
            local outer = device:getOutermostContainer()
            local parent = outer.getParent and outer:getParent() or nil
            if parent and parent.getX then
                x, y, z = parent:getX(), parent:getY(), parent:getZ()
            end
        end

        if not x then
            local last = TMRadio.getData and TMRadio.getData(deviceData) or nil
            if last then
                x, y, z = last.x, last.y, last.z
            else
                x, y, z = 0, 0, 0
            end
        end

        return { x = x, y = y, z = z }
    end

    print("[ATFPatches] TMRadio.whereAreYou container-branch typo shim applied.")
    return true
end

local function onFirstTick()
    Events.OnTick.Remove(onFirstTick)
    applyPatch()
end

Events.OnTick.Add(onFirstTick)
