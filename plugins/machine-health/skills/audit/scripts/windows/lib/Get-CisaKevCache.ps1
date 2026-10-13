#Requires -Version 7.4

<#
.SYNOPSIS
Return the cached CISA Known Exploited Vulnerabilities list, refreshing if
stale, missing, unparsable, or still a checked-in seed stub.

.DESCRIPTION
Cache lives at catalog/cisa-kev.json relative to the skill root. Refresh policy:

    refresh when (ForceRefresh)
           or  (file missing)
           or  (file unparsable)
           or  (vulnerabilities array empty -- catches the seed stub)
           or  (file mtime older than MaxAgeDays)

Detection is content-based, not size-based: the checked-in seed stub carries an
explanatory _comment plus an empty vulnerabilities array, so any file that parses
to zero vulnerabilities is treated as uninitialized regardless of byte size.

Every fetch attempt appends the URL to the run log so egress stays auditable
per SKILL.md guardrails. On fetch failure: returns the existing cache (even if
stale or empty) and logs the error rather than throwing -- a stale KEV list is
better than no list.

The returned object always carries three annotation properties, so a caller can
tell a failed fetch from a feed that is genuinely empty and never reports full
confidence on data it did not get:

    _cache_state     fresh        cache within MaxAgeDays, or refreshed now
                     stale        refresh failed; serving the prior cached list
                     unavailable  refresh failed and no usable prior list
                     empty        refresh succeeded but the feed had no entries
    _cache_age_days  age in days of the list served, from the cache file mtime
                     ($null when no list is served)
    _fetch_error     the refresh failure message ($null when no refresh failed)

Downloads to a temp file first, then validates JSON and atomically replaces
the cache. Partial/corrupt downloads do not clobber a previously-good cache.
#>

# Write egress lines only through Write-EgressLogLine: a hand-rolled line gets
# double-stamped and breaks Read-EgressLog's urls_called ingestion.
. (Join-Path $PSScriptRoot 'Invoke-AllowlistedWeb.ps1')

$script:CisaKevUrl = 'https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json'

function Get-CisaKevCache {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [string] $CachePath,
        [string] $LogPath,
        [int] $MaxAgeDays = 7,
        [switch] $ForceRefresh
    )

    $needsRefresh = $ForceRefresh.IsPresent

    $cached = $null
    if (Test-Path -LiteralPath $CachePath) {
        try {
            $raw = Get-Content -LiteralPath $CachePath -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $cached = $raw | ConvertFrom-Json -ErrorAction Stop
            } else {
                $needsRefresh = $true
            }
        } catch {
            Write-Warning "Get-CisaKevCache: cache parse failed, will refresh. $($_.Exception.Message)"
            $needsRefresh = $true
        }
    } else {
        $needsRefresh = $true
    }

    if (-not $needsRefresh -and $null -ne $cached) {
        if (-not $cached.PSObject.Properties['vulnerabilities'] -or
            $null -eq $cached.vulnerabilities -or
            @($cached.vulnerabilities).Count -eq 0) {
            $needsRefresh = $true
        } else {
            $mtime = (Get-Item -LiteralPath $CachePath).LastWriteTime
            $ageDays = (New-TimeSpan -Start $mtime -End (Get-Date)).TotalDays
            if ($ageDays -gt $MaxAgeDays) { $needsRefresh = $true }
        }
    }

    $state = 'fresh'
    $fetchError = $null
    if ($needsRefresh) {
        $fetch = Invoke-KevFetch -CachePath $CachePath -LogPath $LogPath
        if ($null -eq $fetch.Error) {
            $cached = $fetch.Data
        } else {
            # Keep the prior cache, but say so: a fallback is never reported as fresh.
            $fetchError = $fetch.Error
            $state = 'stale'
        }
    }

    if ($null -eq $cached -or -not $cached.PSObject.Properties['vulnerabilities'] -or
        $null -eq $cached.vulnerabilities) {
        $cached = [pscustomobject]@{ vulnerabilities = @() }
    }

    $ageDays = $null
    if (@($cached.vulnerabilities).Count -eq 0) {
        # Nothing to correlate against: after a failed refresh that is unavailable,
        # after a good one the feed itself was empty.
        $state = $null -ne $fetchError ? 'unavailable' : 'empty'
    } elseif (Test-Path -LiteralPath $CachePath) {
        $mtime = (Get-Item -LiteralPath $CachePath).LastWriteTime
        $ageDays = [math]::Round((New-TimeSpan -Start $mtime -End (Get-Date)).TotalDays, 1)
    }

    $cached | Add-Member -NotePropertyName '_cache_state' -NotePropertyValue $state -Force
    $cached | Add-Member -NotePropertyName '_cache_age_days' -NotePropertyValue $ageDays -Force
    $cached | Add-Member -NotePropertyName '_fetch_error' -NotePropertyValue $fetchError -Force
    return $cached
}

function Invoke-KevFetch {
    # Returns @{ Data; Error }: the downloaded document on success, the failure message
    # otherwise, so the caller never mistakes a failed fetch for an empty feed.
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [string] $CachePath,
        [string] $LogPath
    )

    Write-EgressLogLine -LogPath $LogPath -Kind 'GET' -Uri $script:CisaKevUrl

    $tempPath = "$CachePath.download"
    try {
        $fetchParams = @{
            Uri         = $script:CisaKevUrl
            OutFile     = $tempPath
            TimeoutSec  = 30
            ErrorAction = 'Stop'
        }
        Invoke-WebRequest @fetchParams | Out-Null
        $downloaded = Get-Content -LiteralPath $tempPath -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop

        if (-not $downloaded.PSObject.Properties['vulnerabilities']) {
            throw "Downloaded payload lacks 'vulnerabilities' array."
        }

        Move-Item -LiteralPath $tempPath -Destination $CachePath -Force
        return @{ Data = $downloaded; Error = $null }
    } catch {
        $fetchFailure = $_.Exception.Message
        Write-EgressLogLine -LogPath $LogPath -Kind 'FAIL' -Uri $script:CisaKevUrl `
            -Message $_.Exception.Message
        Write-Warning "Get-CisaKevCache: fetch failed; keeping prior cache. $($_.Exception.Message)"
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        $message = $fetchFailure
        if ([string]::IsNullOrWhiteSpace($message)) { $message = 'KEV fetch failed (no error detail).' }
        return @{ Data = $null; Error = $message }
    }
}
