param(
    [Parameter(Mandatory=$true)][int]$ClientProcessId,
    [string]$ConsolePath,
    [string]$OutputDirectory = "$env:USERPROFILE/Zomboid/AdminDiagnostics",
    [ValidateRange(1,60)][int]$IntervalSeconds = 5,
    [ValidateRange(0,1000000)][int]$MaxSamples = 0
)
$ErrorActionPreference = 'Stop'
# Explicit PID avoids confusing the server or second client with the affected client.
$target = Get-Process -Id $ClientProcessId -ErrorAction Stop
$started = $target.StartTime.ToUniversalTime().ToString('o')
$session = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString()
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$script:part = 1
$script:bytes = 0
$script:buffer = ''
$script:offset = 0L
if ($ConsolePath -and (Test-Path -LiteralPath $ConsolePath -PathType Leaf)) {
    $script:offset = (Get-Item -LiteralPath $ConsolePath).Length
}
$script:lastConsole = [DateTime]::MinValue
$history = [Collections.Generic.Queue[object]]::new()
$lastIncident = [DateTime]::MinValue
$lastCheckpoint = [DateTime]::MinValue
$afterUntil = [DateTime]::MinValue
$samples = 0
$previous = $null
# A single native counter snapshot avoids WMI polling and still works if the game JVM hangs.
if (-not ('AdminDiagnostics.SystemMemory' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace AdminDiagnostics {
    [StructLayout(LayoutKind.Sequential)]
    public struct PerformanceInfo {
        public uint Size;
        public UIntPtr CommitTotal, CommitLimit, CommitPeak, PhysicalTotal, PhysicalAvailable;
        public UIntPtr SystemCache, KernelTotal, KernelPaged, KernelNonpaged, PageSize;
        public uint HandleCount, ProcessCount, ThreadCount;
    }
    public static class SystemMemory {
        [DllImport("psapi.dll", SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetPerformanceInfo(out PerformanceInfo info, uint size);
        public static double[] Read() {
            PerformanceInfo info;
            if (!GetPerformanceInfo(out info, (uint)Marshal.SizeOf(typeof(PerformanceInfo)))) return null;
            double page = info.PageSize.ToUInt64() / 1048576.0;
            return new double[] { info.PhysicalAvailable.ToUInt64()*page, info.CommitTotal.ToUInt64()*page,
                info.CommitLimit.ToUInt64()*page };
        }
    }
}
'@
}
function Write-Record($record) {
    $record.session = $session
    $line = ($record | ConvertTo-Json -Compress -Depth 5) + "`n"
    if ($script:bytes + [Text.Encoding]::UTF8.GetByteCount($line) -gt 2097152) {
        $script:part = $script:part % 4 + 1
        $script:bytes = 0
    }
    $path = Join-Path $OutputDirectory "admin-os-$($script:part).jsonl"
    if ($script:bytes -eq 0) { [IO.File]::WriteAllText($path, $line, [Text.UTF8Encoding]::new($false)) }
    else { [IO.File]::AppendAllText($path, $line, [Text.UTF8Encoding]::new($false)) }
    $script:bytes += [Text.Encoding]::UTF8.GetByteCount($line)
}
function Read-RecentWarnings {
    if (!$ConsolePath -or !(Test-Path -LiteralPath $ConsolePath -PathType Leaf)) { return @() }
    $stream = [IO.File]::Open($ConsolePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        if ($stream.Length -lt $script:offset) { $script:offset = 0L; $script:buffer = '' }
        # Never read more than 64 KiB in a sample, even during a native error storm.
        if ($stream.Length - $script:offset -gt 65536) {
            $script:offset = $stream.Length - 65536
            $script:buffer = ''
        }
        $null = $stream.Seek($script:offset, [IO.SeekOrigin]::Begin)
        $buffer = New-Object byte[] 65536
        $read = $stream.Read($buffer, 0, $buffer.Length)
        $script:offset = $stream.Position
        $text = $script:buffer + [Text.Encoding]::UTF8.GetString($buffer, 0, $read)
        $lines = $text -split "`n"
        $script:buffer = $lines[-1]
        if ($script:buffer.Length -gt 2048) { $script:buffer = $script:buffer.Substring($script:buffer.Length - 2048) }
        $warningLines = [Collections.Generic.List[string]]::new()
        for ($i = 0; $i -lt $lines.Length - 1; $i++) {
            $line = $lines[$i]
            if ($line -match '\[ADMIN-DIAG\]') { continue }
            if ($line -notmatch '(?i)timeout|timed out|desync|exception|outofmemory|insufficient memory|chunk.*(fail|error|remov)|vehicle.*(packet|error)|correction|connection.*lost') { continue }
            if ($line -match '(?i)password|authorization|token|secret') { $line = '[sensitive error line omitted]' }
            $line = $line -replace '\b\d{1,3}(?:\.\d{1,3}){3}\b', '[IP]'
            $warningLines.Add($line.Substring(0, [Math]::Min(500, $line.Length)))
            if ($warningLines.Count -ge 20) { break }
        }
        return $warningLines.ToArray()
    } finally { $stream.Dispose() }
}
Write-Record @{kind='session_start'; epochMs=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); processId=$ClientProcessId;
    processName=$target.ProcessName; processStartUtc=$started; intervalSeconds=$IntervalSeconds;
    note='Working set and private bytes are process-wide; heap is recorded separately by the optional in-game helper.'}
Write-Host "Monitoring PID $ClientProcessId. Logs: $OutputDirectory. Press Ctrl+C to stop."
while ($MaxSamples -eq 0 -or $samples -lt $MaxSamples) {
    $time = [DateTime]::UtcNow
    $epoch = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    try {
        $target = Get-Process -Id $ClientProcessId -ErrorAction SilentlyContinue
        $sameProcess = $target -and $target.StartTime.ToUniversalTime().ToString('o') -eq $started
    } catch { $sameProcess = $false }
    if (!$sameProcess) {
        try {
            $finalWarnings = @(Read-RecentWarnings)
            if ($finalWarnings.Count -gt 0) { Write-Record @{kind='native_log_warning'; epochMs=$epoch; lines=$finalWarnings} }
        } catch { Write-Record @{kind='console_read_unavailable'; epochMs=$epoch} }
        foreach ($old in $history) { Write-Record @{kind='before_exit'; sample=$old; epochMs=$epoch} }
        Write-Record @{kind='process_exited'; epochMs=$epoch; note='Exit detected; this alone does not distinguish a crash from a normal close.'}
        break
    }
    $sample = @{epochMs=$epoch; processId=$ClientProcessId; workingSetMiB=[Math]::Round($target.WorkingSet64 / 1MB, 1);
        privateBytesMiB=[Math]::Round($target.PrivateMemorySize64 / 1MB, 1); cpuSeconds=$target.TotalProcessorTime.TotalSeconds;
        threads=$target.Threads.Count; handles=$target.HandleCount}
    try {
        $memory = [AdminDiagnostics.SystemMemory]::Read()
        if (!$memory) { throw 'Native memory counters unavailable' }
        $sample.systemAvailableMiB = [Math]::Round($memory[0], 1)
        $sample.systemCommittedMiB = [Math]::Round($memory[1], 1)
        $sample.systemCommitLimitMiB = [Math]::Round($memory[2], 1)
    } catch { $sample.systemMemoryUnavailable = $true }
    $reasons = [Collections.Generic.List[string]]::new()
    if ($previous -and $sample.privateBytesMiB - $previous.privateBytesMiB -ge 256) { $reasons.Add('private_memory_spike') }
    if ($previous -and $sample.workingSetMiB - $previous.workingSetMiB -ge 256) { $reasons.Add('working_set_spike') }
    if ($sample.ContainsKey('systemAvailableMiB') -and $sample.systemAvailableMiB -lt 1024) { $reasons.Add('low_system_available_memory') }
    if ($sample.systemCommitLimitMiB -gt 0 -and $sample.systemCommittedMiB / $sample.systemCommitLimitMiB -gt 0.95) { $reasons.Add('system_commit_pressure') }
    try { $warnings = @(Read-RecentWarnings) }
    catch { $warnings = @(); $sample.consoleReadUnavailable = $true }
    if ($warnings.Count -gt 0 -and ($time - $script:lastConsole).TotalSeconds -ge 15) {
        Write-Record @{kind='native_log_warning'; epochMs=$epoch; lines=$warnings}
        $script:lastConsole = $time
        $reasons.Add('native_log_warning')
    }
    if ($reasons.Count -gt 0 -and ($time - $lastIncident).TotalSeconds -ge 60) {
        foreach ($old in $history) { Write-Record @{kind='before'; sample=$old; epochMs=$epoch} }
        Write-Record @{kind='incident'; epochMs=$epoch; reasons=$reasons.ToArray(); sample=$sample}
        $lastIncident = $time; $afterUntil = $time.AddSeconds(20)
    } elseif ($time -lt $afterUntil) { Write-Record @{kind='after'; epochMs=$epoch; sample=$sample}
    } elseif (($time - $lastCheckpoint).TotalSeconds -ge 60) {
        Write-Record @{kind='checkpoint'; epochMs=$epoch; sample=$sample}
        $lastCheckpoint = $time
    }
    $history.Enqueue($sample)
    while ($history.Count -gt [Math]::Ceiling(60 / $IntervalSeconds)) { $null = $history.Dequeue() }
    $previous = $sample
    $samples++
    if ($MaxSamples -eq 0 -or $samples -lt $MaxSamples) { Start-Sleep -Seconds $IntervalSeconds }
}
Write-Record @{kind='monitor_stopped'; epochMs=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()}
