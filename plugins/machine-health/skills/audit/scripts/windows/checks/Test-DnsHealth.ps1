#Requires -Version 7.4
<#
.SYNOPSIS
Check: DNS resolution + default-gateway reachability. Emits a CheckResult JSON on stdout.
#>
[CmdletBinding()]
param([switch]$Human)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$id = 'dns-health'
$category = 'network'
$commands = @(
    'Resolve-DnsName microsoft.com -Type A -DnsOnly -QuickTimeout'
    'Get-NetRoute -DestinationPrefix 0.0.0.0/0 | Test-Connection -TargetName {_.NextHop}'
)

try {
    $targets = @('microsoft.com', 'github.com')
    $failures = [System.Collections.Generic.List[string]]::new()

    foreach ($t in $targets) {
        try {
            $results = @(Resolve-DnsName -Name $t -Type A -DnsOnly -QuickTimeout -ErrorAction Stop)
            if ($results.Count -eq 0) { $failures.Add($t) }
        } catch {
            $failures.Add($t)
            Write-Verbose "Test-DnsHealth: $t resolution failed. $($_.Exception.Message)"
        }
    }

    # Default gateway reachability (1 ping, 1s timeout).
    $gatewayReachable = $null
    $gateway = $null
    try {
        $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
            Sort-Object RouteMetric | Select-Object -First 1
        $gateway = $route.NextHop
        if ($gateway -and $gateway -ne '0.0.0.0') {
            $gatewayReachable = [bool](Test-Connection -TargetName $gateway -Count 1 -Quiet `
                    -TimeoutSeconds 1 -ErrorAction SilentlyContinue)
        }
    } catch {
        Write-Verbose "Test-DnsHealth: gateway probe failed. $($_.Exception.Message)"
    }

    # Severity rubric (ordered by precedence, most severe first):
    #   CRIT  -- gateway confirmed unreachable (primary network failure)
    #   WARN  -- any DNS target failed, regardless of gateway status
    #            (DNS failures are actionable even when gateway probe didn't run)
    #   INFO  -- gateway probe couldn't determine reachability AND DNS is fine
    #   OK    -- gateway reachable and all DNS resolved
    # Order matters: DNS failures are still reported at WARN when the gateway
    # state is unknown -- ordering "gateway unknown -> INFO" ahead of the
    # DNS-failure check would under-report real DNS problems.
    $severity = 'OK'
    $summary = "DNS OK ($($targets.Count)/$($targets.Count)); gateway $gateway reachable."
    if ($gatewayReachable -eq $false) {
        $severity = 'CRIT'
        $summary = "Default gateway $gateway unreachable."
    } elseif ($failures.Count -gt 0) {
        $severity = 'WARN'
        $gatewayNote = $null -eq $gatewayReachable ? ' (gateway unknown)' : ''
        $summary = "DNS resolution failed for: $($failures -join ', ').$gatewayNote"
    } elseif ($null -eq $gatewayReachable) {
        $severity = 'INFO'
        $summary = "DNS $($targets.Count - $failures.Count)/$($targets.Count) resolved; gateway unknown."
    }

    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity $severity -Summary $summary -Commands $commands `
        -Detail @{
        targets_total     = $targets.Count
        targets_failed    = $failures.Count
        targets_failures  = @($failures)
        default_gateway   = $gateway
        gateway_reachable = $gatewayReachable
    } `
        -NeedsAdmin $false -RanSuccessfully $true `
        -DurationMs ([int]$sw.ElapsedMilliseconds)
} catch {
    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity 'UNKNOWN' -Summary 'DNS health check failed.' -Commands $commands `
        -RanSuccessfully $false -ErrorMessage $_.Exception.Message `
        -DurationMs ([int]$sw.ElapsedMilliseconds)
}

$sw.Stop()
$result.duration_ms = [int]$sw.ElapsedMilliseconds
$result | Write-HealthResult -Human:$Human
