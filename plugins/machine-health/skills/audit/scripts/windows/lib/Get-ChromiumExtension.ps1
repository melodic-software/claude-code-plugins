#Requires -Version 7.4

<#
.SYNOPSIS
Reads the extensions installed in every profile of one Chromium browser (Chrome
or Edge) and returns ExtensionRecords plus a ReadState per profile.

.DESCRIPTION
Profile directory names come from 'Local State' profile.info_cache. Each
profile's 'Preferences' and 'Secure Preferences' hold extensions.settings; the
two are merged per extension id (Secure Preferences wins a key both carry)
before anything is judged, because a full entry can sit in one file while the
other holds a stub for the same id. An entry with no location after the merge
is a stub, not an installed extension: it is dropped and counted in
StubsSkipped.

Each profile is read inside its own guard: a malformed or oversized file, or
an unexpected value, sets that profile's ReadState to 'error' and the other
profiles still read. The browser's install folder comes from its App Paths
registration, so a component extension's path can be checked against it.

The location integer and every pref key stay inside this file. Read-only,
unelevated; never opens a file under the profile's Extensions folder.
#>

. (Join-Path $PSScriptRoot 'New-ExtensionRecord.ps1')

$script:ChromiumBrowser = @{
    chrome = [pscustomobject]@{ UserData = @('Google', 'Chrome', 'User Data'); Exe = 'chrome.exe' }
    edge   = [pscustomobject]@{ UserData = @('Microsoft', 'Edge', 'User Data'); Exe = 'msedge.exe' }
}

# Chromium's ManifestLocation enum (extensions/common/mojom/manifest.mojom).
# EXTERNAL_COMPONENT (10) installs through the component updater into the
# profile, not the browser install, so it is treated as external.
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
    10 = 'external'
}

function Get-ChromiumInstallDir {
    <#
    .SYNOPSIS
    The browser's install folder from its App Paths registration, or $null.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)] [string] $Exe)

    foreach ($hive in @('HKLM:', 'HKCU:')) {
        try {
            $exePath = (Get-ItemProperty -LiteralPath "$hive\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$Exe" -ErrorAction Stop).'(default)'
        } catch {
            continue
        }
        if ($exePath -is [string] -and [System.IO.Path]::IsPathRooted($exePath.Trim('"'))) {
            return [System.IO.Path]::GetDirectoryName($exePath.Trim('"'))
        }
    }
    return $null
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
    <#
    .SYNOPSIS
    $true with no disable reason, $false with one, $null when the value is malformed.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowNull()] $DisableReasons)

    if ($null -eq $DisableReasons) { return $true }
    # Newer builds store a list of reasons; older ones a bitmask integer.
    if ($DisableReasons -is [array]) { return $DisableReasons.Count -eq 0 }
    $mask = 0L
    if ([long]::TryParse([string]$DisableReasons, [ref]$mask)) { return $mask -eq 0 }
    return $null
}

