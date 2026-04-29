require "CSR_FeatureFlags"

--[[
    CSR_GearSling.lua
    Adds a second equip slot (csr:gearsling) to the Human BodyLocations group,
    allowing players to carry a sling-style or shoulder bag in addition to their
    main backpack.

    The BodyLocation is registered once at file load time.  DoParam calls that
    map the curated bag list to the new slot are applied in OnGameStart, after
    ScriptManager is guaranteed to be fully populated.

    Gated by EnableGearSling sandbox option (default on).
]]

local LOCATION_ID = "csr:gearsling"
local FANNY_LOCATION_ID = "csr:fannypack"

-- Vanilla-only bags that are realistically worn crossbody / over-the-shoulder.
-- Excludes full backpacks, long weapon cases, and hand-held bags.
local GEAR_SLING_BAGS = {
    "Base.Bag_DuffelBag",
    "Base.Bag_DuffelBagTINT",
    "Base.Bag_WorkerBag",
    "Base.Bag_BreakdownBag",
    "Base.Bag_BurglarBag",
    "Base.Bag_ToolBag",
    "Base.Bag_Military",
    "Base.Bag_InmateEscapedBag",
    "Base.Bag_MoneyBag",
    "Base.Bag_Satchel",
    "Base.Bag_Satchel_Fishing",
    "Base.Bag_Satchel_Medical",
    "Base.Bag_Satchel_Military",
    "Base.Bag_Satchel_Leather",
    "Base.Bag_Satchel_Mail",
    "Base.Bag_SatchelPhoto",
    "Base.Bag_ClothSatchel_Burlap",
    "Base.Bag_ClothSatchel_Cotton",
    "Base.Bag_ClothSatchel_Denim",
    "Base.Bag_ClothSatchel_DenimBlack",
    "Base.Bag_ClothSatchel_DenimLight",
    "Base.Bag_ChestRig",
    "Base.Bag_ChestRig_Tarp",
    "Base.Bag_Police",
    "Base.Bag_Sheriff",
    "Base.Bag_SWAT",
    "Base.Bag_HideSlingBag",
    "Base.Bag_SheetSlingBag",
    "Base.Bag_TarpSlingBag",
    "Base.Bag_HideSatchel",
    "Base.Bag_CrudeLeatherBag",
    "Base.Bag_CrudeTarpBag",
    "Base.Bag_Mail",
    "Base.Bag_MedicalBag",
    "Base.Bag_DoctorBag",
}

-- Fanny packs get their own dedicated CSR slot so they can coexist with
-- both a backpack (vanilla Back) and a sling/duffle (csr:gearsling).
local FANNY_PACK_BAGS = {
    "Base.Bag_FannyPackFront",
    "Base.Bag_FannyPackBack",
    "Base.Bag_FannyPackFront_Hide",
    "Base.Bag_FannyPackBack_Hide",
    "Base.Bag_FannyPackFront_Tarp",
    "Base.Bag_FannyPackBack_Tarp",
}

local locationRegistered = false

local function registerBodyLocation()
    if locationRegistered then return end
    local ok, err = pcall(function()
        if not BodyLocations or not ItemBodyLocation then return end
        local group = BodyLocations.getGroup("Human")
        if not group then return end
        group:getOrCreateLocation(ItemBodyLocation.register(LOCATION_ID))
        group:getOrCreateLocation(ItemBodyLocation.register(FANNY_LOCATION_ID))
        locationRegistered = true
    end)
    if not ok then
        print("[CSR] GearSling: BodyLocation registration error: " .. tostring(err))
    end
end

-- B42's CanBeEquipped script field is single-valued, so this pass
-- intentionally MOVES each curated bag from its vanilla slot to
-- csr:gearsling rather than appending. That is the documented design
-- of the Gear Sling feature: opting in routes these bags through the
-- new sling slot so a backpack can be worn on the back at the same
-- time. Players who do not want this behaviour can disable
-- EnableGearSling in sandbox.
local function applyDoParams()
    if not CSR_FeatureFlags or not CSR_FeatureFlags.isGearSlingEnabled or not CSR_FeatureFlags.isGearSlingEnabled() then
        return
    end
    if not getScriptManager then return end
    local sm = getScriptManager()
    if not sm then return end
    for i = 1, #GEAR_SLING_BAGS do
        local fullType = GEAR_SLING_BAGS[i]
        local script = sm:getItem(fullType)
        if script and script.DoParam then
            local ok, err = pcall(function()
                script:DoParam("CanBeEquipped = " .. LOCATION_ID)
            end)
            if not ok then
                print("[CSR] GearSling: DoParam failed for " .. tostring(fullType) .. ": " .. tostring(err))
            end
        end
    end
    -- Fanny packs go to their own dedicated CSR slot so they coexist with
    -- both a backpack (vanilla Back) and a sling/duffle (csr:gearsling).
    for i = 1, #FANNY_PACK_BAGS do
        local fullType = FANNY_PACK_BAGS[i]
        local script = sm:getItem(fullType)
        if script and script.DoParam then
            local ok, err = pcall(function()
                script:DoParam("CanBeEquipped = " .. FANNY_LOCATION_ID)
            end)
            if not ok then
                print("[CSR] GearSling: DoParam (fanny) failed for " .. tostring(fullType) .. ": " .. tostring(err))
            end
        end
    end
end

-- Register the BodyLocation at file load time so the engine sees it before
-- any character is created.  DoParam is deferred to OnGameStart when
-- ScriptManager is fully loaded.
registerBodyLocation()

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(applyDoParams)
end
