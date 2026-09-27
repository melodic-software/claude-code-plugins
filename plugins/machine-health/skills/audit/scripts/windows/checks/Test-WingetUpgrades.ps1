#Requires -Version 7.4
<#
.SYNOPSIS
Check: winget app updates vs CISA KEV. Emits a CheckResult JSON on stdout.

See reference/windows/check-catalog.md#6-winget-app-updates for rubric.

.PARAMETER LogPath
Run log the KEV cache fetch appends its egress line to. The orchestrator passes
its per-run log here so the CISA fetch lands in the same egress audit trail that
populates urls_called; omitted, the fetch still runs but goes unlogged.
#>
[CmdletBinding()]
param(
    [switch]$Human,
    [string]$LogPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')
. (Join-Path $PSScriptRoot '..\lib\Get-CisaKevCache.ps1')
. (Join-Path $PSScriptRoot '..\lib\Get-WingetPackageUpdate.ps1')
. (Join-Path $PSScriptRoot '..\lib\Resolve-SkillRoot.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$id = 'winget-upgrades'
$category = 'updates'
$commands = @(
    'Get-WinGetPackage | Where-Object IsUpdateAvailable  # requires Microsoft.WinGet.Client v1.12+'
    'winget upgrade --include-unknown --accept-source-agreements  # fallback'
)

# Correlate KEV on the structured winget Id, never display names: a name substring match
# floods false positives (Microsoft.WSL's "Windows" name matches every Windows CVE).

try {
    $wrapperResult = Get-WingetPackageUpdate

    # Contract: Get-WingetPackageUpdate always returns @{ upgrades; error }.
    if ($wrapperResult -isnot [System.Collections.IDictionary]) {
        $actualType = if ($null -eq $wrapperResult) { '$null' } else { $wrapperResult.GetType().FullName }
        throw "Get-WingetPackageUpdate returned $actualType; expected hashtable."
    }
    $upgrades = $wrapperResult['upgrades']
    $wrapperError = $wrapperResult['error']

    if ($null -eq $upgrades) {
        $msg = $wrapperError ? "winget unavailable: $wrapperError" : 'winget unavailable (no error detail).'
        $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
            -Severity 'UNKNOWN' -Summary $msg `
            -Commands $commands `
            -RanSuccessfully $false `
            -ErrorMessage $wrapperError
    } else {
        $upgrades = @($upgrades)

        $nonConformingCount = @($upgrades | Where-Object { $_.id -notmatch '\.' }).Count

        $kevMatches = [System.Collections.Generic.List[pscustomobject]]::new()
        $kevNotes = $null
        try {
            # Per-user cache -- never in source control. Falls back to the
            # stub at catalog/cisa-kev.json only for initial schema seeding.
            $cacheRoot = Join-Path $env:LOCALAPPDATA 'machine-health\cache'
            if (-not (Test-Path -LiteralPath $cacheRoot)) {
                New-Item -ItemType Directory -Path $cacheRoot -Force | Out-Null
            }
            $kevPath = Join-Path $cacheRoot 'cisa-kev.json'

            # Seed from the checked-in stub; Get-CisaKevCache sees its empty
            # vulnerabilities array and fetches live data to replace it.
            if (-not (Test-Path -LiteralPath $kevPath)) {
                $seedPath = Join-Path (Resolve-SkillRoot) 'catalog\cisa-kev.json'
                if (Test-Path -LiteralPath $seedPath) {
                    Copy-Item -LiteralPath $seedPath -Destination $kevPath -Force
                }
            }

            $kev = Get-CisaKevCache -CachePath $kevPath -LogPath $LogPath -MaxAgeDays 7
            if ($kev -and $kev.vulnerabilities) {
                # Index KEV by lowercase "vendor.product" so each upgrade Id is an O(1) lookup.
                $kevIndex = @{}
                foreach ($vuln in $kev.vulnerabilities) {
                    if ([string]::IsNullOrWhiteSpace($vuln.vendorProject) -or
                        [string]::IsNullOrWhiteSpace($vuln.product)) {
                        continue
                    }
                    $key = "$($vuln.vendorProject).$($vuln.product)".ToLowerInvariant()
                    if (-not $kevIndex.ContainsKey($key)) {
                        $kevIndex[$key] = [System.Collections.Generic.List[object]]::new()
                    }
                    [void]$kevIndex[$key].Add($vuln)
                }

                foreach ($u in $upgrades) {
                    $upgradeId = "$($u.id)"
                    if ([string]::IsNullOrWhiteSpace($upgradeId)) { continue }
                    $idLower = $upgradeId.ToLowerInvariant()

                    # Exact Id first, then shorter '.'-prefixes, so "Microsoft.WSL.Foo"
                    # also matches "microsoft.wsl".
                    $segments = $idLower.Split('.')
                    for ($i = $segments.Length; $i -ge 2; $i--) {
                        $candidate = ($segments[0..($i - 1)] -join '.')
                        if (-not $kevIndex.ContainsKey($candidate)) { continue }
                        $upgradeString = ("$($u.name) $($u.current_version) " +
                            "-> $($u.available_version)")
                        foreach ($vuln in $kevIndex[$candidate]) {
                            $kevMatches.Add([pscustomobject]@{
                                    upgrade_id = $u.id
                                    upgrade    = $upgradeString
                                    cve_id     = $vuln.cveID
                                    vendor     = $vuln.vendorProject
                                    product    = $vuln.product
                                })
                        }
                    }
                }
            } else {
                $kevNotes = 'CISA KEV cache is empty or unparsable; KEV correlation skipped.'
            }
        } catch {
            $kevNotes = "KEV lookup failed: $($_.Exception.Message)"
        }

        $severity = 'OK'
        $summary = 'No winget upgrades available.'
        if ($kevMatches.Count -gt 0) {
            $severity = 'CRIT'
            $summary = "$($kevMatches.Count) upgrade(s) match CISA KEV."
        } elseif ($upgrades.Count -gt 0) {
            $severity = $upgrades.Count -gt 10 ? 'WARN' : 'INFO'
            $summary = "$($upgrades.Count) apps behind on winget upgrades."
        }

        $notes = $kevNotes
        if ($nonConformingCount -gt 0) {
            $skip = ("KEV correlation: $nonConformingCount non-conforming Id(s) " +
                'skipped (no vendor.product structure).')
            $notes = $notes ? "$notes $skip" : $skip
        }

        $detail = @{
            upgrades_count          = $upgrades.Count
            kev_match_count         = $kevMatches.Count
            upgrades                = $upgrades
            kev_matches             = $kevMatches
            non_conforming_id_count = $nonConformingCount
        }

        $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
            -Severity $severity -Summary $summary -Detail $detail -Commands $commands `
            -NeedsAdmin $false -RanSuccessfully $true `
            -Notes $notes
    }
} catch {
    $result = New-HealthFailureResult -Id $id -Category $category `
        -Summary 'winget upgrade check failed.' -Commands $commands -ErrorRecord $_
}

Complete-HealthCheck -Result $result -Stopwatch $sw -Human:$Human
