-- Runs the unchanged provider router/configuration with the optional guard.
local root = assert(arg[1], "Supply the original Talis media/lua folder")
local guardFile = arg[2] or "guspuffy-atf-patches/media/lua/server/ATFPatches_TalisDebugAuthority.lua"
local checks, broadcasts, flips, previousCalls = 0, 0, 0, 0
local function check(value, message) assert(value, message); checks = checks + 1 end
local callbacks = {}
Events = { OnServerStarted = {
    Add = function(fn) callbacks[fn] = true end,
    Remove = function(fn) callbacks[fn] = nil end,
} }
isServer = function() return true end
isClient = function() return false end
Capability = { SandboxOptions = "SandboxOptions" }
NMRuntimeConfig = { _values = {} }
dofile(root .. "/shared/core/NMRuntimeDebugConfig.lua")
NMCore = { NetModule = "NM", setSubsystemDebugEnabled = function(name, enabled)
    return NMRuntimeConfig.setSubsystemDebugEnabled(name, enabled)
end }
local observer = {}
getOnlinePlayers = function() return {size = function() return 1 end, get = function() return observer end} end
sendServerCommand = function(player, module, command)
    check(player == observer and module == "NM" and command == "debug_sync", "native broadcast shape")
    broadcasts = broadcasts + 1
end
NMServerLooseMediaHandlers = { flipMediaSide = function() flips = flips + 1; return "flipped" end }
dofile(root .. "/server/intents/NMServerIntentRouter.lua")
local provider = NMServerIntentRouter.onClientCommand
NMServerIntentRouter.onClientCommand = function(...)
    previousCalls = previousCalls + 1
    return provider(...)
end
dofile(guardFile)
local function player(access, capability)
    local role = {hasCapability = function(_, name) return name == Capability.SandboxOptions and capability end}
    return {getAccessLevel = function() return access end, getRole = function() return role end}
end
local ordinary, none, named, staff = player("", false), player("none", false), player("admin", false), player("", true)
for _, name in ipairs(NMRuntimeConfig.getSubsystemDebugNames()) do
    for _, sender in ipairs({ordinary, none, named}) do
        local count = broadcasts
        check(NMServerIntentRouter.onClientCommand("NM", "debug_set", sender, {enabled = true, subsystem = name}) == true,
            "rejected debug command consumed")
        check(not NMRuntimeConfig.isSubsystemDebugEnabled(name) and broadcasts == count, "unauthorized role cannot change " .. name)
    end
    NMServerIntentRouter.onClientCommand("NM", "debug_set", staff, {enabled = true, subsystem = name})
    check(NMRuntimeConfig.isSubsystemDebugEnabled(name), "capability enables " .. name)
    NMServerIntentRouter.onClientCommand("NM", "debug_set", staff, {enabled = false, subsystem = name})
    check(not NMRuntimeConfig.isSubsystemDebugEnabled(name), "capability disables " .. name)
end
local count = broadcasts
for _, args in ipairs({{}, {enabled = 1, subsystem = "core"}, {enabled = true, subsystem = {}},
    {enabled = true, subsystem = "unknown"}, {enabled = true, subsystem = string.rep("x", 81)}}) do
    NMServerIntentRouter.onClientCommand("NM", "debug_set", staff, args)
end
NMServerIntentRouter.onClientCommand("NM", "debug_set", nil, {enabled = true, subsystem = "core"})
check(broadcasts == count, "invalid intent never broadcasts")
NMServerIntentRouter.onClientCommand("NM", "debug_set", staff, {enabled = true, subsystem = "lootProbe"})
check(NMRuntimeConfig.isSubsystemDebugEnabled("loot_probe"), "provider legacy alias supported")
staff.getRole = function() return nil end
count = broadcasts
NMServerIntentRouter.onClientCommand("NM", "debug_set", staff, {enabled = false, subsystem = "loot_probe"})
check(broadcasts == count and NMRuntimeConfig.isSubsystemDebugEnabled("loot_probe"), "role loss takes effect immediately")
check(NMServerIntentRouter.onClientCommand("other", "debug_set", ordinary, {}) == false, "unrelated modules delegate")
check(NMServerIntentRouter.onClientCommand("NM", "media_flip", ordinary, {}) == "flipped" and flips == 1,
    "ordinary gameplay delegates")
local wrapper = NMServerIntentRouter.onClientCommand
dofile(guardFile)
check(NMServerIntentRouter.onClientCommand == wrapper, "reload does not stack wrappers")
local callbackCount = 0
for _ in pairs(callbacks) do callbackCount = callbackCount + 1 end
check(callbackCount == 1, "reload retains one lifecycle callback")
local before = previousCalls
NMServerIntentRouter.onClientCommand("NM", "media_flip", ordinary, {})
check(previousCalls == before + 1, "earlier wrapper preserved once")
NMServerIntentRouter = nil
check(ATFPatches_TalisDebugAuthority.install() == false, "optional absent provider supported")
NMServerIntentRouter = {onClientCommand = provider}
for callback in pairs(callbacks) do callback() end
count = broadcasts
NMServerIntentRouter.onClientCommand("NM", "debug_set", ordinary, {enabled = true, subsystem = "core"})
check(broadcasts == count, "provider loaded after guard protected before server commands")
print("Talis debug authority checks: " .. checks)
