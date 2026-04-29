require "CSR_FeatureFlags"
require "TimedActions/CSR_UncapBarrelAction"

--[[
    CSR_UsefulBarrels.lua
    Adds an "Uncap Barrel" context-menu option to vanilla barrel world objects.
    Requires a pipe wrench. Once uncapped the barrel gains a native
    FluidContainer component — vanilla PZ handles all fluid transfer, rain
    collection, and UI from that point.  Safe to remove: the component is
    vanilla, only the uncap action is mod-provided.
]]

CSR_UsefulBarrels = {}

-- Vanilla moveable barrel item IDs
local BARREL_ITEMS = {
    ["Base.MetalDrum"]             = true,
    ["Base.Mov_LightGreenBarrel"]  = true,
    ["Base.Mov_OrangeBarrel"]      = true,
    ["Base.Mov_DarkGreenBarrel"]   = true,
}

-- =========================================================================
-- Detection helpers
-- =========================================================================

local function isBarrel(obj)
    if not obj then return false end
    -- Exclude player-built carpentry containers (rain collectors etc.)
    -- that may share the same CustomItem property string. Carpentry
    -- objects are IsoThumpable instances with their own native
    -- FluidContainer + display name; CSR's uncap pass would shadow
    -- them and rename them to "open wooden barrel".
    if instanceof and instanceof(obj, "IsoThumpable") then return false end
    local props = obj:getProperties()
    if not props then return false end
    local ci = props:get("CustomItem")
    return ci ~= nil and BARREL_ITEMS[ci] == true
end

local function alreadyOpen(obj)
    return obj:hasComponent(ComponentType.FluidContainer)
end

-- =========================================================================
-- Context menu
-- =========================================================================

-- Build a "Fluid -> Transfer Liquid / Container Info / Empty" submenu for an
-- already-uncapped barrel. We add this ourselves because vanilla's auto-injected
-- fluid context menu only fires on IsoObjects that were created as full
-- GameEntities with a sprite-bound entity script (e.g. carpentry rain barrels
-- via GameEntityFactory.CreateIsoObjectEntity). Manually attaching a
-- FluidContainer component to a moveable barrel via GameEntityFactory.AddComponent
-- gives the object a working FluidContainer (rain catches, capacity is honoured)
-- but no auto context-menu wiring -- so without this submenu the player has no
-- way to pour liquid in or transfer it out.
local function addFluidSubmenu(context, obj, playerNum)
    local cont = obj.getFluidContainer and obj:getFluidContainer() or nil
    if not cont then return end

    local fluidOption = context:addOption(getText("ContextMenu_Fluid"), nil)
    if getTexture then
        local tex = getTexture("Item_WaterDrop")
        if tex then fluidOption.iconTexture = tex end
    end
    local subMenu = ISContextMenu:getNew(context)
    context:addSubMenu(fluidOption, subMenu)

    -- Re-use the vanilla world handlers; they accept the FluidContainer Java
    -- component directly and walk/open the correct UI for an IsoObject owner.
    subMenu:addOption(getText("Fluid_Transfer_Fluids"), playerNum,
        ISWorldObjectContextMenu.onFluidTransfer, cont)
    subMenu:addOption(getText("Fluid_Show_Info"), playerNum,
        ISWorldObjectContextMenu.onFluidInfo, cont)
    if cont.isEmpty and not cont:isEmpty() and cont.canPlayerEmpty and cont:canPlayerEmpty() then
        subMenu:addOption(getText("Fluid_Empty"), playerNum,
            ISWorldObjectContextMenu.onFluidEmpty, cont)
    end
end

local function onWorldMenu(playerNum, context, worldObjects, test)
    if not CSR_FeatureFlags.isUsefulBarrelsEnabled() then return end
    if test then return end

    local player = getSpecificPlayer(playerNum)
    if not player or player:isDead() then return end

    for i = 1, #worldObjects do
        local obj = worldObjects[i]
        if isBarrel(obj) then
            if not alreadyOpen(obj) then
                local wrench = player:getInventory():getFirstTypeRecurse("PipeWrench")
                if wrench then
                    local option = context:addOption(
                        getText("ContextMenu_CSR_UncapBarrel"), obj,
                        CSR_UsefulBarrels.doUncap, player, wrench
                    )
                    local tooltip = ISWorldObjectContextMenu.addToolTip()
                    tooltip.description = getText("Tooltip_CSR_UncapBarrel")
                    option.toolTip = tooltip
                end
            else
                -- Uncapped barrel: expose Transfer Liquid / Info / Empty.
                addFluidSubmenu(context, obj, playerNum)
            end
            break
        end
    end
end

function CSR_UsefulBarrels.doUncap(barrel, player, wrench)
    if luautils.walkAdj(player, barrel:getSquare()) then
        ISTimedActionQueue.add(ISEquipWeaponAction:new(player, wrench, 25, true, false))
        ISTimedActionQueue.add(CSR_UncapBarrelAction:new(player, barrel, wrench))
    end
end

Events.OnFillWorldObjectContextMenu.Add(onWorldMenu)
