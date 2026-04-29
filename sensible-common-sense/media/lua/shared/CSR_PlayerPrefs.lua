-- CSR_PlayerPrefs: per-player preference overrides stored in modData.
-- Each pref can override a sandbox setting with a player-local value.
-- nil override = use sandbox default. true/false = explicit player choice.
-- Server-side: getPlayer() returns nil so _overrides stays empty and all
-- feature flag checks fall through to sandbox defaults (correct behaviour).

CSR_PlayerPrefs = {}

-- PREFS registry. Each entry:
--   key         unique string used for modData and internal lookup
--   sandboxKey  SandboxVars.CommonSenseReborn field name
--   label       display name shown in the settings panel
--   effectiveFn function returning current effective value (including override)
--   adminLocked optional function returning true when admin controls this flag
CSR_PlayerPrefs.PREFS = {
    {
        key        = "EntryActions",
        sandboxKey = "EnableEntryActions",
        label      = "Entry Actions (Pry/Pick/Cut)",
        effectiveFn = function()
            return CSR_FeatureFlags and CSR_FeatureFlags.isEntryActionsEnabled() or false
        end,
    },
    {
        key        = "DualWield",
        sandboxKey = "EnableDualWield",
        label      = "Dual Wield",
        effectiveFn = function()
            return CSR_FeatureFlags and CSR_FeatureFlags.isDualWieldEnabled() or false
        end,
        adminLocked = function()
            return CSR_FeatureFlags and CSR_FeatureFlags.isAdminAuthoritative() or false
        end,
    },
    {
        -- v1.8.1: Auto-recovery for the "secondary slot vanished, weapon
        -- stuck stowed in inventory" symptom.  Default ON.  When ON, the
        -- client detector swaps the current primary into the secondary slot
        -- and re-equips the stuck weapon as the new primary -- guaranteeing
        -- a weapon in both hands during dual wield.
        key        = "DualWieldEmergencySwap",
        sandboxKey = nil,
        label      = "Dual Wield Emergency Swap",
        effectiveFn = function()
            local o = CSR_PlayerPrefs._overrides["DualWieldEmergencySwap"]
            if o == nil then return true end
            return o == true
        end,
    },
    {
        key        = "NestedContainers",
        sandboxKey = "EnableNestedContainers",
        label      = "Nested Containers",
        effectiveFn = function()
            return CSR_FeatureFlags and CSR_FeatureFlags.isNestedContainersEnabled() or false
        end,
    },
    {
        key        = "Back2Slot",
        sandboxKey = "EnableBack2Slot",
        label      = "Back to Slot",
        effectiveFn = function()
            return CSR_FeatureFlags and CSR_FeatureFlags.isBack2SlotEnabled() or false
        end,
    },
    {
        key        = "WeaponHudOverlay",
        sandboxKey = "EnableWeaponHudOverlay",
        label      = "Weapon HUD Overlay",
        effectiveFn = function()
            return CSR_FeatureFlags and CSR_FeatureFlags.isWeaponHudOverlayEnabled() or false
        end,
    },
    {
        key        = "ConeVisionOutline",
        sandboxKey = "EnableConeVisionOutline",
        label      = "Vision Cone Outline",
        effectiveFn = function()
            return CSR_FeatureFlags and CSR_FeatureFlags.isConeVisionOutlineEnabled() or false
        end,
    },
    {
        key        = "VisualSoundCues",
        sandboxKey = "EnableVisualSoundCues",
        label      = "Visual Sound Cues",
        effectiveFn = function()
            return CSR_FeatureFlags and CSR_FeatureFlags.isVisualSoundCuesEnabled() or false
        end,
    },
    {
        key        = "ItemInsightTooltips",
        sandboxKey = "EnableItemInsightTooltips",
        label      = "Item Insight Tooltips",
        effectiveFn = function()
            return CSR_FeatureFlags and CSR_FeatureFlags.isItemInsightTooltipsEnabled() or false
        end,
    },
    {
        key        = "ProximityLootHelper",
        sandboxKey = "EnableProximityLootHelper",
        label      = "Proximity Loot Helper",
        effectiveFn = function()
            return CSR_FeatureFlags and CSR_FeatureFlags.isProximityLootHelperEnabled() or false
        end,
    },
    {
        key        = "QuickSit",
        sandboxKey = "EnableQuickSit",
        label      = "Quick Sit",
        effectiveFn = function()
            return CSR_FeatureFlags and CSR_FeatureFlags.isQuickSitEnabled() or false
        end,
    },
    {
        key        = "WalkingItemActions",
        sandboxKey = "EnableWalkingItemActions",
        label      = "Walking Item Actions",
        effectiveFn = function()
            return CSR_FeatureFlags and CSR_FeatureFlags.isWalkingActionsEnabled() or false
        end,
    },
    {
        key        = "EatAllStack",
        sandboxKey = "EnableEatAllStack",
        label      = "Eat All Stack",
        effectiveFn = function()
            return CSR_FeatureFlags and CSR_FeatureFlags.isEatAllStackEnabled() or false
        end,
    },
    {
        key        = "HideWatermark",
        sandboxKey = "EnableHideWatermark",
        label      = "Hide Watermark",
        effectiveFn = function()
            return CSR_FeatureFlags and CSR_FeatureFlags.isHideWatermarkEnabled() or false
        end,
    },
    {
        key        = "CharInfoEnhancements",
        sandboxKey = "EnableCharacterInfoEnhancements",
        label      = "Character Info+",
        effectiveFn = function()
            return CSR_FeatureFlags and CSR_FeatureFlags.isCharacterInfoEnhancementsEnabled() or false
        end,
    },
    {
        key        = "AimingAmmoCursor",
        sandboxKey = "EnableAimingAmmoCursor",
        label      = "ADS Ammo Counter",
        effectiveFn = function()
            return CSR_FeatureFlags and CSR_FeatureFlags.isAimingAmmoCursorEnabled() or false
        end,
    },
    {
        key        = "AimingHealthCursor",
        sandboxKey = "EnableAimingHealthCursor",
        label      = "ADS Health Pill",
        effectiveFn = function()
            return CSR_FeatureFlags and CSR_FeatureFlags.isAimingHealthCursorEnabled() or false
        end,
    },
    {
        key        = "AimingDensityCursor",
        sandboxKey = "EnableAimingDensityCursor",
        label      = "ADS Zombie Density Pill",
        effectiveFn = function()
            return CSR_FeatureFlags and CSR_FeatureFlags.isAimingDensityCursorEnabled() or false
        end,
    },
    {
        key        = "SurvivorLedger",
        sandboxKey = "EnableSurvivorLedger",
        label      = "Survivor's Ledger",
        effectiveFn = function()
            return CSR_FeatureFlags and CSR_FeatureFlags.isSurvivorLedgerEnabled() or false
        end,
    },
    {
        key        = "GearSling",
        sandboxKey = "EnableGearSling",
        label      = "Gear Sling (reload required)",
        effectiveFn = function()
            return CSR_FeatureFlags and CSR_FeatureFlags.isGearSlingEnabled() or false
        end,
    },
    {
        key        = "PassiveGenOverlay",
        sandboxKey = nil,
        label      = "Passive Generator Overlay",
        effectiveFn = function()
            local p = getPlayer and getPlayer() or nil
            if not (p and p.getModData) then return false end
            return p:getModData().CSR_PassiveGenOverlay == true
        end,
    },
}

