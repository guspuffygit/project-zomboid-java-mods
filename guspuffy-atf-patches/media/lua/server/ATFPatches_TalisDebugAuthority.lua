-- Optional Talis global diagnostics require the current server capability.
if isClient() and not isServer() then
    return
end

ATFPatches_TalisDebugAuthority = ATFPatches_TalisDebugAuthority or {}
local Guard = ATFPatches_TalisDebugAuthority

local function allowed(player, args)
    local role = player and player.getRole and player:getRole()
    if
        not (
            role
            and role.hasCapability
            and Capability
            and Capability.SandboxOptions
            and role:hasCapability(Capability.SandboxOptions) == true
        )
    then
        return false
    end
    if
        type(args) ~= "table"
        or type(args.enabled) ~= "boolean"
        or type(args.subsystem) ~= "string"
        or #args.subsystem > 80
    then
        return false
    end
    local runtime = NMRuntimeConfig
    if not (runtime and runtime.resolveSubsystemDebugName) then
        return false
    end
    -- Use the provider's approved subsystem names and legacy aliases.
    local name = runtime.resolveSubsystemDebugName(args.subsystem)
    return type(name) == "string" and #name > 0
end

function Guard.install()
    local router = NMServerIntentRouter
    if not router or type(router.onClientCommand) ~= "function" then
        return false
    end
    if router.onClientCommand == Guard.wrapper then
        return true
    end
    local previous = router.onClientCommand
    local wrapper = function(module, command, player, args)
        if
            NMCore
            and module == NMCore.NetModule
            and command == "debug_set"
            and not allowed(player, args)
        then
            return true
        end
        return previous(module, command, player, args)
    end
    Guard.wrapper = wrapper
    router.onClientCommand = wrapper
    return true
end

Guard.install()
if Guard.onServerStarted then
    Events.OnServerStarted.Remove(Guard.onServerStarted)
end
Guard.onServerStarted = function()
    Guard.install()
end
Events.OnServerStarted.Add(Guard.onServerStarted)
