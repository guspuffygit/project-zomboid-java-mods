-- Save reviewed legacy fields without replacing migrated rewards or unrelated mod data.
ATFPatches_LifestyleSyncPolicy = ATFPatches_LifestyleSyncPolicy or {}
local Policy = ATFPatches_LifestyleSyncPolicy

local adminCommands = {
    UpdateAmbt = "SandboxOptions",
    UpdateServerBeauty = "SandboxOptions",
    ImportServerBeauty = "SandboxOptions",
    CompleteTargetAmbt = "CanModifyPlayerStatsInThePlayerStatsUI",
    ResetTargetAmbt = "CanModifyPlayerStatsInThePlayerStatsUI",
    LSSCTest = "SandboxOptions",
    AddItems_Player = "AddItem",
}

function Policy.hasCapability(player, name)
    local role = player and player.getRole and player:getRole()
    return role
        and role.hasCapability
        and Capability
        and Capability[name]
        and role:hasCapability(Capability[name]) == true
end

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function Policy.allowCommand(player, command, args)
    if not player or type(command) ~= "string" or type(args) ~= "table" then
        return false
    end
    local capability = adminCommands[command]
    if capability and not Policy.hasCapability(player, capability) then
        return false
    end
    if command == "AddItems_Player" then
        local amount, itemType = args[2], args[1]
        return finite(amount)
            and amount == math.floor(amount)
            and amount >= 1
            and amount <= 100
            and type(itemType) == "string"
            and #itemType > 0
            and #itemType <= 160
            and itemType:match("^[%w_]+%.[%w_]+$") ~= nil
            and ScriptManager
            and ScriptManager.instance
            and ScriptManager.instance:getItem(itemType) ~= nil
    end
    return true
end

local function copyPreference(value, depth, budget, active)
    local kind = type(value)
    budget.bytes = budget.bytes + 16
    if budget.bytes > 16384 then
        return nil, false
    end
    if kind == "boolean" then
        return value, true
    end
    if kind == "number" then
        return value, finite(value) and math.abs(value) <= 9007199254740991
    end
    if kind == "string" then
        budget.bytes = budget.bytes + #value
        return value, #value <= 1024 and budget.bytes <= 16384
    end
    if kind ~= "table" or depth > 6 or active[value] then
        return nil, false
    end
    active[value] = true
    local result = {}
    for key, child in pairs(value) do
        budget.entries = budget.entries + 1
        if budget.entries > 512 then
            return nil, false
        end
        local keyKind = type(key)
        if
            not (
                (keyKind == "string" and #key <= 80)
                or (finite(key) and key == math.floor(key) and key >= 1 and key <= 256)
            )
        then
            return nil, false
        end
        budget.bytes = budget.bytes + (keyKind == "string" and #key or 16)
        local copied, ok = copyPreference(child, depth + 1, budget, active)
        if not ok then
            return nil, false
        end
        result[key] = copied
    end
    active[value] = nil
    return result, true
end

function Policy.savePlayerData(player, args)
    if not player or type(args) ~= "table" or type(args[1]) ~= "table" then
        return false
    end
    local incoming, current = args[1], player:getModData()
    local voice = incoming.PlayerVoice
    if
        voice ~= nil
        and not (finite(voice) and voice == math.floor(voice) and voice >= 0 and voice <= 4)
    then
        return false
    end
    local clothes, clothesOK
    if incoming.LSClothes ~= nil then
        if type(incoming.LSClothes) ~= "table" then
            return false
        end
        clothes, clothesOK = copyPreference(incoming.LSClothes, 1, { bytes = 0, entries = 0 }, {})
        if not clothesOK then
            return false
        end
    end
    local selections = {}
    if incoming.Ambitions ~= nil then
        if type(incoming.Ambitions) ~= "table" then
            return false
        end
        local count = 0
        for name, data in pairs(incoming.Ambitions) do
            count = count + 1
            if count > 128 or type(name) ~= "string" or #name > 80 then
                return false
            end
            if type(data) == "table" and type(data.isActive) == "boolean" then
                selections[name] = data.isActive
            end
        end
    end
    local legacy = ATFPatches_LifestyleLegacyProgress
    if not legacy then
        require("ATFPatches_LifestyleLegacyProgress")
        legacy = ATFPatches_LifestyleLegacyProgress
    end
    if not legacy or not legacy.copy then
        return false
    end
    local progress = legacy.copy(incoming)
    if not progress then
        return false
    end
    -- Validate every accepted preference before applying any of them.
    if voice ~= nil then
        current.PlayerVoice = voice
    end
    if clothes then
        current.LSClothes = clothes
    end
    legacy.apply(current, progress)
    local passive = ATFPatches_LifestylePassiveRewards
    for name, active in pairs(selections) do
        if name == "LSTerminator" and passive and passive.selectAmbition then
            passive.selectAmbition(player, name, active)
        elseif current.Ambitions and type(current.Ambitions[name]) == "table" then
            current.Ambitions[name].isActive = active
        end
    end
    -- Migrated Yoga/Mindfulness/Neural Hat/Terminator fields stay server-owned.
    -- Other reviewed legacy trackers retain their bounded client-owned schema.
    -- Unrelated mod data and unknown authority keys are never replaced.
    return true
end
