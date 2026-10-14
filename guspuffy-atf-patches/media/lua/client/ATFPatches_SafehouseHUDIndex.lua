-- Preserve exact ATF boundary checks and first-match semantics, with a local index.
ATFSafehouseHUDIndex = ATFSafehouseHUDIndex or {}
local H = ATFSafehouseHUDIndex
function H.install()
    if not _G.GetSafehouseList or not _G.IsPlayerInSafehouse or not ATF or not ATF.HUD then
        return
    end
    if H.installed then
        return
    end
    H.installed = true
    local buckets, large = {}, {}
    function GetSafehouseList()
        PlayerSafehouses, buckets, large = {}, {}, {}
        local list = SafeHouse.getSafehouseList()
        for i = 0, list:size() - 1 do
            local house = list:get(i)
            local box = {
                xStart = house:getX(),
                xEnd = house:getX2(),
                yStart = house:getY(),
                yEnd = house:getY2(),
            }
            PlayerSafehouses[#PlayerSafehouses + 1] = box
            local x1, x2 = math.floor(box.xStart / 100), math.floor(box.xEnd / 100)
            local y1, y2 = math.floor(box.yStart / 100), math.floor(box.yEnd / 100)
            -- Admin-created giant areas must not allocate an enormous index.
            if (x2 - x1 + 1) * (y2 - y1 + 1) > 64 then
                large[#large + 1] = box
            else
                for x = x1, x2 do
                    for y = y1, y2 do
                        local key = x .. ":" .. y
                        buckets[key] = buckets[key] or {}
                        buckets[key][#buckets[key] + 1] = box
                    end
                end
            end
        end
    end
    local function contains(list, x, y)
        for _, box in ipairs(list) do
            if x >= box.xStart and x <= box.xEnd and y >= box.yStart and y <= box.yEnd then
                return true
            end
        end
        return false
    end
    function IsPlayerInSafehouse(x, y)
        local candidates = buckets[math.floor(x / 100) .. ":" .. math.floor(y / 100)]
        return (candidates and contains(candidates, x, y)) or contains(large, x, y)
    end
    GetSafehouseList()
    ATF.HUD.InvalidateCache()
end
if H.hook then
    Events.OnGameStart.Remove(H.hook)
end
H.hook = H.install
Events.OnGameStart.Add(H.hook)
H.install()
