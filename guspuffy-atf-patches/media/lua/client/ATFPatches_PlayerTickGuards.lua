-- Third-party callbacks keep firing between death/disconnect and player creation.
-- Replace registered function references too; changing the global alone is insufficient.
ATFPlayerTickGuards = ATFPlayerTickGuards or { originals = {}, wrappers = {} }
local G = ATFPlayerTickGuards

local function install(name, owner, key)
    local original = owner and owner[key]
    if type(original) ~= "function" or original == G.wrappers[name] then
        return
    end
    if G.wrappers[name] then
        Events.OnTick.Remove(G.wrappers[name])
    end
    G.originals[name] = original
    local function guarded(...)
        local player = getPlayer()
        if not player or player:isDead() then
            return
        end
        return original(...)
    end
    G.wrappers[name] = guarded
    Events.OnTick.Remove(original)
    owner[key] = guarded
    Events.OnTick.Add(guarded)
end

function G.install()
    install("Lifestyle", _G, "LSAtEveryTick")
    install("TrueMusicRadio", _G.TMRadio, "adjustSounds")
end

if G.startHook then
    Events.OnGameStart.Remove(G.startHook)
end
G.startHook = G.install
Events.OnGameStart.Add(G.startHook)
G.install()
