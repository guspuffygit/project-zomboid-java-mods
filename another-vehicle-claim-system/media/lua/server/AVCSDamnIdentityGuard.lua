-- Keep AVCS's claim imprint out of optional DAMN metadata writes.
AVCS = AVCS or {}
AVCS.DamnIdentityGuard = AVCS.DamnIdentityGuard or { handlers = {} }
local state = AVCS.DamnIdentityGuard

local function protectedFields(data)
    if type(data) ~= "table" then
        return false
    end
    for key in pairs(data) do
        if type(key) == "string" and key:upper() == "SQLID" then
            return true
        end
    end
    return false
end

state.protect = function(args, command)
    if type(args) ~= "table" then
        return nil
    end
    local data = command == "setPartModData" and args.data or args
    if not protectedFields(data) then
        return args
    end
    local vehicle = args._vehicle
    if not vehicle then
        local id = args._vehicleId or args.vehicle
        if type(id) ~= "number" or id ~= id or id ~= math.floor(id) then
            return nil
        end
        vehicle = getVehicleById(id)
    end
    if not vehicle or not instanceof(vehicle, "BaseVehicle") then
        return nil
    end
    local target = vehicle
    if command == "setPartModData" then
        if type(args.part) ~= "string" then
            return nil
        end
        target = vehicle:getPartById(args.part)
    end
    if not target then
        return nil
    end
    local identity = target:getModData().SQLID
    local clean = {}
    for key, value in pairs(data) do
        if type(key) == "string" and key:upper() == "SQLID" then
            -- Preserve normal full-data snapshots, but never write the imprint.
            if key ~= "SQLID" or value ~= identity then
                return nil
            end
        else
            clean[key] = value
        end
    end
    if command == "setPartModData" then
        local copy = {}
        for key, value in pairs(args) do
            copy[key] = value
        end
        copy.data = clean
        return copy
    end
    return clean
end

state.install = function()
    local handlers = DAMN and DAMN.ServerHandlers
    if not handlers then
        return
    end
    for _, name in ipairs({ "setVehicleData", "setPartModData" }) do
        local command, original = name, handlers[name]
        local retained = state.handlers[name]
        if type(original) == "function" and (not retained or original ~= retained.wrapper) then
            local wrapper = function(player, args)
                local clean = state.protect(args, command)
                if clean then
                    return original(player, clean)
                end
            end
            handlers[name] = wrapper
            state.handlers[name] = { wrapper = wrapper }
        end
    end
end

if not state.startHook then
    state.startHook = function()
        state.install()
    end
    Events.OnServerStarted.Add(state.startHook)
end
state.install()
