#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PublishDirectory,

    [int]$TimeoutSeconds = 30,

    [int]$OverallTimeoutSeconds = 300
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'PublishedApplicationSmoke.psm1') -Force
$publishDirectoryPath = (Resolve-Path -LiteralPath $PublishDirectory).Path
$launcherExecutablePath = Join-Path $publishDirectoryPath 'SIDEY.exe'
$hostExecutablePath = Join-Path $publishDirectoryPath 'Runtime\SIDEY.Host.exe'
if (Test-Path -LiteralPath (Join-Path $publishDirectoryPath 'Runtime/Assets')) {
    throw 'Startup smoke must use external Assets without a private Runtime/Assets copy.'
}
if (-not (Test-Path -LiteralPath $launcherExecutablePath -PathType Leaf)) {
    throw "SIDEY.exe was not found in the publish directory: $publishDirectoryPath"
}
if (-not (Test-Path -LiteralPath $hostExecutablePath -PathType Leaf)) {
    throw "Runtime/SIDEY.Host.exe was not found in the publish directory: $publishDirectoryPath"
}
$timeoutState = New-SideyStartupSmokeTimeoutState `
    -StartedAt ([DateTimeOffset]::UtcNow) `
    -InactivityTimeoutSeconds $TimeoutSeconds `
    -OverallTimeoutSeconds $OverallTimeoutSeconds

$smokeDataRoot = Join-Path ([IO.Path]::GetTempPath()) "SIDEY-Smoke-$([Guid]::NewGuid().ToString('N'))"
$logDirectory = Join-Path $smokeDataRoot 'SIDEY/Logs'
$startedAt = [DateTime]::UtcNow.AddSeconds(-1)
$smokeEnvironmentVariable = 'SIDEY_STARTUP_SMOKE'
$smokeDataEnvironmentVariable = 'SIDEY_STARTUP_SMOKE_DATA_ROOT'
$previousSmokeValue = [Environment]::GetEnvironmentVariable($smokeEnvironmentVariable, 'Process')
$previousSmokeDataValue = [Environment]::GetEnvironmentVariable($smokeDataEnvironmentVariable, 'Process')
$process = $null
$launcherProcess = $null
try {
    [Environment]::SetEnvironmentVariable($smokeEnvironmentVariable, '1', 'Process')
    [Environment]::SetEnvironmentVariable($smokeDataEnvironmentVariable, $smokeDataRoot, 'Process')
    $launcherProcess = Start-Process `
        -FilePath $launcherExecutablePath `
        -WorkingDirectory $publishDirectoryPath `
        -WindowStyle Hidden `
        -PassThru
    if (-not $launcherProcess.WaitForExit(5000) -or $launcherProcess.ExitCode -ne 0) {
        throw "SIDEY launcher did not forward startup successfully."
    }
    $observation = Resolve-SideyStartupSmokeObservation `
        -State $timeoutState `
        -ObservedAt ([DateTimeOffset]::UtcNow) `
        -HasProgress
    $timeoutState = $observation.State
    $timeoutReason = $observation.TimeoutReason
    $lastStageObservation = $null
    $ready = $false
    while ($null -eq $timeoutReason) {
        $observation = Resolve-SideyStartupSmokeObservation `
            -State $timeoutState `
            -ObservedAt ([DateTimeOffset]::UtcNow)
        $timeoutReason = $observation.TimeoutReason
        if ($null -ne $timeoutReason) {
            break
        }
        if ($null -eq $process) {
            $process = Get-Process -Name 'SIDEY.Host' -ErrorAction SilentlyContinue |
                Where-Object {
                    [string]::Equals(
                        $_.Path,
                        $hostExecutablePath,
                        [StringComparison]::OrdinalIgnoreCase)
                } |
                Select-Object -First 1
            if ($null -eq $process) {
                Start-Sleep -Milliseconds 250
                continue
            }
            $observation = Resolve-SideyStartupSmokeObservation `
                -State $timeoutState `
                -ObservedAt ([DateTimeOffset]::UtcNow) `
                -HasProgress
            $timeoutState = $observation.State
            $timeoutReason = $observation.TimeoutReason
            if ($null -ne $timeoutReason) {
                break
            }
        }
        $process.Refresh()
        if ($process.HasExited) {
            $recentLogs = @(Get-ChildItem -LiteralPath $logDirectory -Filter 'SIDEY.*.log' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTimeUtc -ge $startedAt } |
                Sort-Object LastWriteTimeUtc)
            $tail = if ($recentLogs.Count -gt 0) {
                ($recentLogs | ForEach-Object { Get-Content -LiteralPath $_.FullName -Tail 40 }) -join [Environment]::NewLine
            }
            else {
                '(SIDEY session log not found)'
            }
            throw "SIDEY.exe exited during startup (exit=$($process.ExitCode)).`n$tail"
        }

        $recentLogs = @(Get-ChildItem -LiteralPath $logDirectory -Filter 'SIDEY.*.log' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTimeUtc -ge $startedAt } |
            Sort-Object LastWriteTimeUtc)
        if ($recentLogs.Count -gt 0) {
            $log = ($recentLogs | ForEach-Object {
                Get-Content -LiteralPath $_.FullName -Raw
            }) -join [Environment]::NewLine
            $pidPattern = [regex]::Escape("pid=$($process.Id)")
            $stageObservation = (($log -split '\r?\n') | Where-Object {
                $_ -match "$pidPattern .*stage="
            }) -join [Environment]::NewLine
            $hasProgress = $stageObservation -and $stageObservation -cne $lastStageObservation
            if ($hasProgress) {
                $lastStageObservation = $stageObservation
            }
            if ($log -match "$pidPattern fatal ") {
                throw "SIDEY startup failed.`n$log"
            }
            $hasCompleted = $log -match "$pidPattern startup-complete"
            $observation = Resolve-SideyStartupSmokeObservation `
                -State $timeoutState `
                -ObservedAt ([DateTimeOffset]::UtcNow) `
                -HasProgress:$hasProgress `
                -HasCompleted:$hasCompleted
            $timeoutState = $observation.State
            $timeoutReason = $observation.TimeoutReason
            if ($null -ne $timeoutReason) {
                break
            }
            if ($observation.Ready) {
                $ready = $observation.Ready
                break
            }
        }
        Start-Sleep -Milliseconds 250
    }

    if (-not $ready) {
        $recentLogs = @(Get-ChildItem -LiteralPath $logDirectory -Filter 'SIDEY.*.log' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTimeUtc -ge $startedAt } |
            Sort-Object LastWriteTimeUtc)
        $tail = if ($recentLogs.Count -gt 0) {
            ($recentLogs | ForEach-Object { Get-Content -LiteralPath $_.FullName -Tail 40 }) -join [Environment]::NewLine
        }
        else {
            '(SIDEY session log not found)'
        }
        $timeout = if ($timeoutReason -ceq 'Overall') {
            "the $OverallTimeoutSeconds-second overall limit"
        }
        else {
            "$TimeoutSeconds seconds without progress"
        }
        throw "SIDEY.exe did not complete startup before $timeout.`n$tail"
    }
    Write-Host "StartupSmokeTest=true"
    Write-Host "ProcessId=$($process.Id)"
}
finally {
    [Environment]::SetEnvironmentVariable(
        $smokeEnvironmentVariable,
        $previousSmokeValue,
        'Process')
    [Environment]::SetEnvironmentVariable(
        $smokeDataEnvironmentVariable,
        $previousSmokeDataValue,
        'Process')
    if ($null -ne $process) {
        $process.Refresh()
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force
            $process.WaitForExit()
        }
        $process.Dispose()
    }
    if ($null -ne $launcherProcess) {
        $launcherProcess.Dispose()
    }
}
