SafeLogin = {}

local SAFE_DURATION_MS = 10000

local protectionActive = false
local spawnTimeMs = 0
local spawnX = 0
local spawnY = 0
local protectedPlayer = nil

local function isAdmin()
    return getAccessLevel() == "admin" or getAccessLevel() == "Admin"
end

local function halo(player, msg)
    player:setHaloNote(msg, 100, 200, 100, 50)
end

function SafeLogin.activate(player)
    if isAdmin() then
        print("[SafeLogin] Player is admin — skipping protection.")
        return
    end

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

    halo(protectedPlayer, "You are no longer protected.")

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

    local elapsedMs = getTimestampMs() - spawnTimeMs
    if elapsedMs >= SAFE_DURATION_MS then
        print("[SafeLogin] 10 seconds elapsed — removing protection.")
        SafeLogin.deactivate()
    else
        local remainingSec = math.ceil((SAFE_DURATION_MS - elapsedMs) / 1000)
        halo(protectedPlayer, "You are invisible and invincible for " .. remainingSec .. "s. Move to cancel.")
    end
end

Events.OnCreatePlayer.Add(function(playerIndex, player)
    SafeLogin.activate(player)
end)
