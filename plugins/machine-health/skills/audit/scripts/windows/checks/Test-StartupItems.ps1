#Requires -Version 7.4
<#
.SYNOPSIS
Check: everything that starts at logon. Emits a CheckResult JSON on stdout.

See reference/windows/check-catalog.md#21-startup-items for the rubric.
#>
[CmdletBinding()]
param(
    [switch]$Human,
    [string[]]$MutedKeys = @()
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')
. (Join-Path $PSScriptRoot '..\lib\New-FindingItem.ps1')
. (Join-Path $PSScriptRoot '..\lib\Read-StartupApproved.ps1')
. (Join-Path $PSScriptRoot '..\lib\Get-RunKeyEntry.ps1')
. (Join-Path $PSScriptRoot '..\lib\Get-LogonTaskInventory.ps1')

$id = 'startup-items'
$category = 'services'
$commands = @(
    'Get-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Run, ...\RunOnce (HKCU, HKLM, HKLM WOW6432Node)'
    'Get-ChildItem ([Environment]::GetFolderPath(''Startup'')), ([Environment]::GetFolderPath(''CommonStartup''))'
    'Get-ItemProperty ...\Explorer\StartupApproved\Run, Run32, StartupFolder (HKCU, HKLM)'
    'Get-ScheduledTask | Where-Object { $_.Triggers.CimClass.CimClassName -eq ''MSFT_TaskLogonTrigger'' }'
)

# Each startup location; RunOnce entries have no StartupApproved state.
$locations = @(
    @{ Scope = 'hkcu'; Key = 'Run'; Approved = $true }
    @{ Scope = 'hkcu'; Key = 'RunOnce'; Approved = $false }
    @{ Scope = 'hklm'; Key = 'Run'; Approved = $true }
    @{ Scope = 'hklm'; Key = 'RunOnce'; Approved = $false }
    @{ Scope = 'hklm-wow64'; Key = 'Run'; Approved = $true }
    @{ Scope = 'hklm-wow64'; Key = 'RunOnce'; Approved = $false }
    @{ Scope = 'user-folder'; Approved = $true }
    @{ Scope = 'common-folder'; Approved = $true }
)

$FailureSummary = 'Startup items check failed.'
$PassThru = $false
$CheckBody = {
    $items = [System.Collections.Generic.List[pscustomobject]]::new()
    $readStates = [System.Collections.Generic.List[string]]::new()
    $unreadable = [System.Collections.Generic.List[string]]::new()

    foreach ($location in $locations) {
        $source = [ordered]@{ Scope = $location.Scope }
        if ($location.ContainsKey('Key')) { $source['Key'] = $location.Key }
        $read = Get-RunKeyEntry @source
        $readStates.Add($read.ReadState)
        if (-not (Test-ReadStateUsable $read.ReadState)) { $unreadable.Add("$($source.Values -join ' '): $($read.ReadState)") }
        if (@($read.Entries).Count -eq 0) { continue }

        $approved = @{}
        if ($location.Approved) {
            $approvedRead = Read-StartupApproved -Scope $location.Scope
            $readStates.Add($approvedRead.ReadState)
            if (-not (Test-ReadStateUsable $approvedRead.ReadState)) {
                $unreadable.Add("$($location.Scope) StartupApproved: $($approvedRead.ReadState)")
            }
            $approved = $approvedRead.Entries
        }

        foreach ($entry in $read.Entries) {
            $state = $approved[$entry.Name]
            $approvedState = $state ? $state.State : 'none'
            $items.Add((New-FindingItem -Kind 'startup' -Identity @($entry.Scope, $entry.Name) -MutedKeys $MutedKeys `
                        -Severity ($approvedState -eq 'unknown' ? 'UNKNOWN' : 'INFO') -Title $entry.Name -Fields @{
                        kind              = $entry.Kind
                        scope             = $entry.Scope
                        name              = $entry.Name
                        command           = $entry.Command
                        approved_state    = $approvedState
                        approved_raw_byte = $state ? $state.RawByte : $null
                        disabled_at       = ($state -and $state.DisabledAt) ? $state.DisabledAt.ToString('o') : $null
                        task_path         = $null
                    }))
        }
    }

    $tasks = Get-LogonTaskInventory
    $readStates.Add($tasks.ReadState)
    if (-not (Test-ReadStateUsable $tasks.ReadState)) { $unreadable.Add("logon tasks: $($tasks.ReadState)") }
    foreach ($task in $tasks.Tasks) {
        $items.Add((New-FindingItem -Kind 'task' -Identity @($task.TaskPath, $task.TaskName) -MutedKeys $MutedKeys `
                    -Severity 'INFO' -Title "$($task.TaskPath)$($task.TaskName)" -Fields @{
                    kind              = 'logon-task'
                    scope             = 'task'
                    name              = $task.TaskName
                    command           = $task.Command
                    approved_state    = $task.Enabled ? 'enabled' : 'disabled'
                    approved_raw_byte = $null
                    disabled_at       = $null
                    task_path         = $task.TaskPath
                }))
    }

    # Entries with no StartupApproved value start like enabled ones.
    $enabledCount = @($items | Where-Object { $_.approved_state -in 'enabled', 'none' }).Count
    $disabledCount = @($items | Where-Object { $_.approved_state -eq 'disabled' }).Count
    $unknownCount = @($items | Where-Object { $_.approved_state -eq 'unknown' }).Count
    $taskCount = @($tasks.Tasks).Count
    $mutedCount = @($items | Where-Object { $_.muted }).Count

    $severity = Get-UnmutedSeverity -Items $items.ToArray() -ReadState $readStates.ToArray()
    $summary = ("$($items.Count) startup item(s): $enabledCount start at logon, $disabledCount disabled, " +
        "$unknownCount in an unrecognized state; $taskCount logon task(s).")
    if (-not $tasks.Complete) { $summary += ' Logon tasks are partial without elevation.' }
    if ($unreadable.Count -gt 0) { $summary += " Unreadable: $($unreadable -join ', ')." }

    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity $severity -Summary $summary -Commands $commands -Detail @{
        items               = $items.ToArray()
        items_count         = $items.Count
        muted_count         = $mutedCount
        enabled_count       = $enabledCount
        disabled_count      = $disabledCount
        unknown_state_count = $unknownCount
        logon_task_count    = $taskCount
        tasks_complete      = [bool]$tasks.Complete
        unreadable_sources  = $unreadable.ToArray()
    } `
        -AdminFields ($tasks.Complete ? @() : @('tasks_complete')) `
        -NeedsAdmin $false -RanSuccessfully $true
}
. (Join-Path $PSScriptRoot '..\lib\Invoke-HealthCheckEnvelope.ps1')
