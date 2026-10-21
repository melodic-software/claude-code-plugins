#Requires -Version 7.4

<#
.SYNOPSIS
Reads the extensions installed in every profile of one Chromium browser (Chrome
or Edge) and returns plain ExtensionRecords plus a ReadState.

.DESCRIPTION
Profile directory names come from 'Local State' profile.info_cache. Each
profile's 'Preferences' and 'Secure Preferences' hold extensions.settings; the
two are merged per extension id (Secure Preferences wins a key both carry)
before anything is judged, because a full entry can sit in one file while the
other holds a stub for the same id.

An entry with no location after the merge is a stub, not an installed
extension: it is dropped and counted in StubsSkipped. The location integer and
every pref key stay inside this file; only LocationCode and LocationKind leave.

Read-only, unelevated. Never opens a file under the profile's Extensions folder.
#>

$script:ChromiumUserData = @{
    chrome = @('Google', 'Chrome', 'User Data')
    edge   = @('Microsoft', 'Edge', 'User Data')
}

# Chromium's ManifestLocation enum (extensions/common/mojom/manifest.mojom).
$script:ChromiumLocationKind = @{
    1  = 'store'
    2  = 'external'
    3  = 'external'
    4  = 'unpacked'
    5  = 'component'
    6  = 'external'
    7  = 'policy'
    8  = 'command-line'
    9  = 'policy'
    10 = 'component'
}

function Read-ChromiumJson {
    <#
    .SYNOPSIS
    Reads one browser JSON file as a hashtable and names how the read went.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory = $true)] [string] $Path)

    try {
        $text = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        return [pscustomobject]@{ State = 'ok'; Data = ($text | ConvertFrom-Json -AsHashtable -ErrorAction Stop) }
    } catch [System.Management.Automation.ItemNotFoundException] {
        return [pscustomobject]@{ State = 'absent'; Data = $null }
    } catch [System.UnauthorizedAccessException] {
        return [pscustomobject]@{ State = 'denied'; Data = $null }
    } catch {
        if ($_.Exception.InnerException -is [System.UnauthorizedAccessException] -or
            $_.CategoryInfo.Category -eq 'PermissionDenied') {
            return [pscustomobject]@{ State = 'denied'; Data = $null }
        }
        return [pscustomobject]@{ State = 'error'; Data = $null }
    }
}

function Get-ChromiumSetting {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([AllowNull()] $Prefs)

    if ($Prefs -isnot [hashtable]) { return @{} }
    $extensions = $Prefs['extensions']
    if ($extensions -isnot [hashtable]) { return @{} }
    $settings = $extensions['settings']
    if ($settings -isnot [hashtable]) { return @{} }
    return $settings
}

function Test-ChromiumEnabled {
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowNull()] $DisableReasons)

    if ($null -eq $DisableReasons) { return $true }
    # Newer builds store a list of reasons; older ones a bitmask integer.
    if ($DisableReasons -is [array]) { return $DisableReasons.Count -eq 0 }
    return [long]$DisableReasons -eq 0
}

function Get-ChromiumExtension {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [ValidateSet('chrome', 'edge')] [string] $Browser,
        [string] $UserDataRoot
    )

    if (-not $UserDataRoot) {
        $UserDataRoot = [System.IO.Path]::Combine([string[]](@($env:LOCALAPPDATA) + $script:ChromiumUserData[$Browser]))
    }

    $records = [System.Collections.Generic.List[pscustomobject]]::new()
    $localState = Read-ChromiumJson -Path ([System.IO.Path]::Combine($UserDataRoot, 'Local State'))
    $result = [pscustomobject]@{
        Browser      = $Browser
        ReadState    = $localState.State
        ProfileCount = 0
        StubsSkipped = 0
        Extensions   = @()
    }
    if ($localState.State -ne 'ok') { return $result }

    $infoCache = $null
    if ($localState.Data['profile'] -is [hashtable]) { $infoCache = $localState.Data['profile']['info_cache'] }
    if ($infoCache -isnot [hashtable]) {
        $result.ReadState = 'error'
        return $result
    }

    $readState = 'ok'
    $stubs = 0
    foreach ($profileDir in @($infoCache.Keys | Sort-Object)) {
        $profileInfo = $infoCache[$profileDir]
        $displayName = if ($profileInfo -is [hashtable] -and $profileInfo['name']) { [string]$profileInfo['name'] } else { $profileDir }

        $merged = @{}
        foreach ($file in @('Preferences', 'Secure Preferences')) {
            $read = Read-ChromiumJson -Path ([System.IO.Path]::Combine($UserDataRoot, $profileDir, $file))
            if ($read.State -notin @('ok', 'absent') -and $readState -eq 'ok') { $readState = $read.State }
            $settings = Get-ChromiumSetting -Prefs $read.Data
            foreach ($extId in $settings.Keys) {
                $entry = $settings[$extId]
                if ($entry -isnot [hashtable]) { continue }
                if (-not $merged.ContainsKey($extId)) { $merged[$extId] = @{} }
                foreach ($k in $entry.Keys) { $merged[$extId][$k] = $entry[$k] }
            }
        }

        foreach ($extId in @($merged.Keys | Sort-Object)) {
            $entry = $merged[$extId]
            if (-not $entry.ContainsKey('location') -or $null -eq $entry['location']) {
                $stubs++
                continue
            }
            $code = [int]$entry['location']
            $kind = $script:ChromiumLocationKind[$code]
            if (-not $kind) { $kind = 'unknown' }
            $manifest = if ($entry['manifest'] -is [hashtable]) { $entry['manifest'] } else { @{} }
            $active = if ($entry['active_permissions'] -is [hashtable]) { $entry['active_permissions'] } else { @{} }
            $hosts = @(@($active['explicit_host']) + @($active['scriptable_host']) |
                    Where-Object { $_ -is [string] } | Sort-Object -Unique)

            $records.Add([pscustomobject]@{
                    Browser        = $Browser
                    ProfileDir     = $profileDir
                    ProfileName    = $displayName
                    ExtId          = $extId
                    Name           = if ($manifest['name']) { [string]$manifest['name'] } else { $null }
                    Version        = if ($manifest['version']) { [string]$manifest['version'] } else { $null }
                    LocationCode   = $code
                    LocationKind   = $kind
                    FromWebstore   = [bool]$entry['from_webstore']
                    Enabled        = Test-ChromiumEnabled -DisableReasons $entry['disable_reasons']
                    ApiPermissions = [string[]]@($active['api'] | Where-Object { $_ -is [string] })
                    HostPatterns   = [string[]]$hosts
                    Signed         = $null
                    ForeignInstall = $null
                })
        }
        $result.ProfileCount++
    }

    $result.ReadState = $readState
    $result.StubsSkipped = $stubs
    $result.Extensions = $records.ToArray()
    return $result
}
