--
-- SurvivorSkillObeliskProtection.lua
-- Blocks sledgehammer destruction of obelisk sprites by filtering
-- ISDestroyCursor:canDestroy. Cosmetic guard only: a modified client can
-- still craft the packet, but a vanilla + Storm client won't get the
-- destroy option to succeed. Pickup is already blocked at the tile-props
-- level (IsMoveAble stripped from survivor_skill_obelisk.tiles.txt).
--

if isServer() then
    return
end

local SPRITE_PREFIX = "atf_obelisks_"

-- Cache the pristine canDestroy on first load; re-runs (via /reload etc.)
-- must reuse the cached original, not re-wrap the already-wrapped one.
SurvivorSkillObeliskProtection = SurvivorSkillObeliskProtection or {}
if not SurvivorSkillObeliskProtection.origCanDestroy then
    SurvivorSkillObeliskProtection.origCanDestroy = ISDestroyCursor.canDestroy
end

function ISDestroyCursor:canDestroy(object)
    if object then
        local sprite = object:getSprite()
        if sprite then
            local name = sprite:getName()
            if name and luautils.stringStarts(name, SPRITE_PREFIX) then
                return false
            end
        end
    end
    return SurvivorSkillObeliskProtection.origCanDestroy(self, object)
end
