#Requires -Version 7.4
<#
.SYNOPSIS
Check: winget app updates vs CISA KEV. Emits a CheckResult JSON on stdout.

See references/windows/check-catalog.md#6-winget-app-updates for rubric.
#>
[CmdletBinding()]
param([switch]$Human)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')
. (Join-Path $PSScriptRoot '..\lib\Get-CisaKevCache.ps1')
. (Join-Path $PSScriptRoot '..\lib\Get-WingetPackageUpdate.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$id = 'winget-upgrades'
$category = 'updates'
$commands = @(
    'Get-WinGetPackage | Where-Object IsUpdateAvailable  # requires Microsoft.WinGet.Client v1.12+'
    'winget upgrade --include-unknown --accept-source-agreements  # fallback'
)

# KEV correlation is ID-based, not display-name-based. The previous substring
# match on display names produced 170 false positives ("Windows Subsystem for
# Linux" / id Microsoft.WSL was flagged against every Microsoft/Windows CVE
# because the name contained "Windows"). The winget Id is already a structured
# "<vendor>.<product>" token assigned by the package manifest author, so
# matching on Id is both precise and cheap.

try {
    $wrapperResult = Get-WingetPackageUpdate

    # Contract: Get-WingetPackageUpdate always returns @{ upgrades; error }.
    if ($null -eq $wrapperResult -or -not ($wrapperResult -is [hashtable] -or
            $wrapperResult -is [System.Collections.IDictionary])) {
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
            -ErrorMessage $wrapperError `
            -DurationMs ([int]$sw.ElapsedMilliseconds)
    } else {
        $upgrades = @($upgrades)

        $nonConformingIds = @($upgrades | Where-Object { $_.id -notmatch '\.' })
        $nonConformingCount = $nonConformingIds.Count

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

            # Seed the cache on first run by copying the checked-in stub.
            # Get-CisaKevCache will detect the empty vulnerabilities array
            # and fetch live data to replace it.
            if (-not (Test-Path -LiteralPath $kevPath)) {
                $skillRoot = Split-Path -Path $PSScriptRoot -Parent |
                    Split-Path -Parent |
                    Split-Path -Parent
                $seedPath = Join-Path $skillRoot 'catalog\cisa-kev.json'
                if (Test-Path -LiteralPath $seedPath) {
                    Copy-Item -LiteralPath $seedPath -Destination $kevPath -Force
                }
            }

            $kev = Get-CisaKevCache -CachePath $kevPath -MaxAgeDays 7
            if ($kev -and $kev.vulnerabilities) {
                # Index KEV entries by lowercase "vendor.product" key so each
                # upgrade Id can be matched in O(1) instead of scanning every
                # vuln. KEV has ~1300 entries and a typical machine reports
                # ~30 upgrades, so the prior nested loop did ~40k comparisons
                # per run.
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

                    # Test idLower against exact key, then progressively
                    # shorter prefixes (split on '.') so "Microsoft.WSL.Foo"
                    # also matches "microsoft.wsl". Bounded by Id segment
                    # count, typically 2-4.
                    $segments = $idLower.Split('.')
                    for ($i = $segments.Length; $i -ge 2; $i--) {
                        $candidate = ($segments[0..($i - 1)] -join '.')
                        if (-not $kevIndex.ContainsKey($candidate)) { continue }
                        foreach ($vuln in $kevIndex[$candidate]) {
                            $upgradeString = ("$($u.name) $($u.current_version) " +
                                "-> $($u.available_version)")
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
        } elseif ($upgrades.Count -gt 10) {
            $severity = 'WARN'
            $summary = "$($upgrades.Count) apps behind on winget upgrades."
        } elseif ($upgrades.Count -gt 0) {
            $severity = 'INFO'
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
            -DurationMs ([int]$sw.ElapsedMilliseconds) `
            -Notes $notes
    }
} catch {
    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity 'UNKNOWN' -Summary 'winget upgrade check failed.' -Commands $commands `
        -RanSuccessfully $false -ErrorMessage $_.Exception.Message `
        -DurationMs ([int]$sw.ElapsedMilliseconds)
}

$sw.Stop()
$result.duration_ms = [int]$sw.ElapsedMilliseconds
$result | Write-HealthResult -Human:$Human
