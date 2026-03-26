--
-- Copyright (c) 2022 outdead.
-- Use of this source code is governed by the Apache 2.0 license.
--
-- LogExtenderClient adds more logs to the Logs directory the Project Zomboid game.
--

LogExtenderClient = {
    version = logutils.version,
    pzversion = getCore():getVersionNumber(),
    
    -- Placeholders for Project Zomboid log file names.
    -- Project Zomboid generates files like this 24-08-19_18-11_chat.txt
    -- at first action and use file until next server restart.
    filemask = {
        chat = "chat",
        user = "user",
        cmd = "cmd",
        item = "item",
        map = "map",
        pvp = "pvp",
        vehicle = "vehicle",
        player = "player",
        admin = "admin",
        safehouse = "safehouse",
        craft = "craft",
        map_alternative = "map_alternative",
        brushtool = "brushtool",
    }
}

-- writeLog sends command to server for writting log line to file.
-- Deprecated: Moved to logutils.
-- TODO: Will be removed from LogExtenderClient on next releases.
function LogExtenderClient.writeLog(filemask, message)
    sendClientCommand("LogExtender", "write", { mask = filemask, message = message });
end

-- getLogLinePrefix generates prefix for each log lines.
-- for ease of use, we assume that the player’s existence has been verified previously.
-- Deprecated: Moved to logutils.
-- TODO: Will be removed from LogExtenderClient on next releases.
function LogExtenderClient.getLogLinePrefix(player, action)
    -- TODO: Add ownerID.
    return getCurrentUserSteamID() .. " \"" .. player:getUsername() .. "\" " .. action
end

-- getLocation returns players or vehicle location in "x,x,z" format.
-- Deprecated: Moved to logutils.
-- TODO: Will be removed from LogExtenderClient on next releases.
function LogExtenderClient.getLocation(obj)
    return math.floor(obj:getX()) .. "," .. math.floor(obj:getY()) .. "," .. math.floor(obj:getZ());
end

-- getPlayerSafehouses iterates in server safehouse list and returns
-- area coordinates of player's houses.
-- Deprecated: Moved to logutils.
-- TODO: Will be removed from LogExtenderClient on next releases.
function LogExtenderClient.getPlayerSafehouses(player)
    if player == nil then
        return nil;
    end

    local safehouses = {
        Owner = nil,
        Member = {}
    };

    local safehouseList = SafeHouse.getSafehouseList();
    for i = 0, safehouseList:size() - 1 do
        local safehouse = safehouseList:get(i);
        local owner = safehouse:getOwner();
        local members = safehouse:getPlayers();
        local area = {
            Top = safehouse:getX() .. "x" .. safehouse:getY(),
            Bottom = safehouse:getX2() .. "x" .. safehouse:getY2()
        };

        if player:getUsername() == owner then
            safehouses.Owner = area;
        elseif members:size() > 0 then
            for j = 0, members:size() - 1 do
                if members:get(j) == player:getUsername() then
                    safehouses.Member[#safehouses.Member + 1] = area;
                    break;
                end
            end
        end
    end

    return safehouses;
end

-- getPlayerPerks returns player perks table.
-- Deprecated: Moved to logutils.
-- TODO: Will be removed from LogExtenderClient on next releases.
function LogExtenderClient.getPlayerPerks(player)
    if player == nil then
        return nil;
    end

    local perks = {}

    for i = 0, Perks.getMaxIndex() - 1 do
        local perkType = Perks.fromIndex(i);
        local perk = PerkFactory.getPerk(perkType);

        if perk then
            local parent = perk:getParent();
            if parent ~= Perks.None then
                local perkName = tostring(perk:getType());
                local perkLevel = player:getPerkLevel(perkType);
                local key = "\"" .. perkName .. "\"";

                table.insert(perks, key .. ":" .. perkLevel);
            end
        end
    end

    table.sort(perks);

    return perks;
end

-- getPlayerTraits returns player traits table.
-- Deprecated: Moved to logutils.
-- TODO: Will be removed from LogExtenderClient on next releases.
function LogExtenderClient.getPlayerTraits(player)
    if player == nil then
        return nil;
    end

    local traits = {}

    local knownTraits = player:getCharacterTraits():getKnownTraits();
    for i = 0, knownTraits:size() - 1 do
        local trait = knownTraits:get(i);
        if trait then
            table.insert(traits, '"' .. tostring(trait:getName()) .. '"');
        end
    end

    table.sort(traits);

    return traits;
end

-- getPlayerStats returns some player additional info.
-- Deprecated: Moved to logutils.
-- TODO: Will be removed from LogExtenderClient on next releases.
function LogExtenderClient.getPlayerStats(player)
    if player == nil then
        return nil;
    end

    local stats = {}

    stats.Kills = player:getZombieKills();
    stats.Survived = math.floor(player:getHoursSurvived() * 100) / 100;
    stats.Profession = "";

    if player:getDescriptor() and player:getDescriptor():getCharacterProfession() then
        local charProf = player:getDescriptor():getCharacterProfession();
        local profDef = CharacterProfessionDefinition.getCharacterProfessionDefinition(charProf);
        if profDef then
            stats.Profession = tostring(charProf:getName());
        end
    end

    return stats;
end

-- getPlayerHealth returns some player health information.
-- Deprecated: Moved to logutils.
-- TODO: Will be removed from LogExtenderClient on next releases.
function LogExtenderClient.getPlayerHealth(player)
    if player == nil then
        return nil;
    end

    local bd = player:getBodyDamage()

    local health = {}

    health.Health = math.floor(bd:getOverallBodyHealth());
    health.Infected = bd:IsInfected() and "true" or "false";

    return health;
end

-- getVehicleInfo returns some vehicles information such as id, type and center
-- coordinate.
-- Deprecated: Moved to logutils.
-- TODO: Will be removed from LogExtenderClient on next releases.
function LogExtenderClient.getVehicleInfo(vehicle)
    local info = {
        ID = "0",
        Type = "unknown",
        Center = "10,10,0", -- Unexisting coordinate.
    }

    if vehicle == nil then
        return info;
    end

    local id = vehicle:getID() or "0";
    local type = "unknown";

    local script = vehicle:getScript();
    if script then
        type = script:getName() or "unknown";
    end;

    info.ID = tostring(id);
    info.Type = type;
    info.Center = logutils.GetLocation(vehicle:getCurrentSquare());

    return info;
end
