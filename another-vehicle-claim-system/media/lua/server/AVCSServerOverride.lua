if isClient() and not isServer() then
	return
end

require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISAVCSUninstallVehiclePart"
require "TimedActions/ISAVCSTakeEngineParts"

if ISInventoryPage == nil then
	ISInventoryPage = {}
end

-- AVCS guard: avoid nil duration crashing NetTimedAction
if not ISBaseTimedAction.__avcsDurationGuard then
	ISBaseTimedAction.__avcsDurationGuard = true
	local _avcsOldGetDuration = ISBaseTimedAction.getDuration
	local _avcsLogged = {}
	function ISBaseTimedAction:getDuration()
		local v = _avcsOldGetDuration(self)
		if v == nil then
			local name = self.__className or self.Type or (self.getType and self:getType()) or "UnknownTimedAction"
			if not _avcsLogged[name] then
				_avcsLogged[name] = true
				print("[AVCS] getDuration() nil for action: " .. tostring(name))
			end
			return 1
		end
		return v
	end
end

-- Force server to use AVCS actions even if vanilla is called
do
	local oldNew = ISUninstallVehiclePart and ISUninstallVehiclePart.new
	if oldNew and ISAVCSUninstallVehiclePart then
		function ISUninstallVehiclePart:new(character, part, workTime)
			return ISAVCSUninstallVehiclePart:new(character, part, workTime)
		end
	end
end

do
	local oldNew = ISTakeEngineParts and ISTakeEngineParts.new
	if oldNew and ISAVCSTakeEngineParts then
		function ISTakeEngineParts:new(character, part, item, maxTime)
			return ISAVCSTakeEngineParts:new(character, part, item, maxTime)
		end
	end
end

--[[
It is impossible to get real time coordinate of vehicles
Vehicle object is not readily obtainable and vehicle DB is not accessible via mod codes
Vehicles.LowerCondition is the only function that simply make sense
All vehicles will have conditions losses as you use it thus this will be called
--]]

if not AVCS.oLowerCondition then
    AVCS.oLowerCondition = Vehicles.LowerCondition
end

function Vehicles.LowerCondition(vehicle, part, elapsedMinutes)
    AVCS.updateVehicleCoordinate(vehicle)
	return AVCS.oLowerCondition(vehicle, part, elapsedMinutes)
end
