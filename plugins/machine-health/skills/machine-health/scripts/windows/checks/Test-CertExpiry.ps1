#Requires -Version 7.4
<#
.SYNOPSIS
Check: user certificate expiry (CurrentUser\My). Emits a CheckResult JSON on stdout.
#>
[CmdletBinding()]
param([switch]$Human)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$id = 'cert-expiry'
$category = 'security'
$commands = @(
    'Get-ChildItem Cert:\CurrentUser\My | Select-Object Subject, Issuer, NotAfter'
)

try {
    $now = Get-Date
    $certs = @(Get-ChildItem -Path Cert:\CurrentUser\My -ErrorAction SilentlyContinue |
            Where-Object {
                $subj = "$($_.Subject)"
                # Filter out obvious dev/self-signed junk: CN=localhost, "DO_NOT_TRUST" test certs, etc.
                $subj -notmatch 'DO_NOT_TRUST' -and $subj -notmatch 'CN=localhost'
            } |
            ForEach-Object {
                $daysLeft = $_.NotAfter ? [int]([math]::Floor(($_.NotAfter - $now).TotalDays)) : 9999
                [pscustomobject]@{
                    subject    = $_.Subject
                    issuer     = $_.Issuer
                    not_after  = $_.NotAfter ? $_.NotAfter.ToString('o') : $null
                    days_left  = $daysLeft
                    thumbprint = $_.Thumbprint
                }
            })

    # Single-pass classification: each cert lands in exactly one bucket,
    # avoiding repeated Where-Object passes over the same collection.
    $crit = [System.Collections.Generic.List[pscustomobject]]::new()
    $warn = [System.Collections.Generic.List[pscustomobject]]::new()
    $info = [System.Collections.Generic.List[pscustomobject]]::new()
    $expired = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($c in $certs) {
        if ($c.days_left -lt 0) { $expired.Add($c) }
        elseif ($c.days_left -le 7) { $crit.Add($c) }
        elseif ($c.days_left -le 30) { $warn.Add($c) }
        elseif ($c.days_left -le 90) { $info.Add($c) }
    }

    $severity = 'OK'
    $summary = "$($certs.Count) cert(s); none expiring in 90d."
    if ($crit.Count -gt 0 -or $expired.Count -gt 0) {
        $severity = 'CRIT'
        $summary = "$($crit.Count) cert(s) expiring in <=7d, $($expired.Count) already expired."
    } elseif ($warn.Count -gt 0) {
        $severity = 'WARN'
        $summary = "$($warn.Count) cert(s) expiring in 8-30d."
    } elseif ($info.Count -gt 0) {
        $severity = 'INFO'
        $summary = "$($info.Count) cert(s) expiring in 31-90d."
    }

    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity $severity -Summary $summary -Commands $commands `
        -Detail @{
        total_count   = $certs.Count
        crit_count    = $crit.Count
        warn_count    = $warn.Count
        info_count    = $info.Count
        expired_count = $expired.Count
        expiring_soon = @($crit + $warn + $expired | Select-Object -First 20)
    } `
        -NeedsAdmin $false -RanSuccessfully $true `
        -DurationMs ([int]$sw.ElapsedMilliseconds)
} catch {
    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity 'UNKNOWN' -Summary 'Cert expiry check failed.' -Commands $commands `
        -RanSuccessfully $false -ErrorMessage $_.Exception.Message `
        -DurationMs ([int]$sw.ElapsedMilliseconds)
}

$sw.Stop()
$result.duration_ms = [int]$sw.ElapsedMilliseconds
$result | Write-HealthResult -Human:$Human
