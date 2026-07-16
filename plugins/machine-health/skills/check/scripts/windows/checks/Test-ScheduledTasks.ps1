#Requires -Version 7.4
<#
.SYNOPSIS
Check: scheduled tasks with failing LastTaskResult. Emits a CheckResult JSON on stdout.
#>
[CmdletBinding()]
param([switch]$Human)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')

function Test-IsNeverRunScheduledTask {
    # 267011 = SCHED_S_TASK_HAS_NOT_RUN; FILETIME-zero shows as pre-2000 dates.
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter()] [AllowNull()] $TaskInfo)

    if ($null -eq $TaskInfo) { return $true }

    if ($TaskInfo.PSObject.Properties['LastTaskResult'] -and
        $TaskInfo.LastTaskResult -eq 267011) {
        return $true
    }

    if (-not $TaskInfo.PSObject.Properties['LastRunTime']) { return $true }
    $lastRun = $TaskInfo.LastRunTime
    if ($null -eq $lastRun) { return $true }
    if ($lastRun -lt [datetime]'2000-01-01') { return $true }

    return $false
}

# Dot-source guard: lets Pester test the helper in isolation; & invocation skips it.
if ($MyInvocation.InvocationName -eq '.') { return }

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$id = 'scheduled-tasks'
$category = 'reliability'
$commands = @(
    'Get-ScheduledTask | Get-ScheduledTaskInfo | Where-Object { $_.LastTaskResult -ne 0 }'
)

try {
    # Filter out \Microsoft\* tasks -- too noisy, mostly OS housekeeping.
    # Never-run detection (LastTaskResult=267011 or LastRunTime sentinel) is
    # delegated to Test-IsNeverRunScheduledTask; see helper docs above for
    # the full SCHED_S_* code mapping. 267014 (SCHED_S_TASK_TERMINATED) is
    # NOT filtered -- termination is a real event worth surfacing.
    $tasks = @(Get-ScheduledTask -ErrorAction Stop |
            Where-Object { $_.TaskPath -notlike '\Microsoft\*' -and $_.State -eq 'Ready' })

    $failed = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($t in $tasks) {
        $info = $null
        try {
            $info = $t | Get-ScheduledTaskInfo -ErrorAction Stop
        } catch {
            Write-Verbose "Test-ScheduledTasks: info query failed for $($t.TaskName). $($_.Exception.Message)"
            continue
        }
        if ($null -eq $info) { continue }
        if ($info.LastTaskResult -eq 0) { continue }
        if (Test-IsNeverRunScheduledTask -TaskInfo $info) { continue }

        $failed.Add([pscustomobject]@{
                task_path     = $t.TaskPath
                task_name     = $t.TaskName
                last_result   = [long]$info.LastTaskResult
                last_run_time = $info.LastRunTime ? $info.LastRunTime.ToString('o') : $null
                next_run_time = $info.NextRunTime ? $info.NextRunTime.ToString('o') : $null
            })
    }

    $severity = 'OK'
    $summary = 'No failing scheduled tasks.'
    if ($failed.Count -gt 0) {
        $severity = 'WARN'
        $summary = "$($failed.Count) scheduled task(s) with non-zero LastTaskResult."
    }

    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity $severity -Summary $summary -Commands $commands `
        -Detail @{
        failed_count = $failed.Count
        failed_tasks = @($failed | Select-Object -First 20)
    } `
        -NeedsAdmin $false -RanSuccessfully $true `
        -DurationMs ([int]$sw.ElapsedMilliseconds)
} catch {
    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity 'UNKNOWN' -Summary 'Scheduled task check failed.' -Commands $commands `
        -RanSuccessfully $false -ErrorMessage $_.Exception.Message `
        -DurationMs ([int]$sw.ElapsedMilliseconds)
}

$sw.Stop()
$result.duration_ms = [int]$sw.ElapsedMilliseconds
$result | Write-HealthResult -Human:$Human
