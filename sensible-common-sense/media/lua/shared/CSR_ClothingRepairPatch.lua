local explicitFabric = {
    ["Base.Ghillie_Top"] = "Leather",
    ["Base.Ghillie_Trousers"] = "Leather",
    ["Base.Jacket_Fireman"] = "Leather",
    ["Base.Trousers_Fireman"] = "Leather",
    ["Base.Jacket_Padded"] = "Denim",
    ["Base.Jacket_PaddedDOWN"] = "Denim",
    ["Base.Jacket_Padded_HuntingCamo"] = "Denim",
    ["Base.Jacket_Padded_HuntingCamoDOWN"] = "Denim",
    ["Base.Trousers_Padded"] = "Denim",
    ["Base.PonchoGreen"] = "Leather",
    ["Base.PonchoGreenDOWN"] = "Leather",
    ["Base.PonchoYellow"] = "Leather",
    ["Base.PonchoYellowDOWN"] = "Leather",
    ["Base.PonchoGarbageBag"] = "Leather",
    ["Base.PonchoGarbageBagDOWN"] = "Leather",
    ["Base.PonchoTarp"] = "Leather",
    ["Base.PonchoTarpDOWN"] = "Leather",
    ["Base.HazmatSuit"] = "Leather",
    ["Base.SpiffoSuit"] = "Cotton"
}

local function classifyFabric(item)
    if not item or not item.getFullName then
        return nil
    end

    local fullName = item:getFullName()
    if explicitFabric[fullName] then
        return explicitFabric[fullName]
    end

    local name = string.lower(fullName)
    if name:find("shoe", 1, true) or name:find("boot", 1, true) or name:find("glove", 1, true) or name:find("armor", 1, true) or name:find("armour", 1, true) or name:find("bullet", 1, true) or name:find("vest", 1, true) or name:find("poncho", 1, true) or name:find("hazmat", 1, true) then
        return "Leather"
    end

    if name:find("denim", 1, true) or name:find("jean", 1, true) or name:find("padded", 1, true) or name:find("shellsuit", 1, true) or name:find("fireman", 1, true) or name:find("trouser", 1, true) or name:find("jacket", 1, true) then
        return "Denim"
    end

    return "Cotton"
end

local function patchRepairableClothes()
    local items = getAllItems()
    if not items then
        return
    end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item and item.getFabricType and item.getBloodClothingType and item.DoParam then
            local fabricType = item:getFabricType()
            local bloodClothingType = item:getBloodClothingType()
            local coveredCount = 0
            if BloodClothingType and BloodClothingType.getCoveredPartCount and bloodClothingType then
                coveredCount = BloodClothingType.getCoveredPartCount(bloodClothingType) or 0
            end

            if (not fabricType or fabricType == "") and coveredCount > 0 then
                local classified = classifyFabric(item)
                if classified then
                    item:DoParam("FabricType = " .. classified)
                end
            end
        end
    end
end

local _clothingRepairApplied = false
local function patchRepairableClothesOnce()
    if _clothingRepairApplied then return end
    _clothingRepairApplied = true
    patchRepairableClothes()
end
if Events and Events.OnGameStart then
    Events.OnGameStart.Add(patchRepairableClothesOnce)
elseif Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(patchRepairableClothesOnce)
end
