CSR_FeatureFlags = {}

local function sandbox()
    return SandboxVars and SandboxVars.CommonSenseReborn or {}
end

function CSR_FeatureFlags.isEntryActionsEnabled()
    if CSR_PlayerPrefs then
        local override = CSR_PlayerPrefs.getOverride("EntryActions")
        if override ~= nil then return override end
    end
    return sandbox().EnableEntryActions ~= false
end

function CSR_FeatureFlags.isPryEnabled()
    return CSR_FeatureFlags.isEntryActionsEnabled() and sandbox().EnablePrySystem == true
end

function CSR_FeatureFlags.isLockpickEnabled()
    return CSR_FeatureFlags.isEntryActionsEnabled() and sandbox().EnableScrewdriverLockpick ~= false
end

function CSR_FeatureFlags.isAlternateCanOpeningEnabled()
    return sandbox().EnableAlternateCanOpening ~= false
end

function CSR_FeatureFlags.isRepairEnabled()
    return sandbox().EnableRepairExtensions ~= false
end

function CSR_FeatureFlags.isRepairAllClothingEnabled()
    return CSR_FeatureFlags.isRepairEnabled() and sandbox().EnableRepairAllClothing ~= false
end

function CSR_FeatureFlags.isEquipmentQoLEnabled()
    return sandbox().EnableEquipmentQoL ~= false
end

function CSR_FeatureFlags.isCorpseIgniteEnabled()
    return sandbox().EnableCorpseIgnite ~= false
end

function CSR_FeatureFlags.isPlayerMapTrackingEnabled()
    return sandbox().EnablePlayerMapTracking ~= false and (sandbox().PlayerMapVisibilityMode or 1) ~= 3
end

function CSR_FeatureFlags.isSeatbeltEnabled()
    return sandbox().EnableSeatbeltProtection ~= false
end

function CSR_FeatureFlags.isWalkingActionsEnabled()
    if CSR_PlayerPrefs then
        local override = CSR_PlayerPrefs.getOverride("WalkingItemActions")
        if override ~= nil then return override end
    end
    return sandbox().EnableWalkingItemActions ~= false
end

function CSR_FeatureFlags.isVehicleMechanicsQoLEnabled()
    return sandbox().EnableVehicleMechanicsQoL ~= false
end

function CSR_FeatureFlags.isImprovisedHotwireEnabled()
    return sandbox().EnableImprovisedHotwire ~= false
end

function CSR_FeatureFlags.isUnHotwireEnabled()
    return sandbox().EnableUnHotwire ~= false
end

function CSR_FeatureFlags.isVehicleDoorPryEnabled()
    return sandbox().EnableVehicleDoorPry ~= false and CSR_FeatureFlags.isPryEnabled()
end

function CSR_FeatureFlags.isGarageDoorPryEnabled()
    return sandbox().EnableGarageDoorPry ~= false and CSR_FeatureFlags.isPryEnabled()
end

function CSR_FeatureFlags.isSafeDoorPryEnabled()
    return sandbox().EnableSafeDoorPry == true and CSR_FeatureFlags.isPryEnabled()
end

function CSR_FeatureFlags.isWashMenuSplitEnabled()
    return sandbox().EnableWashMenuSplits ~= false
end

function CSR_FeatureFlags.isDashboardHighlightsEnabled()
    return sandbox().EnableDashboardHighlights ~= false
end

function CSR_FeatureFlags.isPourCanContentsEnabled()
    return sandbox().EnablePourCanContents ~= false
end

function CSR_FeatureFlags.isProximityLootHelperEnabled()
    if CSR_PlayerPrefs then
        local override = CSR_PlayerPrefs.getOverride("ProximityLootHelper")
        if override ~= nil then return override end
    end
    return sandbox().EnableProximityLootHelper ~= false
end

function CSR_FeatureFlags.isZombieDensityOverlayEnabled()
    return sandbox().EnableZombieDensityOverlay ~= false
end

