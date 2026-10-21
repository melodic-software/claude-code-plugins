#Requires -Version 7.4

<#
.SYNOPSIS
Reads the extensions installed in every Firefox profile and returns plain
ExtensionRecords plus a ReadState, in the same shape Get-ChromiumExtension
returns.

.DESCRIPTION
Profiles come from profiles.ini; each profile's extensions.json addons[] holds
the installed add-ons. Only type 'extension' is returned (themes, language
packs and dictionaries are not extensions). The extensions.json keys, the
location names and the signedState integers stay inside this file: a record
carries LocationKind, Signed and ForeignInstall instead.

Read-only, unelevated. Firefox has no Chromium location integer, so
LocationCode is $null, and no web-store flag, so FromWebstore is $null.
#>

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

function Get-FirefoxReadState {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)] [System.Management.Automation.ErrorRecord] $ErrorRecord)

    $ex = $ErrorRecord.Exception
    if ($ex -is [System.Management.Automation.ItemNotFoundException]) { return 'absent' }
    if ($ex -is [System.UnauthorizedAccessException] -or $ex.InnerException -is [System.UnauthorizedAccessException] -or
        $ErrorRecord.CategoryInfo.Category -eq 'PermissionDenied') { return 'denied' }
    return 'error'
}

function Read-FirefoxProfileList {
    <#
    .SYNOPSIS
    Parses profiles.ini lines into { DirName, Name, Path } per [Profile*] section.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [AllowEmptyCollection()] [string[]] $Lines = @(),
        [Parameter(Mandatory = $true)] [string] $Root
    )

    $sections = [System.Collections.Generic.List[hashtable]]::new()
    $current = $null
    foreach ($line in $Lines) {
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
        $leaf = Split-Path -Leaf $path
        [pscustomobject]@{
            DirName = $leaf
            Name    = if ($section['Name']) { $section['Name'] } else { $leaf }
            Path    = $path
        }
    }
    return @($profiles)
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
        Extensions   = @()
    }

    try {
        $lines = @(Get-Content -LiteralPath (Join-Path $FirefoxRoot 'profiles.ini') -ErrorAction Stop)
    } catch {
        $result.ReadState = Get-FirefoxReadState -ErrorRecord $_
        return $result
    }

    $records = [System.Collections.Generic.List[pscustomobject]]::new()
    $readState = 'ok'
    foreach ($fxProfile in @(Read-FirefoxProfileList -Lines $lines -Root $FirefoxRoot)) {
        $result.ProfileCount++
        try {
            $text = Get-Content -LiteralPath (Join-Path $fxProfile.Path 'extensions.json') -Raw -ErrorAction Stop
            $db = $text | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        } catch {
            # A profile that never started has no extensions.json: nothing installed there.
            $state = Get-FirefoxReadState -ErrorRecord $_
            if ($state -ne 'absent' -and $readState -eq 'ok') { $readState = $state }
            continue
        }

        foreach ($addon in @($db['addons'])) {
            if ($addon -isnot [hashtable] -or $addon['type'] -ne 'extension') { continue }
            $kind = $script:FirefoxLocationKind[[string]$addon['location']]
            if (-not $kind) { $kind = 'unknown' }
            $locale = if ($addon['defaultLocale'] -is [hashtable]) { $addon['defaultLocale'] } else { @{} }
            $perms = if ($addon['userPermissions'] -is [hashtable]) { $addon['userPermissions'] } else { @{} }
            $signed = $null -ne $addon['signedState'] -and [int]$addon['signedState'] -ge $script:FirefoxSignedFloor

            $records.Add([pscustomobject]@{
                    Browser        = 'firefox'
                    ProfileDir     = $fxProfile.DirName
                    ProfileName    = $fxProfile.Name
                    ExtId          = [string]$addon['id']
                    Name           = if ($locale['name']) { [string]$locale['name'] } else { $null }
                    Version        = if ($addon['version']) { [string]$addon['version'] } else { $null }
                    LocationCode   = $null
                    LocationKind   = $kind
                    FromWebstore   = $null
                    Enabled        = [bool]$addon['active']
                    ApiPermissions = [string[]]@($perms['permissions'] | Where-Object { $_ -is [string] })
                    HostPatterns   = [string[]]@($perms['origins'] | Where-Object { $_ -is [string] } | Sort-Object -Unique)
                    Signed         = $signed
                    ForeignInstall = [bool]$addon['foreignInstall']
                })
        }
    }

    $result.ReadState = $readState
    $result.Extensions = $records.ToArray()
    return $result
}
