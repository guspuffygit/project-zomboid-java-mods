param([Parameter(Mandatory=$true)][string]$GameDir)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot
$lua = (Get-Command lua -ErrorAction Stop).Source
$luac = (Get-Command luac -ErrorAction Stop).Source
if (!(Test-Path -LiteralPath "$GameDir/media/lua/client/ISUI/AdminPanel/ISAdminPanelUI.lua")) {
    throw 'GameDir must contain the installed B42 Admin Panel Lua source.'
}
Push-Location $repoRoot
try {
    foreach ($file in Get-ChildItem -LiteralPath "$PSScriptRoot/media" -Filter '*.lua' -Recurse -File) {
        & $luac -p $file.FullName
        if ($LASTEXITCODE -ne 0) { throw "Lua syntax failed: $($file.Name)" }
    }
    foreach ($test in @('ControlCenter','PlayerTools','MembershipServer','VisibleStats','InviteSearch','OfflineMembership','ObserveLifecycle','UserPanel')) {
        & $lua "universal-admin-core/tests/$test.lua" $GameDir
        if ($LASTEXITCODE -ne 0) { throw "Lua regression failed: $test" }
    }
} finally { Pop-Location }
