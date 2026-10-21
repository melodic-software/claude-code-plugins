#Requires -Version 7.4
<#
.SYNOPSIS
Check: whether anything backs this machine up. Emits a CheckResult JSON on stdout.

See reference/windows/check-catalog.md#27-backup-status for rubric.

.DESCRIPTION
Reads every backup signal through Get-BackupSignal and reports one source row
each; the source list and the rubric are in the catalog section above.
Read-only: the check never starts or configures a backup.
#>
[CmdletBinding()]
param(
    [switch]$Human
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')
. (Join-Path $PSScriptRoot '..\lib\Get-BackupSignal.ps1')
. (Join-Path $PSScriptRoot '..\lib\Test-IsElevated.ps1')
. (Join-Path $PSScriptRoot '..\lib\Get-WorstSeverity.ps1')

$id = 'backup-status'
$category = 'reliability'
$src = $BackupSignalSource
$commands = @(
    "Get-WinEvent -FilterHashtable @{ LogName = '$($src.BackupChannel)'; Id = $($src.BackupEventIds -join ', ') }"
    "wbadmin $($src.WbadminArguments -join ' ') (elevated only)"
    "Get-CimInstance -Namespace $($src.RestoreNamespace) -ClassName $($src.RestoreClass) (elevated only)"
    "Get-ChildItem `"`$env:LOCALAPPDATA\$($src.FileHistoryFolder)`" -Filter '$($src.FileHistoryFilter)'"
    "Get-WinEvent -ListLog '$($src.WindowsBackupLog)'"
    "Get-Item $(($src.OneDrivePolicyKeys | ForEach-Object { "'$_'" }) -join ', ')"
)

$FailureSummary = 'Backup-status check failed.'
$PassThru = $false
$CheckBody = {
    $elevated = [bool](Test-IsElevated)
    $sources = @(Get-BackupSignal -Elevated $elevated)

    $present = [System.Collections.Generic.List[string]]::new()
    $needsAdmin = [System.Collections.Generic.List[string]]::new()
    $levels = foreach ($s in $sources) {
        switch ($s.State) {
            'present' { $present.Add($s.Source); 'OK' }
            'absent' { 'OK' }
            'unknown' { 'OK' }
            'needs-admin' { $needsAdmin.Add($s.Source); 'UNKNOWN' }
            default { 'UNKNOWN' }
        }
    }
    $severity = Get-WorstSeverity -Levels @($levels)
    if ($severity -eq 'OK' -and $present.Count -eq 0) { $severity = 'WARN' }

    $lead = $present.Count -gt 0 ? "Backup sources present: $($present -join ', ')" :
        "No backup source present among $($sources.Count) checked"
    $adminNote = $needsAdmin.Count -gt 0 ? "; $($needsAdmin -join ', ') readable elevated only" : ''
    $byName = @{}
    foreach ($s in $sources) { $byName[$s.Source] = $s }
    $systemImage = $byName[$BackupSourceId.SystemImage]
    $deprecation = 'System Image Backup has been deprecated since Windows 10 version 1709.'
    # The note rides on the summary only when a system image is what protects the machine.
    $summary = "$lead$adminNote." + ($systemImage -and $systemImage.State -eq 'present' ? " $deprecation" : '')
    $detail = @{
        sources           = @($sources | ForEach-Object {
                [ordered]@{
                    source            = $_.Source
                    state             = $_.State
                    last_success      = $_.LastSuccess
                    last_result_event = $_.LastResultEvent
                    signal            = $_.Signal
                    basis             = $_.Basis
                }
            })
        protected_count   = $present.Count
        needs_admin_count = $needsAdmin.Count
        restore_points    = $elevated ? $byName[$BackupSourceId.RestorePoints].Count : $null
        system_image      = $elevated ? $systemImage.Count : $null
        deprecation_note  = $deprecation
        items_count       = 0
        muted_count       = 0
    }

    $result = New-HealthResult -Id $id -Category $category -Os 'windows' -Severity $severity -Summary $summary `
        -Commands $commands -Detail $detail -NeedsAdmin $false -RanSuccessfully $true `
        -AdminFields ($elevated ? @() : @('restore_points', 'system_image'))
}
. (Join-Path $PSScriptRoot '..\lib\Invoke-HealthCheckEnvelope.ps1')
