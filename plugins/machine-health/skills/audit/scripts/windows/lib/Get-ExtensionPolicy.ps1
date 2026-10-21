#Requires -Version 7.4

<#
.SYNOPSIS
Reads the Edge and Chrome extension policies (ExtensionInstallForcelist and
ExtensionSettings) under both HKLM and HKCU and returns plain PolicyEntries
plus a ReadState.

.DESCRIPTION
Each browser's policy key is read in both hives and every row is labeled with
its hive; which hive wins when both are set is not resolved here.

Forcelist values are REG_SZ named 1, 2, 3, ...: only integer-named values are
read, and each is split on the first ';' into the extension id and the
optional update URL. ExtensionSettings is one JSON value; only ids whose
installation mode installs them are returned. Each entry's update URL loses
its query string, and OffStore says whether it names an update source other
than that browser's own store (an entry with no URL uses the store).
DomainJoined comes from Win32_ComputerSystem.PartOfDomain, $null when that
read fails. What the check makes of an off-store entry is its rule.

Read-only, unelevated.
#>

$script:ExtensionPolicyBrowser = @(
    [pscustomobject]@{ Browser = 'edge'; Key = 'SOFTWARE\Policies\Microsoft\Edge'; StoreUpdateUrl = 'https://edge.microsoft.com/extensionwebstorebase/v1/crx' }
    [pscustomobject]@{ Browser = 'chrome'; Key = 'SOFTWARE\Policies\Google\Chrome'; StoreUpdateUrl = 'https://clients2.google.com/service/update2/crx' }
)
$script:ExtensionPolicyHive = [ordered]@{ hklm = 'HKLM:'; hkcu = 'HKCU:' }
$script:ExtensionPolicyInstallModes = @('force_installed', 'normal_installed')

function Get-ExtensionPolicyReadState {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)] [System.Management.Automation.ErrorRecord] $ErrorRecord)

    $ex = $ErrorRecord.Exception
    if ($ex -is [System.Management.Automation.ItemNotFoundException]) { return 'absent' }
    if ($ex -is [System.Security.SecurityException] -or $ex -is [System.UnauthorizedAccessException] -or
        $ErrorRecord.CategoryInfo.Category -eq 'PermissionDenied') { return 'denied' }
    return 'error'
}

function New-PolicyEntry {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure constructor: builds and returns an object, changes no system state.')]
    param(
        [AllowNull()] [string] $ValueName,
        [Parameter(Mandatory = $true)] [string] $ExtId,
        [AllowNull()] [AllowEmptyString()] [string] $UpdateUrl,
        [Parameter(Mandatory = $true)] [string] $StoreUpdateUrl
    )

    $url = if ([string]::IsNullOrWhiteSpace($UpdateUrl)) { $null } else { ($UpdateUrl.Trim() -split '\?', 2)[0] }
    [pscustomobject]@{
        ValueName = if ($ValueName) { $ValueName } else { $null }
        ExtId     = $ExtId.Trim()
        UpdateUrl = $url
        OffStore  = $null -ne $url -and -not [string]::Equals($url, $StoreUpdateUrl, [System.StringComparison]::OrdinalIgnoreCase)
    }
}

function Read-ExtensionPolicyKey {
    <#
    .SYNOPSIS
    Reads one registry key's values as a name -> data map, naming how the read went.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory = $true)] [string] $Path)

    try {
        $props = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
    } catch {
        return [pscustomobject]@{ State = (Get-ExtensionPolicyReadState -ErrorRecord $_); Values = @{} }
    }
    $values = @{}
    if ($null -ne $props) {
        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -like 'PS*') { continue }
            $values[$p.Name] = $p.Value
        }
    }
    return [pscustomobject]@{ State = 'ok'; Values = $values }
}

function Get-ExtensionPolicy {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $domainJoined = $null
    $domainState = 'ok'
    try {
        $domainJoined = [bool](Get-CimInstance -ClassName Win32_ComputerSystem -Property PartOfDomain -ErrorAction Stop).PartOfDomain
    } catch {
        $domainState = Get-ExtensionPolicyReadState -ErrorRecord $_
        if ($domainState -eq 'absent') { $domainState = 'error' }
    }

    $readState = 'ok'
    $rows = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($b in $script:ExtensionPolicyBrowser) {
        foreach ($hive in $script:ExtensionPolicyHive.Keys) {
            $root = "$($script:ExtensionPolicyHive[$hive])\$($b.Key)"

            $forcelistRead = Read-ExtensionPolicyKey -Path "$root\ExtensionInstallForcelist"
            if ($forcelistRead.State -notin @('ok', 'absent') -and $readState -eq 'ok') { $readState = $forcelistRead.State }
            $names = @($forcelistRead.Values.Keys | Where-Object { $_ -match '^\d+$' } | Sort-Object { [long]$_ })
            $forced = foreach ($name in $names) {
                $data = $forcelistRead.Values[$name]
                if ($data -isnot [string] -or [string]::IsNullOrWhiteSpace($data)) { continue }
                $cut = $data.IndexOf(';')
                $extId = ($cut -ge 0 ? $data.Substring(0, $cut) : $data).Trim()
                if (-not $extId) { continue }
                New-PolicyEntry -ValueName $name -ExtId $extId `
                    -UpdateUrl ($cut -ge 0 ? $data.Substring($cut + 1) : $null) -StoreUpdateUrl $b.StoreUpdateUrl
            }
            $rows.Add([pscustomobject]@{
                    Browser = $b.Browser; Hive = $hive; Kind = 'forcelist'
                    Matched = $forcelistRead.State -eq 'ok'; Entries = @($forced)
                })

            $settingsRead = Read-ExtensionPolicyKey -Path $root
            if ($settingsRead.State -notin @('ok', 'absent') -and $readState -eq 'ok') { $readState = $settingsRead.State }
            $settingsText = $settingsRead.Values['ExtensionSettings']
            $settings = $null
            if ($settingsText -is [string] -and $settingsText.Trim()) {
                try {
                    $settings = $settingsText | ConvertFrom-Json -AsHashtable -ErrorAction Stop
                } catch {
                    $settings = $null
                }
                if ($settings -isnot [hashtable] -and $readState -eq 'ok') { $readState = 'error' }
            }
            $installing = if ($settings -is [hashtable]) {
                foreach ($id in $settings.Keys) {
                    $entry = $settings[$id]
                    if ($id -eq '*' -or -not $id.Trim() -or $entry -isnot [hashtable]) { continue }
                    if ([string]$entry['installation_mode'] -notin $script:ExtensionPolicyInstallModes) { continue }
                    $url = if ($entry['update_url'] -is [string]) { $entry['update_url'] } else { $null }
                    New-PolicyEntry -ExtId $id -UpdateUrl $url -StoreUpdateUrl $b.StoreUpdateUrl
                }
            }
            $rows.Add([pscustomobject]@{
                    Browser = $b.Browser; Hive = $hive; Kind = 'extension-settings'
                    Matched = $settings -is [hashtable]; Entries = @($installing)
                })
        }
    }

    return [pscustomobject]@{
        ReadState    = $readState
        DomainState  = $domainState
        DomainJoined = $domainJoined
        Policies     = $rows.ToArray()
    }
}
