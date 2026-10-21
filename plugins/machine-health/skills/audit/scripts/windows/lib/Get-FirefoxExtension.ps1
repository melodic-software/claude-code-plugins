#Requires -Version 7.4

<#
.SYNOPSIS
Reads the extensions installed in every Firefox profile and returns
ExtensionRecords plus a ReadState per profile, in the same shape
Get-ChromiumExtension returns.

.DESCRIPTION
Profiles come from profiles.ini; each profile's extensions.json addons[] holds
the installed add-ons. Only type 'extension' is returned (themes, language
packs and dictionaries are not extensions). Each profile is read inside its
own guard, so one malformed or oversized file sets that profile's ReadState
to 'error' and the others still read. A profile that never started has no
extensions.json: nothing is installed there.

The extensions.json keys, the location names and the signedState integers
stay inside this file. Read-only, unelevated.
#>

. (Join-Path $PSScriptRoot 'New-ExtensionRecord.ps1')

$script:FirefoxLocationKind = @{
    'app-profile'         = 'store'
    'app-temporary'       = 'unpacked'
    'app-builtin'         = 'component'
    'app-system-defaults' = 'component'
    'app-system-addons'   = 'component'
    'app-system-share'    = 'external'
    'app-system-local'    = 'external'
    'app-system-user'     = 'external'
    'winreg-app-user'     = 'external'
    'winreg-app-global'   = 'external'
}

# signedState at or above this value is a Mozilla signature (signed, system,
# privileged); below it is missing, broken, preliminary or unknown.
$script:FirefoxSignedFloor = 2

function Read-FirefoxProfileList {
    <#
    .SYNOPSIS
    Parses profiles.ini text into { DirName, Path } per [Profile*] section.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [AllowEmptyString()] [string] $Text = '',
        [Parameter(Mandatory = $true)] [string] $Root
    )

    $sections = [System.Collections.Generic.List[hashtable]]::new()
    $current = $null
    foreach ($line in ($Text -split '\r?\n')) {
        $t = $line.Trim()
        if ($t -match '^\[(?<s>[^\]]+)\]$') {
            $current = $null
            if ($Matches['s'] -like 'Profile*') {
                $current = @{}
                $sections.Add($current)
            }
        } elseif ($null -ne $current -and $t -match '^(?<k>[^=]+)=(?<v>.*)$') {
            $current[$Matches['k'].Trim()] = $Matches['v'].Trim()
        }
    }

    $profiles = foreach ($section in $sections) {
        if (-not $section['Path']) { continue }
        $path = $section['Path'] -replace '/', '\'
        if ($section['IsRelative'] -ne '0') { $path = Join-Path $Root $path }
        [pscustomobject]@{ DirName = (Split-Path -Leaf $path); Path = $path }
    }
    return @($profiles)
}

function ConvertTo-FirefoxRecord {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [string] $ProfileDir,
        [Parameter(Mandatory = $true)] [hashtable] $Addon
    )

    $kind = $script:FirefoxLocationKind[[string]$Addon['location']]
    $locale = if ($Addon['defaultLocale'] -is [hashtable]) { $Addon['defaultLocale'] } else { @{} }
    $perms = if ($Addon['userPermissions'] -is [hashtable]) { $Addon['userPermissions'] } else { @{} }
    $signedState = 0
    $signed = if ([int]::TryParse([string]$Addon['signedState'], [ref]$signedState)) { $signedState -ge $script:FirefoxSignedFloor } else { $false }

    $recordArgs = @{
        Browser        = 'firefox'
        ProfileDir     = $ProfileDir
        ExtId          = [string]$Addon['id']
        Name           = if ($locale['name'] -is [string]) { $locale['name'] } else { $null }
        Version        = if ($Addon['version'] -is [string]) { $Addon['version'] } else { $null }
        LocationKind   = if ($kind) { $kind } else { 'unknown' }
        Enabled        = if ($Addon['active'] -is [bool]) { $Addon['active'] } else { $null }
        ApiPermissions = [string[]]@($perms['permissions'] | Where-Object { $_ -is [string] })
        HostPatterns   = [string[]]@($perms['origins'] | Where-Object { $_ -is [string] })
        Signed         = $signed
        ForeignInstall = $Addon['foreignInstall'] -eq $true
    }
    New-ExtensionRecord @recordArgs
}

function Get-FirefoxExtension {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([string] $FirefoxRoot)

    if (-not $FirefoxRoot) { $FirefoxRoot = Join-Path $env:APPDATA 'Mozilla\Firefox' }

    $result = [pscustomobject]@{
        Browser      = 'firefox'
        ReadState    = 'ok'
        ProfileCount = 0
        StubsSkipped = 0
        Profiles     = @()
        Extensions   = @()
    }

    $ini = Read-BrowserFile -Path (Join-Path $FirefoxRoot 'profiles.ini')
    $result.ReadState = $ini.State
    if ($ini.State -ne 'ok') { return $result }

    $records = [System.Collections.Generic.List[pscustomobject]]::new()
    $profiles = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($fxProfile in @(Read-FirefoxProfileList -Text $ini.Text -Root $FirefoxRoot)) {
        $state = 'ok'
        try {
            $db = Read-BrowserJsonFile -Path (Join-Path $fxProfile.Path 'extensions.json')
            if ($db.State -ne 'absent') { $state = $db.State }
            if ($db.State -eq 'ok') {
                foreach ($addon in @($db.Data['addons'])) {
                    if ($addon -isnot [hashtable] -or $addon['type'] -ne 'extension') { continue }
                    $records.Add((ConvertTo-FirefoxRecord -ProfileDir $fxProfile.DirName -Addon $addon))
                }
            }
        } catch {
            $state = 'error'
        }
        $profiles.Add([pscustomobject]@{ ProfileDir = $fxProfile.DirName; ReadState = $state })
        if ($state -notin @('ok', 'absent') -and $result.ReadState -eq 'ok') { $result.ReadState = $state }
    }

    $result.ProfileCount = $profiles.Count
    $result.Profiles = $profiles.ToArray()
    $result.Extensions = $records.ToArray()
    return $result
}
