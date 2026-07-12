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

Downloads to a temp file first, then validates JSON and atomically replaces
the cache. Partial/corrupt downloads do not clobber a previously-good cache.
#>

. (Join-Path $PSScriptRoot 'Write-MachineHealthLog.ps1')

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

    if ($needsRefresh) {
        $cached = Invoke-KevFetch -CachePath $CachePath -LogPath $LogPath -FallbackCache $cached
    }

    if ($null -ne $cached -and $cached.PSObject.Properties['vulnerabilities']) {
        return $cached
    }
    return [pscustomobject]@{ vulnerabilities = @() }
}

function Invoke-KevFetch {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $CachePath,
        [string] $LogPath,
        $FallbackCache
    )

    $stamp = (Get-Date).ToString('o')
    Write-MachineHealthLog -LogPath $LogPath -Message "$stamp egress GET $script:CisaKevUrl"

    $tempPath = "$CachePath.download"
    try {
        $fetchParams = @{
            Uri             = $script:CisaKevUrl
            OutFile         = $tempPath
            UseBasicParsing = $true
            TimeoutSec      = 30
            ErrorAction     = 'Stop'
        }
        Invoke-WebRequest @fetchParams | Out-Null
        $downloaded = Get-Content -LiteralPath $tempPath -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop

        if (-not $downloaded.PSObject.Properties['vulnerabilities']) {
            throw "Downloaded payload lacks 'vulnerabilities' array."
        }

        Move-Item -LiteralPath $tempPath -Destination $CachePath -Force
        return $downloaded
    } catch {
        $failStamp = (Get-Date).ToString('o')
        Write-MachineHealthLog -LogPath $LogPath `
            -Message "$failStamp egress FAIL $script:CisaKevUrl - $($_.Exception.Message)"
        Write-Warning "Get-CisaKevCache: fetch failed; keeping prior cache. $($_.Exception.Message)"
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        return $FallbackCache
    }
}