-- Deprecated in v1.6.7: minimap density heatmap removed (severe per-frame cost).
-- Replaced by CSR_NearbyDensityHUD draggable on-screen widget. Always returns
-- false so any leftover code paths cleanly no-op.
function CSR_FeatureFlags.isZombieDensityMinimapEnabled()
    return false
end

function CSR_FeatureFlags.isUtilityHudEnabled()
    return sandbox().EnableUtilityHud ~= false
end

function CSR_FeatureFlags.isLootFilterEnabled()
    return sandbox().EnableLootFilter ~= false
end

function CSR_FeatureFlags.isItemInsightTooltipsEnabled()
    if CSR_PlayerPrefs then
        local override = CSR_PlayerPrefs.getOverride("ItemInsightTooltips")
        if override ~= nil then return override end
    end
    return sandbox().EnableItemInsightTooltips ~= false
end

function CSR_FeatureFlags.isSmartVehicleKeyLabelsEnabled()
    return sandbox().EnableSmartVehicleKeyLabels ~= false
end

function CSR_FeatureFlags.isEatAllStackEnabled()
    if CSR_PlayerPrefs then
        local override = CSR_PlayerPrefs.getOverride("EatAllStack")
        if override ~= nil then return override end
    end
    return sandbox().EnableEatAllStack ~= false
end

function CSR_FeatureFlags.isMagazineBatchActionsEnabled()
    return sandbox().EnableMagazineBatchActions ~= false
end

function CSR_FeatureFlags.isQuickDeviceToggleEnabled()
    return sandbox().EnableQuickDeviceToggle ~= false
end

function CSR_FeatureFlags.isVisualSoundCuesEnabled()
    if CSR_PlayerPrefs then
        local override = CSR_PlayerPrefs.getOverride("VisualSoundCues")
        if override ~= nil then return override end
    end
    return sandbox().EnableVisualSoundCues ~= false
end

function CSR_FeatureFlags.isVehicleClockEnabled()
    return sandbox().EnableVehicleClock ~= false
end

function CSR_FeatureFlags.isSweepTrashEnabled()
    return sandbox().EnableSweepTrash ~= false
end

function CSR_FeatureFlags.isSweepAshesEnabled()
    return sandbox().EnableSweepAshes ~= false
end

function CSR_FeatureFlags.isClipboardEnabled()
    return sandbox().EnableClipboardQoL ~= false
end

function CSR_FeatureFlags.isQuickSitEnabled()
    if CSR_PlayerPrefs then
        local override = CSR_PlayerPrefs.getOverride("QuickSit")
        if override ~= nil then return override end
    end
    return sandbox().EnableQuickSit ~= false
end

function CSR_FeatureFlags.isWeaponHudOverlayEnabled()
    if CSR_FeatureFlags.isCleanHotBarActive() then return false end
    if CSR_PlayerPrefs then
        local override = CSR_PlayerPrefs.getOverride("WeaponHudOverlay")
        if override ~= nil then return override end
    end
    return sandbox().EnableWeaponHudOverlay ~= false
end

function CSR_FeatureFlags.isCleanHotBarActive()
    return getActivatedMods and getActivatedMods():contains("CleanHotBar") or false
end

function CSR_FeatureFlags.isLadderClimbEnabled()
    return sandbox().EnableLadderClimb ~= false
end

-- Diagnostic-only: when ON, prints a trace each time the player attempts a
-- cross-pane drop onto a side-panel bag button. Default OFF.
function CSR_FeatureFlags.isBagDropDiagEnabled()
    return sandbox().CSR_DebugBagDrop == true
end

function CSR_FeatureFlags.isFireworkEnabled()
    return sandbox().EnableFirework ~= false
end

function CSR_FeatureFlags.isNoticeBoardEnabled()
    return sandbox().EnableNoticeBoard ~= false
end

function CSR_FeatureFlags.isBoltCutterEnabled()
    return sandbox().EnableBoltCutter ~= false and CSR_FeatureFlags.isPryEnabled()
end

function CSR_FeatureFlags.isAdminAuthoritative()
    return sandbox().AdminAuthoritativeControl == true
end

