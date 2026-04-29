require "CSR_FeatureFlags"

--[[
    CSR_BagDropDiag.lua
    -------------------------------------------------------------------------
    OFF by default. When sandbox option CSR_DebugBagDrop is ON, prints a
    short trace each time the player attempts a cross-pane drop onto a
    side-panel bag button. Used to diagnose the "drag from loot window
    onto bag icon doesn't drop" bug without guessing.

    All output goes to the standard PZ console / console.txt with a
    [CSR-BagDrop] prefix so a tester can grep for it.
--]]

local function isEnabled()
    if CSR_FeatureFlags and CSR_FeatureFlags.isBagDropDiagEnabled then
        return CSR_FeatureFlags.isBagDropDiagEnabled()
    end
    local sb = SandboxVars and SandboxVars.CommonSenseReborn or nil
    if not sb then return false end
    return sb.CSR_DebugBagDrop == true
end

local function tag(s)
    return "[CSR-BagDrop] " .. tostring(s)
end

local function describeButton(btn)
    if not btn then return "nil" end
    local inv = btn.inventory
    if not inv then return "btn(no inventory)" end
    local containing = inv.getContainingItem and inv:getContainingItem() or nil
    local name = containing and containing.getName and containing:getName() or "(main inventory)"
    local invType = inv.getType and inv:getType() or "?"
    return string.format("btn(name=%s, type=%s, isCSRNested=%s)",
        tostring(name), tostring(invType), tostring(btn._csr_nested == true))
end

local function describeDragging()
    local d = ISMouseDrag and ISMouseDrag.dragging
    if not d then return "ISMouseDrag.dragging=nil" end
    if type(d) == "table" then
        return "ISMouseDrag.dragging=table[" .. tostring(#d) .. " entries]"
    end
    return "ISMouseDrag.dragging=" .. tostring(d)
end

local patched = false

local function patch()
    if patched then return end
    if not ISInventoryPage then return end
    patched = true

    local origDropItemsInContainer = ISInventoryPage.dropItemsInContainer
    function ISInventoryPage:dropItemsInContainer(button)
        if isEnabled() then
            print(tag(string.format("dropItemsInContainer ENTER  player=%s  pressed=%s  %s  %s",
                tostring(self.player),
                tostring(button and button.pressed),
                describeButton(button),
                describeDragging())))
        end
        local ok, result = pcall(origDropItemsInContainer, self, button)
        if isEnabled() then
            if not ok then
                print(tag("dropItemsInContainer ERROR: " .. tostring(result)))
            else
                print(tag("dropItemsInContainer EXIT   returned=" .. tostring(result)))
            end
        end
        if not ok then error(result) end
        return result
    end

    local origOnBackpackMouseUp = ISInventoryPage.onBackpackMouseUp
    function ISInventoryPage:onBackpackMouseUp(x, y)
        if isEnabled() then
            print(tag(string.format("onBackpackMouseUp ENTER  pressed=%s  %s  %s",
                tostring(self.pressed),
                describeButton(self),
                describeDragging())))
        end
        return origOnBackpackMouseUp(self, x, y)
    end
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(patch)
end
