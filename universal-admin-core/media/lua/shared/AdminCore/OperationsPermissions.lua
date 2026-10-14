-- A feature gate narrows native capabilities; it never grants them.
AdminOperations = AdminOperations or {}
local O = AdminOperations
function O.hasEntries(values)
    for _ in pairs(values) do
        return true
    end
    return false
end
O.features = {
    ADMIN_POWER_BASIC = {
        "ToggleGodModHimself",
        "ToggleInvisibleHimself",
        "ToggleUnlimitedCarry",
        "ToggleUnlimitedEndurance",
        "ToggleUnlimitedAmmo",
        "ClimateManager",
        "CanSeeAll",
        "CanHearAll",
        "ManipulateZombie",
    },
    ADMIN_POWER_MOVEMENT = {
        "ToggleNoclipHimself",
        "UseFastMoveCheat",
        "UseTimedActionInstantCheat",
    },
    ADMIN_SPECTATOR = { "TeleportToPlayer" },
    ADMIN_RENDER_DEBUG = { "UseDebugContextMenu" },
    ADMIN_SAFEHOUSE_EDIT = { "CanSetupSafehouses" },
    ADMIN_WORLD_EDIT = {
        "UseBuildCheat",
        "UseMovablesCheat",
        "UseFarmingCheat",
        "UseFishingCheat",
        "UseBrushToolManager",
        "ToggleKnowAllRecipes",
    },
    ADMIN_DEBUG_TOOLS = {
        "UseDebugContextMenu",
        "UseHealthCheat",
        "UseMechanicsCheat",
        "AnimalCheats",
        "UseLootZed",
        "UseLootLog",
        "ManipulateVehicle",
    },
    ADMIN_HORDE_MANAGER = { "CreateHorde" },
}
function O.policy()
    if not isServer() or not ModData then
        return {}
    end
    return ModData.getOrCreate("UniversalAdminCore.OperationsPolicy.v1")
end
function O.capable(player, name)
    local role = player and player:getRole()
    local capability = Capability and Capability[name]
    return role ~= nil and capability ~= nil and role:hasCapability(capability) == true
end
function O.authorized(player, feature)
    local role, caps = player and player:getRole(), O.features[feature]
    if not role or not role:hasAdminPower() or not caps then
        return false
    end
    local granted = false
    for _, name in ipairs(caps) do
        granted = granted or O.capable(player, name)
    end
    if not granted then
        return false
    end
    if feature == "ADMIN_SPECTATOR" and not O.capable(player, "SeePlayersConnected") then
        return false
    end
    local policy = O.policy()
    if policy.disabled and policy.disabled[feature] == true then
        return false
    end
    local users = policy.users
    if users and users[player:getUsername()] and users[player:getUsername()][feature] == false then
        return false
    end
    return true
end
function O.toolAllowed(player, id)
    local role = player and player:getRole()
    if not role or not role:hasAdminPower() or type(id) ~= "string" or #id > 160 then
        return false
    end
    local policy = O.policy()
    return not (policy.disabledTools and policy.disabledTools[id] == true)
end
-- No policy-writing RPC. Server operators may restrict features/tools through
-- this persisted table; true never bypasses a missing native capability.
function O.audit(event, player, detail)
    if not isServer() or not player then
        return
    end
    local data = ModData.getOrCreate("UniversalAdminCore.OperationsAudit.v1")
    data.rows = data.rows or {}
    local row = {
        event = tostring(event):sub(1, 64),
        actor = player:getUsername(),
        time = getTimestampMs(),
        detail = tostring(detail or ""):gsub("[%c]", " "):sub(1, 512),
    }
    data.rows[#data.rows + 1] = row
    if #data.rows > 500 then
        table.remove(data.rows, 1)
    end
    print("[Universal Admin Core] " .. row.event .. " | " .. row.actor .. " | " .. row.detail)
end