-- Client-local override: nil = use sandbox, true/false = player override.
-- Kept for backward compatibility; CSR_PlayerPrefs is the primary store now.
CSR_FeatureFlags._dualWieldLocalOverride = nil

function CSR_FeatureFlags.isDualWieldEnabled()
    if CSR_FeatureFlags.isAdminAuthoritative() then
        return sandbox().EnableDualWield ~= false
    end
    if CSR_PlayerPrefs then
        local override = CSR_PlayerPrefs.getOverride("DualWield")
        if override ~= nil then return override end
    end
    -- Legacy field fallback (populated by CSR_PlayerPrefs.load() migration)
    if CSR_FeatureFlags._dualWieldLocalOverride ~= nil then
        return CSR_FeatureFlags._dualWieldLocalOverride == true
    end
    return sandbox().EnableDualWield ~= false
end

function CSR_FeatureFlags.toggleDualWieldLocal()
    if CSR_FeatureFlags.isAdminAuthoritative() then return CSR_FeatureFlags.isDualWieldEnabled() end
    local current = CSR_FeatureFlags.isDualWieldEnabled()
    CSR_FeatureFlags._dualWieldLocalOverride = not current
    return not current
end

function CSR_FeatureFlags.isAdvancedSoundOptionsEnabled()
    return sandbox().EnableAdvancedSoundOptions ~= false
end

function CSR_FeatureFlags.isSawAllDropToGroundEnabled()
    return sandbox().EnableSawAllDropToGround == true
end

function CSR_FeatureFlags.isTowelDryingEnabled()
    return sandbox().EnableTowelDrying ~= false
end

function CSR_FeatureFlags.isSleepAnywhereEnabled()
    return sandbox().EnableSleepAnywhere ~= false
end

function CSR_FeatureFlags.isDismantleAllWatchesEnabled()
    return sandbox().EnableDismantleAllWatches ~= false
end

function CSR_FeatureFlags.isMassageEnabled()
    return sandbox().EnableMassage ~= false
end

function CSR_FeatureFlags.isHideInFurnitureEnabled()
    return sandbox().EnableHideInFurniture ~= false
end

function CSR_FeatureFlags.isPointBlankEnabled()
    return sandbox().EnablePointBlank ~= false
end

function CSR_FeatureFlags.isVehicleSalvageEnabled()
    return sandbox().EnableVehicleSalvage ~= false
end

function CSR_FeatureFlags.isItemRenameEnabled()
    return sandbox().EnableItemRename ~= false
end

function CSR_FeatureFlags.isVehicleHVACEnabled()
    return sandbox().EnableVehicleHVAC ~= false
end

function CSR_FeatureFlags.isCharacterInfoEnhancementsEnabled()
    if CSR_PlayerPrefs then
        local override = CSR_PlayerPrefs.getOverride("CharInfoEnhancements")
        if override ~= nil then return override end
    end
    return sandbox().EnableCharacterInfoEnhancements ~= false
end

function CSR_FeatureFlags.isWearableSlotFixEnabled()
    return sandbox().EnableWearableSlotFix ~= false
end

function CSR_FeatureFlags.isClimbWithGeneratorEnabled()
    return sandbox().EnableClimbWithGenerator ~= false
end

function CSR_FeatureFlags.isRoomScannerEnabled()
    return sandbox().EnableRoomScanner ~= false and CSR_FeatureFlags.isClipboardEnabled()
end

function CSR_FeatureFlags.isVehicleRadioEnabled()
    return sandbox().EnableVehicleRadio ~= false
end

function CSR_FeatureFlags.isHideWatermarkEnabled()
    if CSR_PlayerPrefs then
        local override = CSR_PlayerPrefs.getOverride("HideWatermark")
        if override ~= nil then return override end
    end
    return sandbox().EnableHideWatermark ~= false
end

function CSR_FeatureFlags.isSleepBenefitsEnabled()
    return sandbox().EnableSleepBenefits ~= false
end

function CSR_FeatureFlags.isBagBottomAttachEnabled()
    return sandbox().EnableBagBottomAttach ~= false
end

