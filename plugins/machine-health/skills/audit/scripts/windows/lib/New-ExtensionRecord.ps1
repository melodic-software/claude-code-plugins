#Requires -Version 7.4

<#
.SYNOPSIS
The ExtensionRecord constructor both browser adapters return, and the one
size-capped reader they use for browser files.

.DESCRIPTION
An ExtensionRecord is plain data: no pref key, location integer or JSON
object crosses into the check. LocationKind is one of the set declared here.
PathIsAbsolute and UnderBrowserInstall are Chromium facts ($null for
Firefox): whether the settings entry's install path is absolute, and whether
it lies under the browser's own install folder ($null when that folder could
not be read).

Read-BrowserFile refuses a file above the held size before reading it, and
Read-BrowserJsonFile also requires the JSON root to be an object, so one
oversized or malformed profile file is a ReadState, not a crash.
#>

$script:ExtensionLocationKinds = @('store', 'policy', 'unpacked', 'command-line', 'external', 'component', 'unknown')
# Judgment: well above any real Preferences or extensions.json, small enough to parse safely.
$script:BrowserFileMaxBytes = 64MB

function New-ExtensionRecord {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure constructor: builds and returns an object, changes no system state.')]
    param(
        [Parameter(Mandatory = $true)] [ValidateSet('chrome', 'edge', 'firefox')] [string] $Browser,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [string] $ProfileDir,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [string] $ExtId,
        [AllowNull()] [AllowEmptyString()] [string] $Name,
        [AllowNull()] [AllowEmptyString()] [string] $Version,
        [AllowNull()] [Nullable[int]] $LocationCode,
        [Parameter(Mandatory = $true)] [string] $LocationKind,
        [AllowNull()] [Nullable[bool]] $FromWebstore,
        [AllowNull()] [Nullable[bool]] $Enabled,
        [AllowEmptyCollection()] [string[]] $ApiPermissions = @(),
        [AllowEmptyCollection()] [string[]] $HostPatterns = @(),
        [AllowNull()] [Nullable[bool]] $PathIsAbsolute,
        [AllowNull()] [Nullable[bool]] $UnderBrowserInstall,
        [AllowNull()] [Nullable[bool]] $Signed,
        [AllowNull()] [Nullable[bool]] $ForeignInstall
    )

    if ($LocationKind -cnotin $script:ExtensionLocationKinds) {
        throw "New-ExtensionRecord: LocationKind '$LocationKind' is not one of $($script:ExtensionLocationKinds -join ', ')."
    }
    [pscustomobject]@{
        Browser             = $Browser
        ProfileDir          = $ProfileDir
        ExtId               = $ExtId
        Name                = if ($Name) { $Name } else { $null }
        Version             = if ($Version) { $Version } else { $null }
        LocationCode        = $LocationCode
        LocationKind        = $LocationKind
        FromWebstore        = $FromWebstore
        Enabled             = $Enabled
        ApiPermissions      = [string[]]@($ApiPermissions)
        HostPatterns        = [string[]]@($HostPatterns | Sort-Object -Unique)
        PathIsAbsolute      = $PathIsAbsolute
        UnderBrowserInstall = $UnderBrowserInstall
        Signed              = $Signed
        ForeignInstall      = $ForeignInstall
    }
}

function Get-BrowserReadState {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)] [System.Management.Automation.ErrorRecord] $ErrorRecord)

    $ex = $ErrorRecord.Exception
    if ($ex -is [System.Management.Automation.ItemNotFoundException]) { return 'absent' }
    if ($ex -is [System.UnauthorizedAccessException] -or $ex.InnerException -is [System.UnauthorizedAccessException] -or
        $ErrorRecord.CategoryInfo.Category -eq 'PermissionDenied') { return 'denied' }
    return 'error'
}

function Read-BrowserFile {
    <#
    .SYNOPSIS
    Reads one browser file's text after checking its size; names how the read went.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory = $true)] [string] $Path)

    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ($item.Length -gt $script:BrowserFileMaxBytes) {
            return [pscustomobject]@{ State = 'error'; Text = $null }
        }
        return [pscustomobject]@{ State = 'ok'; Text = (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop) }
    } catch {
        return [pscustomobject]@{ State = (Get-BrowserReadState -ErrorRecord $_); Text = $null }
    }
}

function Read-BrowserJsonFile {
    <#
    .SYNOPSIS
    Reads one browser JSON file whose root must be an object.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory = $true)] [string] $Path)

    $read = Read-BrowserFile -Path $Path
    if ($read.State -ne 'ok') { return [pscustomobject]@{ State = $read.State; Data = $null } }
    try {
        $data = $read.Text | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    } catch {
        return [pscustomobject]@{ State = 'error'; Data = $null }
    }
    if ($data -isnot [hashtable]) { return [pscustomobject]@{ State = 'error'; Data = $null } }
    return [pscustomobject]@{ State = 'ok'; Data = $data }
}
