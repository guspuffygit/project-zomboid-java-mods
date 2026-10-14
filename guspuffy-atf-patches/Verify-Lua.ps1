param(
    [string]$VendorFixtures,
    [string]$LifestyleLuaSource,
    [string]$PZInventoryPane,
    [string]$LivestockEggHook,
    [string]$TalisLuaSource
)
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot)
try {
    foreach ($file in Get-ChildItem "$PSScriptRoot/media" -Recurse -File -Filter '*.lua') {
        & luac -p $file.FullName
        if ($LASTEXITCODE -ne 0) { throw "Lua syntax failed: $($file.Name)" }
    }
    & lua "$PSScriptRoot/tests/Performance.lua"
    if ($LASTEXITCODE -ne 0) { throw 'Compatibility regression failed' }
    & lua "$PSScriptRoot/tests/LifestyleSyncPolicy.lua"
    if ($LASTEXITCODE -ne 0) { throw 'Lifestyle policy regression failed' }
    & lua "$PSScriptRoot/tests/LifestyleLegacyProgress.lua" $PSScriptRoot $LifestyleLuaSource
    if ($LASTEXITCODE -ne 0) { throw 'Lifestyle legacy progress regression failed' }
    if ($VendorFixtures) {
        foreach ($name in @('VendorMemory','SafehouseSync','SafehouseAuthority','LifestyleActions','RadioAuthority')) {
            & lua "$PSScriptRoot/tests/$name.lua" $VendorFixtures
            if ($LASTEXITCODE -ne 0) { throw "Vendor regression failed: $name" }
        }
        & lua "$PSScriptRoot/tests/LifestylePassiveRewards.lua" $VendorFixtures $PSScriptRoot
        if ($LASTEXITCODE -ne 0) { throw 'Lifestyle passive reward regression failed' }
        if ($LifestyleLuaSource) {
            & lua "$PSScriptRoot/tests/LifestyleRewardActions.lua" $VendorFixtures $PSScriptRoot $LifestyleLuaSource
            if ($LASTEXITCODE -ne 0) { throw 'Lifestyle action reward regression failed' }
            & lua "$PSScriptRoot/tests/LifestyleNeuralReading.lua" $VendorFixtures $LifestyleLuaSource
        } else {
            Write-Output 'Action formula checks skipped: supply -LifestyleLuaSource for the unchanged ambition helper.'
            & lua "$PSScriptRoot/tests/LifestyleNeuralReading.lua" $VendorFixtures
        }
        if ($LASTEXITCODE -ne 0) { throw 'Lifestyle Neural Hat reading regression failed' }
        if ($LifestyleLuaSource) {
            & lua "$PSScriptRoot/tests/LifestyleItemSync.lua" $VendorFixtures $LifestyleLuaSource
            if ($LASTEXITCODE -ne 0) { throw 'Lifestyle item synchronization regression failed' }
        } else {
            Write-Output 'Item synchronization test skipped: supply -LifestyleLuaSource for the unchanged LSSync helper.'
        }
        if ($PZInventoryPane -and $LivestockEggHook -and $LifestyleLuaSource) {
            & lua "$PSScriptRoot/tests/LifestyleInventory.lua" $VendorFixtures $PZInventoryPane $LivestockEggHook "$LifestyleLuaSource/client/ISUI/hooks/InvPane.lua"
        } else {
            & lua "$PSScriptRoot/tests/LifestyleInventory.lua" $VendorFixtures
            Write-Output 'Exact inventory-provider checks need -PZInventoryPane, -LivestockEggHook and -LifestyleLuaSource.'
        }
        if ($LASTEXITCODE -ne 0) { throw 'Lifestyle inventory regression failed' }
    } else {
        Write-Output 'Vendor source regressions skipped: supply -VendorFixtures after applying the source patches.'
    }
    if ($TalisLuaSource) {
        & lua "$PSScriptRoot/tests/TalisDebugAuthority.lua" $TalisLuaSource
        if ($LASTEXITCODE -ne 0) { throw 'Talis debug authority regression failed' }
    }
} finally { Pop-Location }