function CSR_FeatureFlags.isNestedContainersEnabled()
    if CSR_PlayerPrefs then
        local override = CSR_PlayerPrefs.getOverride("NestedContainers")
        if override ~= nil then return override end
    end
    return sandbox().EnableNestedContainers ~= false
end

function CSR_FeatureFlags.isToolSetEnabled()
    return sandbox().EnableToolSet ~= false
end

function CSR_FeatureFlags.isBulletPenetrationEnabled()
    return sandbox().EnableBulletPenetration ~= false
end

function CSR_FeatureFlags.isBack2SlotEnabled()
    if CSR_PlayerPrefs then
        local override = CSR_PlayerPrefs.getOverride("Back2Slot")
        if override ~= nil then return override end
    end
    return sandbox().EnableBack2Slot ~= false
end

function CSR_FeatureFlags.isWarmUpEnabled()
    return sandbox().EnableWarmUp ~= false
end

function CSR_FeatureFlags.isStopDropRollEnabled()
    return sandbox().EnableStopDropRoll ~= false
end

function CSR_FeatureFlags.isConeVisionOutlineEnabled()
    if CSR_PlayerPrefs then
        local override = CSR_PlayerPrefs.getOverride("ConeVisionOutline")
        if override ~= nil then return override end
    end
    return sandbox().EnableConeVisionOutline ~= false
end

function CSR_FeatureFlags.isExerciseWithGearEnabled()
    return sandbox().EnableExerciseWithGear ~= false
end

function CSR_FeatureFlags.isInfectionResilienceEnabled()
    return sandbox().EnableInfectionResilience ~= false
end

function CSR_FeatureFlags.isUsefulBarrelsEnabled()
    return sandbox().EnableUsefulBarrels ~= false
end

function CSR_FeatureFlags.isClimbWithBagsEnabled()
    return sandbox().EnableClimbWithBags ~= false
end

function CSR_FeatureFlags.isFieldFiltersEnabled()
    return sandbox().EnableFieldFilters ~= false
end

function CSR_FeatureFlags.isTowAssistEnabled()
    return sandbox().EnableTowAssist ~= false
end

function CSR_FeatureFlags.isGeneratorInfoEnabled()
    return sandbox().EnableGeneratorInfo ~= false
end

function CSR_FeatureFlags.isVideoInsertEnabled()
    return sandbox().EnableVideoInsert ~= false
end

function CSR_FeatureFlags.isTVRadialEnabled()
    return sandbox().EnableTVRadial ~= false
end

function CSR_FeatureFlags.isAnimatedDufflesEnabled()
    return sandbox().EnableAnimatedDuffles ~= false
end

function CSR_FeatureFlags.isAimingAmmoCursorEnabled()
    if CSR_FeatureFlags.isCleanHotBarActive() then return false end
    if CSR_PlayerPrefs then
        local override = CSR_PlayerPrefs.getOverride("AimingAmmoCursor")
        if override ~= nil then return override end
    end
    return sandbox().EnableAimingAmmoCursor ~= false
end

function CSR_FeatureFlags.isAimingHealthCursorEnabled()
    if CSR_FeatureFlags.isCleanHotBarActive() then return false end
    if CSR_PlayerPrefs then
        local override = CSR_PlayerPrefs.getOverride("AimingHealthCursor")
        if override ~= nil then return override end
    end
    return sandbox().EnableAimingHealthCursor ~= false
end

function CSR_FeatureFlags.isAimingDensityCursorEnabled()
    if CSR_FeatureFlags.isCleanHotBarActive() then return false end
    if CSR_PlayerPrefs then
        local override = CSR_PlayerPrefs.getOverride("AimingDensityCursor")
        if override ~= nil then return override end
    end
    return sandbox().EnableAimingDensityCursor == true
end

function CSR_FeatureFlags.isGearSlingEnabled()
    return sandbox().EnableGearSling ~= false
end

function CSR_FeatureFlags.isColoredTogglesEnabled()
    return sandbox().EnableColoredToggles ~= false
end

function CSR_FeatureFlags.isSurvivorLedgerEnabled()
    return sandbox().EnableSurvivorLedger ~= false
end

return CSR_FeatureFlags
