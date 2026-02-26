require "TimedActions/ISBaseTimedAction"

ISAVCSUninstallVehiclePart = ISBaseTimedAction:derive("ISAVCSUninstallVehiclePart")

local function hasPermission(character, vehicle)
    local ok = AVCS.getPublicPermission(vehicle, "AllowUninstallParts")
    if not ok then
        ok = AVCS.getSimpleBooleanPermission(AVCS.checkPermission(character, vehicle))
    end
    return ok == true
end

function ISAVCSUninstallVehiclePart:isValid()
    if self.character:isMechanicsCheat() then return true end
    if not self.part or not self.vehicle then return false end
    if not hasPermission(self.character, self.vehicle) then return false end
    return self.part:getInventoryItem() and self.vehicle:canUninstallPart(self.character, self.part)
end

function ISAVCSUninstallVehiclePart:waitToStart()
    if self.character:isMechanicsCheat() then return false end
    self.character:faceThisObject(self.vehicle)
    return self.character:shouldBeTurning()
end

function ISAVCSUninstallVehiclePart:update()
    self.character:faceThisObject(self.vehicle)
    self.character:setMetabolicTarget(Metabolics.MediumWork)
end

function ISAVCSUninstallVehiclePart:start()
    if isServer() then return end
    if self.part:getWheelIndex() ~= -1 or self.part:getId():contains("Brake") then
        self:setActionAnim("VehicleWorkOnTire")
    else
        self:setActionAnim("VehicleWorkOnMid")
    end
end

function ISAVCSUninstallVehiclePart:stop()
    ISBaseTimedAction.stop(self)
end

function ISAVCSUninstallVehiclePart:perform()
    ISBaseTimedAction.perform(self)
    return true
end

function ISAVCSUninstallVehiclePart:complete()
    if not isServer() then return true end
    if not self.vehicle or not self.part then return false end
    if not hasPermission(self.character, self.vehicle) then return false end

    local installTable = self.part:getTable("install")
    if not installTable then return false end

    local perksTable = VehicleUtils.getPerksTableForChr(installTable.skills, self.character)
    local perks = installTable.skills
    local success, failure = VehicleUtils.calculateInstallationSuccess(perks, self.character, perksTable)
    local item = self.part:getInventoryItem()
    if not item then return false end

    if instanceof(item, "Radio") and item:getDeviceData() ~= nil then
        if self.part:getDeviceData() == nil then
            self.part:createSignalDevice()
        end
        local presets = self.part:getDeviceData():getDevicePresets()
        item:getDeviceData():cloneDevicePresets(presets)
    end

    if ZombRand(100) < success then
        item:setItemCapacity(self.part:getContainerContentAmount())
        self.part:setInventoryItem(nil)
        local tbl = self.part:getTable("uninstall")
        if tbl and tbl.complete then
            VehicleUtils.callLua(tbl.complete, self.vehicle, self.part, item)
        end
        self.vehicle:transmitPartItem(self.part)

        if self.character:getInventory():hasRoomFor(self.character, item) then
            self.character:getInventory():AddItem(item)
            sendAddItemToContainer(self.character:getInventory(), item)
        else
            local square = self.character:getCurrentSquare()
            if square then
                local dropX, dropY, dropZ = ISTransferAction.GetDropItemOffset(self.character, square, item)
                square:AddWorldInventoryItem(item, dropX, dropY, dropZ)
            end
        end

        self.character:sendObjectChange("mechanicActionDone", { success = true })
        self.character:addMechanicsItem(
            item:getID() .. self.vehicle:getMechanicalID() .. "0",
            self.part,
            getGameTime():getCalender():getTimeInMillis()
        )
    elseif ZombRand(failure) < 100 then
        self.part:setCondition(self.part:getCondition() - ZombRand(5, 10))
        self.vehicle:transmitPartCondition(self.part)
        playServerSound("PZ_MetalSnap", self.character:getCurrentSquare())
        self.character:sendObjectChange("mechanicActionDone", { success = false })
        self.character:getXp():AddXP(Perks.Mechanics, 1, false, false, true)
    end

    return true
end

function ISAVCSUninstallVehiclePart:getDuration()
    if self.character:isMechanicsCheat() or self.character:isTimedActionInstant() then
        return 1
    end
    local workTime = tonumber(self.workTime) or 1
    local perk = self.character:getPerkLevel(Perks.Mechanics)
    local duration = workTime - (perk * (workTime / 15))
    if duration < 1 then duration = 1 end
    return duration
end

function ISAVCSUninstallVehiclePart:new(character, part, workTime)
    local o = ISBaseTimedAction.new(self, character)
    o.vehicle = part and part:getVehicle() or nil
    o.part = part
    o.workTime = workTime
    o.maxTime = o:getDuration()

    local invItem = part and part:getInventoryItem()
    if invItem then
        o.jobType = getText("Tooltip_Vehicle_Uninstalling", invItem:getDisplayName())
    end

    return o
end
