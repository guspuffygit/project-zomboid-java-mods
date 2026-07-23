--
-- SurvivorSkillObeliskDestroyGuard.lua
-- Server half of obelisk indestructibility for the B42 action system.
--
-- Sledgehammer destroy and furniture pickup/disassemble are synced timed
-- actions: the client streams the action to the server (NetTimedAction) and
-- the SERVER runs the action's complete(), which removes the object with
-- direct Java calls (transmitRemoveItemFromSquare, pickUpMoveableViaCursor,
-- scrapObjectViaCursor). No removal packet is processed on that path, so the
-- Storm packet patches never see it — these overrides are the missing gate.
--
-- Policy matches the Java guard: only a role with the brush-tool capability
-- may remove an obelisk. If the Java API failed to expose, we still block
-- (protection fails closed) but cannot exempt admins or deliver the curse.
--

if not isServer() then
    return
end

local SPRITE_PREFIX = "atf_obelisks_"

local function isProtected(obj)
    if not obj or not obj.getSprite then
        return false
    end
    local sprite = obj:getSprite()
    local name = sprite and sprite:getName() or nil
    return name ~= nil and string.sub(name, 1, #SPRITE_PREFIX) == SPRITE_PREFIX
end

local function isRemovalAllowed(character)
    return SurvivorSkillObeliskApi ~= nil
        and character ~= nil
        and SurvivorSkillObeliskApi.isObeliskRemovalAllowed(character)
end

local originalDestroyComplete = ISDestroyStuffAction.complete
function ISDestroyStuffAction:complete()
    if not isProtected(self.item) or isRemovalAllowed(self.character) then
        return originalDestroyComplete(self)
    end
    if SurvivorSkillObeliskApi then
        SurvivorSkillObeliskApi.onBlockedObeliskDestroy(self.character, self.item)
    end
    return true
end

local originalMoveComplete = ISMoveablesAction.complete
function ISMoveablesAction:complete()
    if self.mode == "pickup" or self.mode == "scrap" then
        local target = self.moveProps and self.moveProps.object or nil
        if isProtected(target) and not isRemovalAllowed(self.character) then
            if SurvivorSkillObeliskApi then
                SurvivorSkillObeliskApi.onBlockedObeliskPickup(self.character, target)
            end
            return true
        end
    end
    return originalMoveComplete(self)
end
