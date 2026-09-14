param([Parameter(Mandatory=$true)][string]$GameDir, [switch]$Kahlua)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
Push-Location -LiteralPath $repo
try {
    foreach ($file in Get-ChildItem -LiteralPath "$PSScriptRoot/media" -Filter '*.lua' -Recurse -File) {
        & luac -p $file.FullName
        if ($LASTEXITCODE -ne 0) { throw "Lua syntax failed: $($file.Name)" }
    }
    foreach ($name in @('Recorder','Controls')) {
        $test = "$PSScriptRoot/tests/$name.lua"
        $source = "$PSScriptRoot/media/lua/client/AdminDiagnostics/$name.lua"
        & lua $test $source
        if ($LASTEXITCODE -ne 0) { throw "Lua regression failed: $name" }
        if ($Kahlua) {
            $java = if ($env:JAVA_HOME) { "$env:JAVA_HOME/bin/java.exe" } else { 'java' }
            Push-Location -LiteralPath $GameDir
            try { & $java -cp "$GameDir/projectzomboid.jar" "$PSScriptRoot/tests/RunKahlua.java" $test $source }
            finally { Pop-Location }
            if ($LASTEXITCODE -ne 0) { throw "Game Kahlua regression failed: $name" }
        }
    }
} finally { Pop-Location }
