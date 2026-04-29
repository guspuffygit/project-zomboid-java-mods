local function enableAdvancedSoundOptions()
    if not CSR_FeatureFlags.isAdvancedSoundOptionsEnabled() then return end
    SystemDisabler.setEnableAdvancedSoundOptions(true)
end

Events.OnGameBoot.Add(enableAdvancedSoundOptions)
