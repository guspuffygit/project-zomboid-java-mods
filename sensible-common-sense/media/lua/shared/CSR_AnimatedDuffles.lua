--[[
    CSR_AnimatedDuffles
    -------------------
    Bundles Skully's Duffels And Rigs assets (item scripts, clothing XMLs, skinned 3D
    meshes and textures) directly into Common Sense Reborn so that vanilla duffel-class
    bags gain a right-click "Equip on Back > Equip on Lower Back" option that places the
    bag on a separate Lower Back slot using a rigged 3D model that animates with the
    character. This frees the upper Back slot for a backpack.

    Used with permission from Skully. Original meshes by Alice (Duffel Bag Mod).

    All asset paths and item names mirror Skully's mod exactly so behaviour matches
    his standalone mod. If a player has both mods enabled, ours becomes a no-op
    (we detect Skully's activated mod ID and bail).

    The custom body locations themselves are registered globally in registries.lua
    (file scope, runs before the script manager loads items so DoParam binds to the
    correct location).
]]

require "BodyLocations"

local DUFFLE_BAGS = {
    "Bag_DuffelBag", "Bag_DuffelBagTINT", "Bag_WeaponBag", "Bag_InmateEscapedBag",
    "Bag_MoneyBag", "Bag_WorkerBag", "Bag_ShotgunBag", "Bag_MedicalBag",
    "Bag_ShotgunSawnoffBag", "Bag_ShotgunDblBag", "Bag_ShotgunDblSawnoffBag",
    "Bag_FoodCanned", "Bag_FoodSnacks", "Bag_ToolBag", "Bag_Military",
    "Bag_BurglarBag", "Bag_Police", "Bag_SWAT", "Bag_Sheriff",
    "Bag_BreakdownBag", "Bag_TennisBag", "Bag_BaseballBag",
}

local ALICE_RIGS = {
    "Bag_ALICE_BeltSus", "Bag_ALICE_BeltSus_Camo", "Bag_ALICE_BeltSus_Green",
    "Bag_ChestRig", "Bag_ChestRig_Tarp",
    "ALICE.AliceVest4P1C1HTight", "ALICE.AliceVest4P1C1HLoosen",
    "ALICE.AliceVest2P1C1HTight", "ALICE.AliceVest2P1C1HLoosen",
    "ALICE.AliceVest4P2CTight",   "ALICE.AliceVest4P2CLoosen",
    "ALICE.AliceVest2P2CTight",   "ALICE.AliceVest2P2CLoosen",
    "ALICE.AliceVest4P1C1ETight", "ALICE.AliceVest4P1C1ELoosen",
    "ALICE.AliceVest2P1C1ETight", "ALICE.AliceVest2P1C1ELoosen",
    "ALICE.AliceVest4PTight",     "ALICE.AliceVest4PLoosen",
    "ALICE.AliceVest2PTight",     "ALICE.AliceVest2PLoosen",
}

local function isSkullysActivated()
    if not getActivatedMods then return false end
    local mods = getActivatedMods()
    if not mods then return false end
    for i = 0, mods:size() - 1 do
        local id = mods:get(i)
        if id == "SkullysDuffelsAndRigs" then return true end
    end
    return false
end

local function ensureBodyLocations()
    -- registries.lua already calls ItemBodyLocation.register; here we attach the
    -- locations to the Human group so the engine actually allocates a slot index.
    if not BodyLocations or not BodyLocations.getGroup then return end
    local group = BodyLocations.getGroup("Human")
    if not group then return end
    if CustomBodyLocation and CustomBodyLocation.ItemBodyLocation then
        if CustomBodyLocation.ItemBodyLocation.LowerBack then
            group:getOrCreateLocation(CustomBodyLocation.ItemBodyLocation.LowerBack)
        end
        if CustomBodyLocation.ItemBodyLocation.NewRigLocation then
            group:getOrCreateLocation(CustomBodyLocation.ItemBodyLocation.NewRigLocation)
        end
    end
end

local function applyDoParams()
    if CSR_FeatureFlags and CSR_FeatureFlags.isAnimatedDufflesEnabled
        and not CSR_FeatureFlags.isAnimatedDufflesEnabled() then
        return
    end
    if isSkullysActivated() then
        -- Skully's standalone mod handles the same items; bail to avoid double DoParam.
        return
    end
    if not ScriptManager or not ScriptManager.instance then return end
    local sm = ScriptManager.instance

    for _, bagName in ipairs(DUFFLE_BAGS) do
        local item = sm:getItem(bagName)
        if item then
            item:DoParam("ClothingItemExtra = " .. bagName .. "_LB")
            item:DoParam("ClothingItemExtraOption = LowerBack")
            item:DoParam("clothingExtraSubmenu = OnBack")
        end
    end

    for _, rigName in ipairs(ALICE_RIGS) do
        local item = sm:getItem(rigName)
        if item then
            item:DoParam("BodyLocation = custombodylocation:NewRigLocation")
            item:DoParam("CanBeEquipped = custombodylocation:NewRigLocation")
        end
    end
end

local function bootstrap()
    ensureBodyLocations()
    applyDoParams()
end

-- OnGameBoot fires before the world loads (and before items are first instanced),
-- which is when DoParam needs to run so the new properties are baked in.
Events.OnGameBoot.Add(bootstrap)
