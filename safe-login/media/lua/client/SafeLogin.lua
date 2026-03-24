SafeLogin = {}

local SAFE_DURATION_MS = 10000

local protectionActive = false
local spawnTimeMs = 0
local spawnX = 0
local spawnY = 0
local protectedPlayer = nil

function SafeLogin.activate(player)
    protectionActive = true
    spawnTimeMs = getTimestampMs()
    spawnX = player:getX()
    spawnY = player:getY()
    protectedPlayer = player

    player:setGodMod(true, true)
    player:setInvisible(true, true)
    player:setGhostMode(true, true)

    Events.OnTick.Add(SafeLogin.onTick)
    print("[SafeLogin] Protection activated for 10 seconds.")
end

function SafeLogin.deactivate()
    if not protectionActive then return end

    protectedPlayer:setGodMod(false, true)
    protectedPlayer:setInvisible(false, true)
    protectedPlayer:setGhostMode(false, true)

    protectionActive = false
    protectedPlayer = nil

    Events.OnTick.Remove(SafeLogin.onTick)
    print("[SafeLogin] Protection deactivated.")
end

function SafeLogin.onTick()
    if not protectionActive then return end

    if protectedPlayer:getX() ~= spawnX or protectedPlayer:getY() ~= spawnY then
        print("[SafeLogin] Player moved — removing protection.")
        SafeLogin.deactivate()
        return
    end

    if getTimestampMs() - spawnTimeMs >= SAFE_DURATION_MS then
        print("[SafeLogin] 10 seconds elapsed — removing protection.")
        SafeLogin.deactivate()
    end
end

Events.OnCreatePlayer.Add(function(playerIndex, player)
    SafeLogin.activate(player)
end)
