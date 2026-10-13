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

$id = 'winget-upgrades'
$category = 'updates'
$commands = @(
    'Get-WinGetPackage | Where-Object IsUpdateAvailable  # requires Microsoft.WinGet.Client v1.12+'
    'winget upgrade --include-unknown --accept-source-agreements  # fallback'
)

# Correlate KEV on the structured winget Id, never display names: a name substring match
# floods false positives (Microsoft.WSL's "Windows" name matches every Windows CVE).

$FailureSummary = 'winget upgrade check failed.'
$PassThru = $false
$CheckBody = {
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
        # $kevGap stays set unless correlation ran against a usable KEV list; it is the
        # reason the check cannot vouch for "no KEV match".
        $kevGap = 'KEV correlation did not run.'
        $kevState = 'unknown'
        $kevAgeDays = $null
        $kevFetchError = $null
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
            # Read the _cache_* annotations by name: StrictMode throws on a missing property.
            $kevCount = 0
            if ($null -ne $kev) {
                $kevProps = $kev.PSObject.Properties
                if ($kevProps['_cache_state'] -and $kevProps['_cache_state'].Value) {
                    $kevState = $kevProps['_cache_state'].Value
                }
                if ($kevProps['_cache_age_days']) { $kevAgeDays = $kevProps['_cache_age_days'].Value }
                if ($kevProps['_fetch_error']) { $kevFetchError = $kevProps['_fetch_error'].Value }
                if ($kevProps['vulnerabilities']) {
                    $kevCount = @($kev.vulnerabilities | Where-Object { $null -ne $_ }).Count
                }
            }
            if ($kevCount -gt 0) {
                $kevGap = $null
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
                                    upgrade_id  = $u.id
                                    upgrade     = $upgradeString
                                    cve_id      = $vuln.cveID
                                    vendor      = $vuln.vendorProject
                                    product     = $vuln.product
                                    match_basis = 'name-only'
                                })
                        }
                    }
                }
            } else {
                $kevGap = switch ($kevState) {
                    'unavailable' { "CISA KEV feed fetch failed and no cached list exists: $kevFetchError" }
                    'empty' { 'CISA KEV feed returned no entries.' }
                    default { 'CISA KEV list is empty or unparsable.' }
                }
            }
        } catch {
            $kevGap = "KEV lookup failed: $($_.Exception.Message)"
        }

        # One upgrade can match several KEV rows, so the upgrade figure counts
        # distinct Ids and the CVE rows are reported as their own number.
        $kevUpgradeCount = @($kevMatches | ForEach-Object { "$($_.upgrade_id)".ToLowerInvariant() } |
                Select-Object -Unique).Count

        # A KEV gap with upgrades pending means "no KEV match" is unverified, so the
        # check reports UNKNOWN instead of a count-only severity. With no
        # upgrades there is nothing to correlate, and OK stays true without KEV data.
        $kevUnverified = $null -ne $kevGap -and $upgrades.Count -gt 0
        $ranSuccessfully = -not $kevUnverified
        $errorMessage = $null

        $severity = 'OK'
        $summary = 'No winget upgrades available.'
        if ($kevUnverified) {
            $severity = 'UNKNOWN'
            $summary = ("$($upgrades.Count) apps behind on winget upgrades; " +
                'CISA KEV correlation could not run, so KEV exposure is unknown.')
            $errorMessage = $kevGap
        } elseif ($kevMatches.Count -gt 0) {
            # Name-only match, so WARN: see the KEV feed record in
            # reference/windows/check-catalog.md (winget-upgrades).
            $severity = 'WARN'
            $cveIds = @($kevMatches | ForEach-Object { "$($_.cve_id)" } | Select-Object -Unique)
            $cveList = ($cveIds | Select-Object -First 5) -join ', '
            if ($cveIds.Count -gt 5) { $cveList += ", +$($cveIds.Count - 5) more" }
            $entryWord = $kevMatches.Count -eq 1 ? 'entry' : 'entries'
            $summary = ("$kevUpgradeCount upgrade(s) name-match CISA KEV " +
                "($($kevMatches.Count) matched CVE $entryWord`: $cveList); installed versions not compared.")
        } elseif ($upgrades.Count -gt 0) {
            $severity = $upgrades.Count -gt 10 ? 'WARN' : 'INFO'
            $summary = "$($upgrades.Count) apps behind on winget upgrades."
        }

        $notes = $null
        if ($null -ne $kevGap -and -not $kevUnverified) {
            $notes = "KEV correlation skipped (no upgrades to correlate): $kevGap"
        } elseif ($kevState -eq 'stale') {
            # Correlation ran, but on an older list than the run asked for: say so in the
            # summary too, so the at-a-glance table does not read as a fresh KEV check.
            $ageText = $null -ne $kevAgeDays ? "$kevAgeDays-day-old" : 'previously'
            $notes = ("CISA KEV refresh failed ($kevFetchError); correlated against the " +
                "$ageText cached list, so KEV entries added since then are not checked.")
            $suffix = ' KEV list stale: refresh failed.'
            if (($summary.Length + $suffix.Length) -le 240) { $summary += $suffix }
        }
        if ($nonConformingCount -gt 0) {
            $skip = ("KEV correlation: $nonConformingCount non-conforming Id(s) " +
                'skipped (no vendor.product structure).')
            $notes = $notes ? "$notes $skip" : $skip
        }

        $detail = @{
            upgrades_count          = $upgrades.Count
            kev_match_count         = $kevMatches.Count
            kev_upgrade_count       = $kevUpgradeCount
            upgrades                = $upgrades
            kev_matches             = $kevMatches
            non_conforming_id_count = $nonConformingCount
            kev_cache_state         = $kevState
            kev_cache_age_days      = $kevAgeDays
        }

        $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
            -Severity $severity -Summary $summary -Detail $detail -Commands $commands `
            -NeedsAdmin $false -RanSuccessfully $ranSuccessfully `
            -Notes $notes -ErrorMessage $errorMessage
    }
}
. (Join-Path $PSScriptRoot '..\lib\Invoke-HealthCheckEnvelope.ps1')