function ConvertTo-ChromiumRecord {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [string] $Browser,
        [Parameter(Mandatory = $true)] [string] $ProfileDir,
        [Parameter(Mandatory = $true)] [string] $ExtId,
        [Parameter(Mandatory = $true)] [hashtable] $Entry,
        [AllowNull()] [string] $InstallDir
    )

    $code = 0
    $parsed = [int]::TryParse([string]$Entry['location'], [ref]$code)
    $kind = if ($parsed -and $script:ChromiumLocationKind.ContainsKey($code)) { $script:ChromiumLocationKind[$code] } else { 'unknown' }
    $manifest = if ($Entry['manifest'] -is [hashtable]) { $Entry['manifest'] } else { @{} }
    $active = if ($Entry['active_permissions'] -is [hashtable]) { $Entry['active_permissions'] } else { @{} }

    $path = $Entry['path']
    $absolute = $null
    $underInstall = $null
    if ($path -is [string] -and $path) {
        $absolute = [System.IO.Path]::IsPathRooted($path)
        if ($InstallDir) {
            $underInstall = $absolute -and $path.StartsWith($InstallDir.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)
        }
    }

    $recordArgs = @{
        Browser             = $Browser
        ProfileDir          = $ProfileDir
        ExtId               = $ExtId
        Name                = if ($manifest['name'] -is [string]) { $manifest['name'] } else { $null }
        Version             = if ($manifest['version'] -is [string]) { $manifest['version'] } else { $null }
        LocationCode        = if ($parsed) { $code } else { $null }
        LocationKind        = $kind
        FromWebstore        = if ($Entry['from_webstore'] -is [bool]) { $Entry['from_webstore'] } else { $null }
        Enabled             = Test-ChromiumEnabled -DisableReasons $Entry['disable_reasons']
        ApiPermissions      = [string[]]@($active['api'] | Where-Object { $_ -is [string] })
        HostPatterns        = [string[]]@(@($active['explicit_host']) + @($active['scriptable_host']) | Where-Object { $_ -is [string] })
        PathIsAbsolute      = $absolute
        UnderBrowserInstall = $underInstall
    }
    New-ExtensionRecord @recordArgs
}

function Get-ChromiumExtension {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [ValidateSet('chrome', 'edge')] [string] $Browser,
        [string] $UserDataRoot
    )

    $spec = $script:ChromiumBrowser[$Browser]
    if (-not $UserDataRoot) {
        $UserDataRoot = [System.IO.Path]::Combine([string[]](@($env:LOCALAPPDATA) + $spec.UserData))
    }

    $result = [pscustomobject]@{
        Browser      = $Browser
        ReadState    = 'ok'
        ProfileCount = 0
        StubsSkipped = 0
        Profiles     = @()
        Extensions   = @()
    }
    $localState = Read-BrowserJsonFile -Path ([System.IO.Path]::Combine($UserDataRoot, 'Local State'))
    $result.ReadState = $localState.State
    if ($localState.State -ne 'ok') { return $result }

    $infoCache = $null
    if ($localState.Data['profile'] -is [hashtable]) { $infoCache = $localState.Data['profile']['info_cache'] }
    if ($infoCache -isnot [hashtable]) {
        $result.ReadState = 'error'
        return $result
    }

    $installDir = Get-ChromiumInstallDir -Exe $spec.Exe
    $records = [System.Collections.Generic.List[pscustomobject]]::new()
    $profiles = [System.Collections.Generic.List[pscustomobject]]::new()
    $stubs = 0
    foreach ($profileDir in @($infoCache.Keys | Sort-Object)) {
        $state = 'ok'
        try {
            # A profile name is data from Local State: it must name a folder, not a path.
            if ($profileDir -match '[\\/:]' -or $profileDir -in @('.', '..')) { throw "Profile name is not a folder name." }
            $merged = @{}
            foreach ($file in @('Preferences', 'Secure Preferences')) {
                $read = Read-BrowserJsonFile -Path ([System.IO.Path]::Combine($UserDataRoot, $profileDir, $file))
                if ($read.State -notin @('ok', 'absent') -and $state -eq 'ok') { $state = $read.State }
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
                if ($null -eq $entry['location']) {
                    $stubs++
                    continue
                }
                $records.Add((ConvertTo-ChromiumRecord -Browser $Browser -ProfileDir $profileDir -ExtId $extId `
                            -Entry $entry -InstallDir $installDir))
            }
        } catch {
            $state = 'error'
        }
        $profiles.Add([pscustomobject]@{ ProfileDir = $profileDir; ReadState = $state })
        if ($state -notin @('ok', 'absent') -and $result.ReadState -eq 'ok') { $result.ReadState = $state }
    }

    $result.ProfileCount = $profiles.Count
    $result.StubsSkipped = $stubs
    $result.Profiles = $profiles.ToArray()
    $result.Extensions = $records.ToArray()
    return $result
}
