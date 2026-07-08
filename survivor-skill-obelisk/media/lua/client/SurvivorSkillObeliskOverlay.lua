--
-- SurvivorSkillObeliskOverlay.lua
-- Attaches the paired `_on` glow sprite to each placed obelisk so the crisp
-- outline that the artist drew renders on top of the base sprite every frame.
--
-- PZ's built-in HasLightOnSprite pathway (IsoObject.hasAnimatedAttachments)
-- is gated on checkObjectPowered(), which needs a generator — exactly the
-- constraint UnpoweredGlow was written to bypass for the radial halo. This
-- module handles the sprite-overlay half of the same feature: it drops the
-- companion `_on` sprite into the placed obelisk's `attachedAnimSprite` list
-- and lets PZ's normal render pass draw it. Same code path fireplaces use to
-- attach fire; no power gate, no shader tricks.
--
-- Reload story mirrors UnpoweredGlow: the hooks table is stashed on a global
-- so a top-level re-execution can drop the previous registrations before
-- re-adding fresh ones.
--

SurvivorSkillObeliskOverlay = SurvivorSkillObeliskOverlay or {}

local BASE_PATTERN = "^atf_obelisks_(lg_01)_(%d+)$"
local BASE_PATTERN_SM = "^atf_obelisks_(sm_01)_(%d+)$"

local function overlayNameFor(spriteName)
    if spriteName == nil then
        return nil
    end
    local kind, idx = string.match(spriteName, BASE_PATTERN)
    if kind == nil then
        kind, idx = string.match(spriteName, BASE_PATTERN_SM)
    end
    if kind == nil then
        return nil
    end
    return "atf_obelisks_" .. kind .. "_on_" .. idx
end

local function attachOverlay(obj)
    if obj == nil then
        return
    end
    local sprite = obj:getSprite()
    if sprite == nil then
        return
    end
    local overlayName = overlayNameFor(sprite:getName())
    if overlayName == nil then
        return
    end
    local overlaySprite = IsoSpriteManager.instance:getSprite(overlayName)
    if overlaySprite == nil then
        return
    end
    if obj:isAttachedAnimSprite(overlaySprite) then
        return
    end
    obj:addAttachedAnimSprite(overlaySprite)
end

local function onObjectAdded(obj)
    attachOverlay(obj)
end

local function onLoadGridsquare(square)
    if square == nil then
        return
    end
    -- IsoGridSquare:getObjects() returns PZArrayList; indexed get(i) is the
    -- only safe traversal (iterator()/listIterator() throw).
    local objects = square:getObjects()
    if objects == nil then
        return
    end
    for i = 0, objects:size() - 1 do
        attachOverlay(objects:get(i))
    end
end

local function uninstallHooks(state)
    if state == nil or state.hooks == nil then
        return
    end
    if state.hooks.onObjectAdded ~= nil then
        Events.OnObjectAdded.Remove(state.hooks.onObjectAdded)
    end
    if state.hooks.onLoadGridsquare ~= nil then
        Events.LoadGridsquare.Remove(state.hooks.onLoadGridsquare)
    end
end

uninstallHooks(SurvivorSkillObeliskOverlay._state)

local hooks = {
    onObjectAdded = onObjectAdded,
    onLoadGridsquare = onLoadGridsquare,
}
SurvivorSkillObeliskOverlay._state = { hooks = hooks }

Events.OnObjectAdded.Add(onObjectAdded)
Events.LoadGridsquare.Add(onLoadGridsquare)

return SurvivorSkillObeliskOverlay
