param([string]$VendorFixtures)
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot)
try {
    foreach ($file in Get-ChildItem "$PSScriptRoot/media" -Recurse -File -Filter '*.lua') {
        & luac -p $file.FullName
        if ($LASTEXITCODE -ne 0) { throw "Lua syntax failed: $($file.Name)" }
    }
    & lua "$PSScriptRoot/tests/Performance.lua"
    if ($LASTEXITCODE -ne 0) { throw 'Compatibility regression failed' }
    if ($VendorFixtures) {
        foreach ($name in @('VendorMemory','SafehouseSync')) {
            & lua "$PSScriptRoot/tests/$name.lua" $VendorFixtures
            if ($LASTEXITCODE -ne 0) { throw "Vendor regression failed: $name" }
        }
    } else {
        Write-Output 'Vendor source regressions skipped: supply -VendorFixtures after applying the source patches.'
    }
} finally { Pop-Location }
