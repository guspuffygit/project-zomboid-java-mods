local module = arg[1] or "another-vehicle-claim-system"
local provider = arg[2] or (os and os.getenv and os.getenv("DAMN_MOD_ROOT"))
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function event()
    local callbacks = {}
    return {
        callbacks = callbacks,
        Add = function(fn)
            callbacks[#callbacks + 1] = fn
        end,
    }
end
local function fire(event, ...)
    for _, callback in ipairs(event.callbacks) do
        callback(...)
    end
end
local function setup()
    AVCS, DAMN = nil, nil
    Events = { OnServerStarted = event(), OnClientCommand = event() }
    isClient = function()
        return false
    end
    isServer = function()
        return true
    end
    getText = function(key)
        return key
    end
    SandboxVars = { AVCS = { AllowFaction = false, AllowSafehouse = false } }
    SandboxVars.AVCS.MuleParts = "Battery"
    sendServerCommand = function() end
    local data, partData = { SQLID = 100 }, { SQLID = 100 }
    local part = {
        getModData = function()
            return partData
        end,
    }
    local vehicle = {
        getId = function()
            return 99
        end,
        getModData = function()
            return data
        end,
        getPartById = function(_, id)
            if id == "Battery" then
                return part
            end
        end,
        transmitModData = function() end,
        transmitPartModData = function() end,
    }
    instanceof = function(object, class)
        return object == vehicle and class == "BaseVehicle"
    end
    getVehicleById = function(id)
        if id == 99 then
            return vehicle
        end
    end
    DAMN = { BackCompat = { migrateModData = function() end } }
    dofile(module .. "/media/lua/shared/AVCSShared.lua")
    AVCS.dbByVehicleSQLID = { [100] = { OwnerPlayerID = "owner" } }
    AVCS.dbByPlayerID = { owner = { LastKnownLogonTime = 1 } }
    local player = {
        getUsername = function()
            return "outsider"
        end,
        getAccessLevel = function()
            return "none"
        end,
    }
    return vehicle, data, partData, player
end
local guard = module .. "/media/lua/server/AVCSDamnIdentityGuard.lua"
if not provider then
    setup()
    DAMN = nil
    dofile(guard)
    fire(Events.OnServerStarted)
    check(#Events.OnServerStarted.callbacks == 1, "Missing optional provider remains inactive")
    dofile(guard)
    check(#Events.OnServerStarted.callbacks == 1, "Absent-provider guard reload keeps one hook")
    print(
        "PASS: "
            .. checks
            .. " optional DAMN absence checks; supply DAMN_MOD_ROOT for actual provider fixture"
    )
    return
end
local function loadProvider()
    dofile(provider .. "/media/lua/server/Commands/DAMN_Data.lua")
    dofile(provider .. "/media/lua/server/DAMN_Server.lua")
end
local function command(player, name, args)
    fire(Events.OnClientCommand, "that_damn_lib", name, player, args)
end
local vehicle, data, partData, player = setup()
loadProvider()
check(
    not AVCS.getSimpleBooleanPermission(AVCS.checkPermission(player, vehicle)),
    "Baseline actor lacks claim access"
)
command(player, "setVehicleData", { _vehicleId = 99, SQLID = 999 })
check(
    data.SQLID == 999 and AVCS.getSimpleBooleanPermission(AVCS.checkPermission(player, vehicle)),
    "Exact unchanged provider reproduces permission bypass before guard"
)
for _, order in ipairs({ "guard-first", "provider-first" }) do
    vehicle, data, partData, player = setup()
    if order == "guard-first" then
        dofile(guard)
    end
    loadProvider()
    if order == "provider-first" then
        dofile(guard)
    end
    fire(Events.OnServerStarted)
    command(player, "setVehicleData", { _vehicleId = 99, SQLID = 999, paint = "red" })
    check(
        data.SQLID == 100 and not data.paint,
        order .. " denies changed vehicle identity before any field mutation"
    )
    check(
        not AVCS.getSimpleBooleanPermission(AVCS.checkPermission(player, vehicle)),
        order .. " maintains denied claim access"
    )
    command(player, "setVehicleData", { _vehicleId = 99, sqlid = 999 })
    check(not data.sqlid, order .. " reserves identity casing variants")
    command(player, "setVehicleData", { _vehicleId = 99, SQLID = 100, paint = "blue" })
    check(
        data.SQLID == 100 and data.paint == "blue",
        order .. " preserves unchanged full-data snapshot"
    )
    command(
        player,
        "setPartModData",
        { _vehicleId = 99, part = "Battery", data = { SQLID = 999, paint = "red" } }
    )
    check(partData.SQLID == 100 and not partData.paint, order .. " rejects mule identity overwrite")
    command(
        player,
        "setPartModData",
        { _vehicleId = 99, part = "Battery", data = { SQLID = 100, paint = "blue" } }
    )
    check(
        partData.SQLID == 100 and partData.paint == "blue",
        order .. " permits unchanged mule snapshot"
    )
    command(player, "setVehicleData", { _vehicleId = 99, paint = "green" })
    check(data.paint == "green", order .. " leaves nonidentity provider metadata native")
    local wrapper = DAMN.ServerHandlers.setVehicleData
    dofile(guard)
    check(
        DAMN.ServerHandlers.setVehicleData == wrapper and #Events.OnServerStarted.callbacks == 1,
        order .. " guard reload does not duplicate wrapper or startup hook"
    )
    DAMN.ServerHandlers.setVehicleData(player, { _vehicleId = 777, SQLID = 999 })
    DAMN.ServerHandlers.setVehicleData(player, { _vehicle = {}, SQLID = 999 })
    check(data.SQLID == 100, order .. " rejects unresolved or forged identity target")
    loadProvider()
    dofile(guard)
    command(player, "setVehicleData", { _vehicleId = 99, SQLID = 998 })
    check(data.SQLID == 100, order .. " reinstall after provider reload restores identity guard")
    data.SQLID, partData.SQLID = nil, 100
    command(player, "setPartModData", { _vehicleId = 99, part = "Battery", data = { SQLID = 999 } })
    check(partData.SQLID == 100, order .. " protects a legacy mule-only claim")
    check(
        not AVCS.getSimpleBooleanPermission(AVCS.checkPermission(player, vehicle)),
        order .. " legacy migration retains denied permission"
    )
end
print("PASS: " .. checks .. " actual DAMN/AVCS identity checks")