-- Fast lookup by key
CSR_PlayerPrefs._byKey = {}
for _, p in ipairs(CSR_PlayerPrefs.PREFS) do
    CSR_PlayerPrefs._byKey[p.key] = p
end

local MODDATA_PREFIX = "CSRPref_"

-- In-memory overrides: key -> true/false (absent = use sandbox)
CSR_PlayerPrefs._overrides = {}

local function getModData()
    local player = getPlayer and getPlayer() or nil
    return player and player:getModData() or nil
end

-- Returns the raw override for a key, or nil if not overridden.
function CSR_PlayerPrefs.getOverride(key)
    return CSR_PlayerPrefs._overrides[key]
end

-- Set an explicit override (pass nil to clear and revert to sandbox).
function CSR_PlayerPrefs.set(key, value)
    CSR_PlayerPrefs._overrides[key] = value
    local modData = getModData()
    if not modData then return end
    if value == nil then
        modData[MODDATA_PREFIX .. key] = nil
    else
        modData[MODDATA_PREFIX .. key] = value == true
    end
    -- Keep the legacy DW key in sync so old saves continue to work.
    if key == "DualWield" then
        modData["CSRDualWieldEnabled"] = value
        -- Also keep the FeatureFlags legacy field in sync.
        if CSR_FeatureFlags then
            CSR_FeatureFlags._dualWieldLocalOverride = value
        end
    end
    -- v1.7.10: forward overlay toggles to their owning module's persisted key
    -- so the in-game state matches the S-panel choice without a reload.
    if key == "PassiveGenOverlay" then
        modData["CSR_PassiveGenOverlay"] = (value == true)
    end
end

-- Toggle a pref using its current effective value as the base.
-- Returns the new effective value.
function CSR_PlayerPrefs.toggle(key)
    local pref = CSR_PlayerPrefs._byKey[key]
    if not pref then return false end
    local current = pref.effectiveFn()
    CSR_PlayerPrefs.set(key, not current)
    return not current
end

-- Clear override for a key (revert to sandbox default).
function CSR_PlayerPrefs.reset(key)
    CSR_PlayerPrefs.set(key, nil)
end

-- Load all per-player overrides from modData. Call on OnGameStart.
function CSR_PlayerPrefs.load()
    CSR_PlayerPrefs._overrides = {}
    local modData = getModData()
    if not modData then return end

    for _, pref in ipairs(CSR_PlayerPrefs.PREFS) do
        local stored = modData[MODDATA_PREFIX .. pref.key]
        if stored ~= nil then
            CSR_PlayerPrefs._overrides[pref.key] = stored == true
        end
    end

    -- Migrate legacy DW key into the new system if no new key was saved yet.
    if CSR_PlayerPrefs._overrides["DualWield"] == nil then
        local legacy = modData["CSRDualWieldEnabled"]
        if legacy ~= nil then
            CSR_PlayerPrefs._overrides["DualWield"] = legacy == true
        end
    end

    -- Keep FeatureFlags legacy field in sync for any code still reading it.
    if CSR_FeatureFlags then
        CSR_FeatureFlags._dualWieldLocalOverride = CSR_PlayerPrefs._overrides["DualWield"]
    end
end
