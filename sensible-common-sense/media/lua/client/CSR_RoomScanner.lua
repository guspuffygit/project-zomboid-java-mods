require "CSR_FeatureFlags"

CSR_RoomScanner = CSR_RoomScanner or {}

local MAX_SQUARES = 300
local DIRS = {
    { dx =  1, dy =  0 },
    { dx = -1, dy =  0 },
    { dx =  0, dy =  1 },
    { dx =  0, dy = -1 },
}

local function hasBlockingObject(fromSq, toSq)
    if not fromSq or not toSq then return true end
    if fromSq:isWallTo(toSq) then return true end
    if toSq:isWallTo(fromSq) then return true end
    if fromSq:isDoorTo(toSq) then return true end
    if toSq:isDoorTo(fromSq) then return true end
    if fromSq:isWindowTo(toSq) then return true end
    if toSq:isWindowTo(fromSq) then return true end
    return false
end

local function sqKey(x, y, z)
    return x .. "," .. y .. "," .. z
end

function CSR_RoomScanner.getRoomSquares(startX, startY, startZ)
    local cell = getCell and getCell() or nil
    if not cell then return {} end

    local startSq = cell:getGridSquare(startX, startY, startZ)
    if not startSq then return {} end

    local visited = {}
    local result = {}
    local queue = {}

    visited[sqKey(startX, startY, startZ)] = true
    queue[#queue + 1] = startSq

    local head = 1
    while head <= #queue do
        local sq = queue[head]
        head = head + 1
        result[#result + 1] = sq

        for _, d in ipairs(DIRS) do
            local nx = sq:getX() + d.dx
            local ny = sq:getY() + d.dy
            local nz = sq:getZ()
            local nk = sqKey(nx, ny, nz)

            if not visited[nk] then
                local nsq = cell:getGridSquare(nx, ny, nz)
                if nsq and not hasBlockingObject(sq, nsq) then
                    visited[nk] = true
                    queue[#queue + 1] = nsq
                end
            end
        end

        if #result > MAX_SQUARES then
            return nil
        end
    end

    return result
end

local function collectContainerItems(container, inventory)
    if not container then return end
    local items = container:getItems()
    if not items then return end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            local name = item.getDisplayName and item:getDisplayName() or nil
            if name and type(name) == "string" and name ~= "" then
                inventory[name] = (inventory[name] or 0) + 1
            end
            if item.IsInventoryContainer and item:IsInventoryContainer() then
                local subInv = item.getInventory and item:getInventory() or nil
                if subInv then
                    collectContainerItems(subInv, inventory)
                end
            end
        end
    end
end

function CSR_RoomScanner.scanRoom(player)
    if not CSR_FeatureFlags.isRoomScannerEnabled() then
        return nil, "Room scanner is disabled."
    end

    if not player then
        return nil, "No player."
    end

    local sq = player.getSquare and player:getSquare() or nil
    if not sq then
        return nil, "Cannot determine player position."
    end

    local squares = CSR_RoomScanner.getRoomSquares(sq:getX(), sq:getY(), sq:getZ())
    if not squares then
        return nil, "Area too large (over " .. MAX_SQUARES .. " tiles). Stand inside an enclosed room."
    end

    if #squares == 0 then
        return nil, "No room detected."
    end

    local inventory = {}

    for _, roomSq in ipairs(squares) do
        local objects = roomSq:getObjects()
        if objects then
            for i = 0, objects:size() - 1 do
                local obj = objects:get(i)
                if obj then
                    local container = obj.getContainer and obj:getContainer() or nil
                    if container then
                        collectContainerItems(container, inventory)
                    end
                end
            end
        end

        local worldObjects = roomSq.getWorldObjects and roomSq:getWorldObjects() or nil
        if worldObjects then
            for i = 0, worldObjects:size() - 1 do
                local wo = worldObjects:get(i)
                if wo then
                    local item = wo.getItem and wo:getItem() or nil
                    if item then
                        local name = item.getDisplayName and item:getDisplayName() or nil
                        if name and type(name) == "string" and name ~= "" then
                            inventory[name] = (inventory[name] or 0) + 1
                        end
                    end
                end
            end
        end
    end

    local sorted = {}
    for name, count in pairs(inventory) do
        sorted[#sorted + 1] = { name = name, count = count }
    end
    table.sort(sorted, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)

    local roomName = nil
    local roomDef = sq.getRoom and sq:getRoom() or nil
    if roomDef and roomDef.getName then
        local rn = roomDef:getName()
        if rn and type(rn) == "string" and rn ~= "" then
            roomName = rn:sub(1, 1):upper() .. rn:sub(2)
        end
    end

    return {
        items = sorted,
        squareCount = #squares,
        roomName = roomName,
    }
end

return CSR_RoomScanner
