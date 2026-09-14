param([Parameter(Mandatory=$true)][string]$GameDir, [switch]$Kahlua)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$claim = "$PSScriptRoot/media/lua/client/UI/AVCSUserManagerMain.lua"
$sizing = "$PSScriptRoot/media/lua/client/UI/AVCSVehicleSizing.lua"
$helper = "$PSScriptRoot/media/lua/client/UI/AVCSWindowSizing.lua"
Push-Location $repo
try {
    foreach ($file in Get-ChildItem -LiteralPath "$PSScriptRoot/media" -Filter '*.lua' -File -Recurse) {
        & luac -p $file.FullName
        if ($LASTEXITCODE -ne 0) { throw "Lua syntax failed: $($file.Name)" }
    }
    & lua "$PSScriptRoot/tests/Management.lua"
    if ($LASTEXITCODE -ne 0) { throw 'Management regression failed' }
    & lua "$PSScriptRoot/tests/VehicleSync.lua"
    if ($LASTEXITCODE -ne 0) { throw 'Vehicle sync regression failed' }
    & lua "$PSScriptRoot/tests/ClaimCache.lua"
    if ($LASTEXITCODE -ne 0) { throw 'Claim cache regression failed' }
    & lua "$PSScriptRoot/tests/PermissionAcknowledgment.lua"
    if ($LASTEXITCODE -ne 0) { throw 'Permission acknowledgment regression failed' }
    & lua "$PSScriptRoot/tests/VehicleIdentity.lua"
    if ($LASTEXITCODE -ne 0) { throw 'Vehicle identity regression failed' }
    & lua "$PSScriptRoot/tests/MapCache.lua"
    if ($LASTEXITCODE -ne 0) { throw 'Map cache regression failed' }
    & lua "$PSScriptRoot/tests/ClaimLayout.lua" $claim $sizing
    if ($LASTEXITCODE -ne 0) { throw 'Claim layout regression failed' }
    & lua "$PSScriptRoot/tests/ClaimResize.lua" $GameDir $claim $sizing $helper
    if ($LASTEXITCODE -ne 0) { throw 'Native resize regression failed' }
    if ($Kahlua) {
        $java = if ($env:JAVA_HOME) { "$env:JAVA_HOME/bin/java.exe" } else { 'java' }
        Set-Location -LiteralPath $GameDir
        & $java -cp "$GameDir/projectzomboid.jar" "$PSScriptRoot/tests/RunKahlua.java" "$PSScriptRoot/tests/ClaimResize.lua" $GameDir $claim $sizing $helper
        if ($LASTEXITCODE -ne 0) { throw 'Game Kahlua resize regression failed' }
        & $java -cp "$GameDir/projectzomboid.jar" "$PSScriptRoot/tests/RunKahlua.java" "$PSScriptRoot/tests/VehicleSync.lua" "$PSScriptRoot/media/lua/client/AVCSVehicleSync.lua"
        if ($LASTEXITCODE -ne 0) { throw 'Game Kahlua sync regression failed' }
    }
} finally { Pop-Location }
