require "CSR_FeatureFlags"
require "CSR_Utils"

local _installed = false

local function isDisinfectant(item)
    if item:hasComponent(ComponentType.FluidContainer) then
        local fc = item:getFluidContainer()
        local amount = fc:getAmount()
        if amount > 0.15 then
            local alcohol = fc:getProperties():getAlcohol()
            if alcohol / (amount + 0.001) >= 0.4 then
                return true
            end
        end
    elseif item:IsDrainable() and item:getAlcoholPower() >= 4.0 then
        return true
    end
    return false
end

local function getBestDisinfectant(items)
    local best = nil
    local bestPower = -1
    for _, item in ipairs(items) do
        local power = 0
        if item:hasComponent(ComponentType.FluidContainer) then
            local fc = item:getFluidContainer()
            power = fc:getProperties():getAlcohol() / (fc:getAmount() + 0.001)
        elseif item:IsDrainable() then
            power = item:getAlcoholPower()
        end
        if power > bestPower then
            bestPower = power
            best = item
        end
    end
    return best
end

local function findItems(doctor)
    local containers = ISInventoryPaneContextMenu.getContainers(doctor)
    if not containers then return {}, {} end
    local bandagesByType = {}
    local disinfectants = {}
    for i = 0, containers:size() - 1 do
        local container = containers:get(i)
        local items = container:getItems()
        for j = 0, items:size() - 1 do
            local item = items:get(j)
            if item:getBandagePower() and item:getBandagePower() > 0 then
                local ft = item:getFullType()
                if not bandagesByType[ft] then
                    bandagesByType[ft] = item
                end
            end
            if isDisinfectant(item) then
                table.insert(disinfectants, item)
            end
        end
    end
    return bandagesByType, disinfectants
end

local function onReplaceBandage(doctor, patient, bodyPart, bandageItem)
    ISInventoryPaneContextMenu.transferIfNeeded(doctor, bandageItem)
    ISTimedActionQueue.add(ISApplyBandage:new(doctor, patient, nil, bodyPart, false))
    ISTimedActionQueue.add(ISApplyBandage:new(doctor, patient, bandageItem, bodyPart, true))
end

local function onDisinfectAndReplace(doctor, patient, bodyPart, bandageItem, disinfectant)
    ISInventoryPaneContextMenu.transferIfNeeded(doctor, disinfectant)
    ISInventoryPaneContextMenu.transferIfNeeded(doctor, bandageItem)
    ISTimedActionQueue.add(ISApplyBandage:new(doctor, patient, nil, bodyPart, false))
    ISTimedActionQueue.add(ISDisinfect:new(doctor, patient, disinfectant, bodyPart))
    ISTimedActionQueue.add(ISApplyBandage:new(doctor, patient, bandageItem, bodyPart, true))
end

local function onRestaple(doctor, patient, bodyPart)
    if not CSR_RestapleAction then
        require "TimedActions/CSR_RestapleAction"
    end
    ISTimedActionQueue.add(ISApplyBandage:new(doctor, patient, nil, bodyPart, false))
    ISTimedActionQueue.add(CSR_RestapleAction:new(doctor, patient, bodyPart))
end

local function onDisinfectAndRestaple(doctor, patient, bodyPart, disinfectant)
    if not CSR_RestapleAction then
        require "TimedActions/CSR_RestapleAction"
    end
    ISInventoryPaneContextMenu.transferIfNeeded(doctor, disinfectant)
    ISTimedActionQueue.add(ISApplyBandage:new(doctor, patient, nil, bodyPart, false))
    ISTimedActionQueue.add(ISDisinfect:new(doctor, patient, disinfectant, bodyPart))
    ISTimedActionQueue.add(CSR_RestapleAction:new(doctor, patient, bodyPart))
end

local function installReplaceBandageHandler()
    if _installed then return end
    if not ISHealthPanel or not ISHealthPanel.doBodyPartContextMenu then return end
    _installed = true

    local _origDoBodyPartContextMenu = ISHealthPanel.doBodyPartContextMenu

    function ISHealthPanel:doBodyPartContextMenu(bodyPart, x, y)
        _origDoBodyPartContextMenu(self, bodyPart, x, y)

        if not CSR_FeatureFlags.isEquipmentQoLEnabled() then return end
        if not bodyPart:bandaged() then return end

        local doctor = self.otherPlayer or self.character
        local patient = self.character
        local playerNum = self.otherPlayer and self.otherPlayer:getPlayerNum() or self.character:getPlayerNum()
        local context = getPlayerContextMenu(playerNum)
        if not context then return end

        local bandagesByType, disinfectants = findItems(doctor)
        local bestDisinfectant = getBestDisinfectant(disinfectants)
        local isStapled = bodyPart:getBandageType() == "Base.Stapler"
        local hasStapler = CSR_Utils.findStapler(doctor) ~= nil
        local hasStaples = CSR_Utils.findStaples(doctor) ~= nil

        local bandageTypes = {}
        for ft, item in pairs(bandagesByType) do
            table.insert(bandageTypes, { fullType = ft, item = item })
        end
        table.sort(bandageTypes, function(a, b) return a.item:getName() < b.item:getName() end)

        if #bandageTypes > 0 then
            local replaceOpt = context:addOption("Replace bandage")
            local subMenu = context:getNew(context)
            context:addSubMenu(replaceOpt, subMenu)
            for _, bt in ipairs(bandageTypes) do
                local bandageItem = bt.item
                local opt = subMenu:addOption(bandageItem:getName(), self, function()
                    onReplaceBandage(doctor, patient, bodyPart, bandageItem)
                end)
                opt.itemForTexture = bandageItem
            end
        end

        if #bandageTypes > 0 and bestDisinfectant then
            local disReplaceOpt = context:addOption("Disinfect & replace bandage")
            local subMenu = context:getNew(context)
            context:addSubMenu(disReplaceOpt, subMenu)
            disReplaceOpt.itemForTexture = bestDisinfectant
            for _, bt in ipairs(bandageTypes) do
                local bandageItem = bt.item
                local disinfectant = bestDisinfectant
                local opt = subMenu:addOption(bandageItem:getName(), self, function()
                    onDisinfectAndReplace(doctor, patient, bodyPart, bandageItem, disinfectant)
                end)
                opt.itemForTexture = bandageItem
            end
        end

        if isStapled and hasStapler and hasStaples then
            context:addOption("Re-staple wound", self, function()
                onRestaple(doctor, patient, bodyPart)
            end)

            if bestDisinfectant then
                local disinfectant = bestDisinfectant
                local opt = context:addOption("Disinfect & re-staple wound", self, function()
                    onDisinfectAndRestaple(doctor, patient, bodyPart, disinfectant)
                end)
                opt.itemForTexture = bestDisinfectant
            end
        end
    end
end

if Events then
    if Events.OnGameStart then Events.OnGameStart.Add(installReplaceBandageHandler) end
    if Events.OnCreatePlayer then Events.OnCreatePlayer.Add(installReplaceBandageHandler) end
end
