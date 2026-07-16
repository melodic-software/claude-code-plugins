#Requires -Version 7.4

<#
.SYNOPSIS
Read-only probes for Windows dimensions not yet in the catalog. Returns an
array of probe records consumed by Invoke-Discovery.

.DESCRIPTION
Each probe is safe to call unconditionally. Probes never prompt, never
install, never write outside RAM. When a probe's target tool isn't present
the probe returns detected=$false.

Probe record shape:
    { dimension, detected, suggested_check_id, rationale, straightforward }

"straightforward" signals whether the proposed check is read-only, needs no
new egress, and no new elevation. Non-straightforward proposals are
surfaced in the report but would require human approval before landing in
the catalog (future work).

Windows-specific by design. The macOS/linux equivalents will live in
scripts/<os>/lib/Get-<Os>DiscoveryProbes.ps1.
#>

function Test-CommandAvailable {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] [string[]] $Name)
    foreach ($candidate in $Name) {
        try {
            if (Get-Command $candidate -ErrorAction SilentlyContinue) { return $true }
        } catch {
            Write-Verbose "Get-Command $candidate failed: $($_.Exception.Message)"
        }
    }
    return $false
}

function Get-WindowsDiscoveryProbe {
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    $probes = [System.Collections.Generic.List[pscustomobject]]::new()

    # Tool-presence probes: each detects via Test-CommandAvailable. Python
    # probes two command names (python, python3); the rest probe one.
    $commandProbes = @(
        @{
            Dimension = 'Docker Desktop'
            Commands  = @('docker')
            CheckId   = 'docker-disk-usage'
            Rationale = 'docker system df reports image+volume disk usage; trend candidate.'
        }
        @{
            Dimension = 'WSL distros'
            Commands  = @('wsl')
            CheckId   = 'wsl-disk-usage'
            Rationale = 'wsl --list --verbose + per-distro vhdx size; trend candidate.'
        }
        @{
            Dimension = '.NET SDK'
            Commands  = @('dotnet')
            CheckId   = 'sdk-versions'
            Rationale = 'dotnet --list-sdks + EOL table; surface LTS drift.'
        }
        @{
            Dimension = 'Node.js runtime'
            Commands  = @('node')
            CheckId   = 'sdk-versions'
            Rationale = 'node --version + EOL table; bundled with .NET SDK check.'
        }
        @{
            Dimension = 'Python runtime'
            Commands  = @('python', 'python3')
            CheckId   = 'sdk-versions'
            Rationale = 'python --version + EOL table; bundled with .NET SDK check.'
        }
    )

    foreach ($probe in $commandProbes) {
        $probes.Add([pscustomobject]@{
                dimension          = $probe.Dimension
                detected           = Test-CommandAvailable $probe.Commands
                suggested_check_id = $probe.CheckId
                rationale          = $probe.Rationale
                straightforward    = $true
            })
    }

    # User cert store
    $certPath = 'Cert:\CurrentUser\My'
    $certs = @()
    try {
        $certs = @(Get-ChildItem -Path $certPath -ErrorAction SilentlyContinue)
    } catch {
        Write-Verbose "Cert store enum failed: $($_.Exception.Message)"
    }
    $probes.Add([pscustomobject]@{
            dimension          = 'User certificate store'
            detected           = ($certs.Count -gt 0)
            suggested_check_id = 'cert-expiry'
            rationale          = "$($certs.Count) cert(s) in CurrentUser\My; expiry detection is read-only."
            straightforward    = $true
        })

    # Scheduled tasks with failing LastTaskResult
    $failedTasks = @()
    try {
        $failedTasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue |
                Where-Object { $_.TaskPath -notlike '\Microsoft\*' } |
                ForEach-Object {
                    $info = $_ | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
                    if ($info -and $info.LastTaskResult -ne 0 -and $info.LastTaskResult -ne 267014) {
                        $_
                    }
                })
    } catch {
        Write-Verbose "Get-ScheduledTask probe failed: $($_.Exception.Message)"
    }
    $probes.Add([pscustomobject]@{
            dimension          = 'Scheduled task failures'
            detected           = $true
            suggested_check_id = 'scheduled-tasks'
            rationale          = ('Filters to non-Microsoft tasks with non-zero LastTaskResult; ' +
                "$($failedTasks.Count) failing today.")
            straightforward    = $true
        })

    # Reliability Monitor readiness
    $reliabilityOk = $false
    try {
        $records = @(Get-CimInstance Win32_ReliabilityRecords -ErrorAction SilentlyContinue | Select-Object -First 1)
        $reliabilityOk = ($records.Count -gt 0)
    } catch {
        Write-Verbose "Win32_ReliabilityRecords probe failed: $($_.Exception.Message)"
    }
    $probes.Add([pscustomobject]@{
            dimension          = 'Reliability Monitor data'
            detected           = $reliabilityOk
            suggested_check_id = 'reliability'
            rationale          = ('Win32_ReliabilityRecords + Win32_ReliabilityStabilityMetrics; ' +
                'high-signal weekly trend.')
            straightforward    = $true
        })

    return $probes.ToArray()
}
