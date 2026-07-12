#Requires -Version 7.4
<#
.SYNOPSIS
Check: TPM ownership + BitLocker volume status. Emits a CheckResult JSON on stdout.
Admin-gated; non-elevated runs return UNKNOWN with needs_admin:true.
#>
[CmdletBinding()]
param([switch]$Human)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')
. (Join-Path $PSScriptRoot '..\lib\Test-IsElevated.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$id = 'tpm-bitlocker'
$category = 'security'
$commands = @(
    'Get-Tpm'
    'Get-BitLockerVolume'
)

try {
    $elevated = Test-IsElevated
    if (-not $elevated) {
        $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
            -Severity 'UNKNOWN' `
            -Summary 'TPM/BitLocker status requires admin (re-run elevated).' `
            -Detail @{ elevated = $false } `
            -Commands $commands `
            -NeedsAdmin $true -RanSuccessfully $false `
            -ErrorMessage 'needs_admin' `
            -DurationMs ([int]$sw.ElapsedMilliseconds) `
            -AdminFields @('tpm_owned', 'tpm_enabled', 'bitlocker_protection_status')
    } else {
        $tpm = $null
        try { $tpm = Get-Tpm -ErrorAction Stop } catch {
            Write-Verbose "Test-TpmBitLocker: Get-Tpm failed. $($_.Exception.Message)"
        }

        $volumes = @()
        try {
            $volumes = @(Get-BitLockerVolume -ErrorAction Stop)
        } catch {
            Write-Verbose "Test-TpmBitLocker: Get-BitLockerVolume failed. $($_.Exception.Message)"
        }

        $systemVol = @($volumes | Where-Object { $_.VolumeType -eq 'OperatingSystem' })
        $systemProtected = @($systemVol | Where-Object { $_.ProtectionStatus -eq 'On' }).Count -gt 0

        $tpmOwned = $tpm ? [bool]$tpm.TpmOwned : $null
        $tpmEnabled = $tpm ? [bool]$tpm.TpmEnabled : $null

        $severity = 'OK'
        $summary = 'TPM owned + enabled, BitLocker on system volume.'
        if ($null -eq $tpm) {
            $severity = 'WARN'
            $summary = 'TPM information unavailable.'
        } elseif (-not $tpmOwned -or -not $tpmEnabled) {
            $severity = 'WARN'
            $summary = "TPM state concerning (owned=$tpmOwned, enabled=$tpmEnabled)."
        } elseif ($systemVol.Count -eq 0) {
            $severity = 'INFO'
            $summary = 'TPM OK; no BitLocker system volume found.'
        } elseif (-not $systemProtected) {
            $severity = 'WARN'
            $summary = 'TPM OK, but BitLocker not protecting system volume.'
        }

        $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
            -Severity $severity -Summary $summary -Commands $commands `
            -Detail @{
            tpm_present                 = ($null -ne $tpm)
            tpm_owned                   = $tpmOwned
            tpm_enabled                 = $tpmEnabled
            bitlocker_protection_status = $systemVol.Count -gt 0 ? "$($systemVol[0].ProtectionStatus)" : $null
            bitlocker_volumes           = @($volumes | ForEach-Object {
                    [pscustomobject]@{
                        mount_point       = $_.MountPoint
                        volume_type       = "$($_.VolumeType)"
                        protection_status = "$($_.ProtectionStatus)"
                        encryption_method = "$($_.EncryptionMethod)"
                        volume_status     = "$($_.VolumeStatus)"
                    }
                })
        } `
            -NeedsAdmin $true -RanSuccessfully $true `
            -DurationMs ([int]$sw.ElapsedMilliseconds)
    }
} catch {
    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity 'UNKNOWN' -Summary 'TPM/BitLocker check failed.' -Commands $commands `
        -RanSuccessfully $false -ErrorMessage $_.Exception.Message `
        -DurationMs ([int]$sw.ElapsedMilliseconds)
}

$sw.Stop()
$result.duration_ms = [int]$sw.ElapsedMilliseconds
$result | Write-HealthResult -Human:$Human
