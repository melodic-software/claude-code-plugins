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
optional update URL.

On a machine not joined to a domain the browser does not install a forced
extension from outside its own store, so such an entry is 'listed-but-blocked'
rather than 'listed'. Edge treats an entry with no update URL as coming from
the Edge Add-ons store; Chrome leaves such an entry alone too. ExtensionSettings
ids whose installation mode installs them and whose update URL is off the
store are counted the same way. Domain membership is read from
Win32_ComputerSystem.PartOfDomain; when that read fails, no entry is called
blocked and DomainState records the failure.

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

function Test-OffStoreUrl {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()] [AllowEmptyString()] [string] $UpdateUrl,
        [Parameter(Mandatory = $true)] [string] $StoreUpdateUrl
    )
    if ([string]::IsNullOrWhiteSpace($UpdateUrl)) { return $false }
    return -not [string]::Equals($UpdateUrl.Trim(), $StoreUpdateUrl, [System.StringComparison]::OrdinalIgnoreCase)
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
    $blockOffStore = $domainJoined -eq $false

    $readState = 'ok'
    $rows = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($b in $script:ExtensionPolicyBrowser) {
        foreach ($hive in $script:ExtensionPolicyHive.Keys) {
            $root = "$($script:ExtensionPolicyHive[$hive])\$($b.Key)"

            $forcelistRead = Read-ExtensionPolicyKey -Path "$root\ExtensionInstallForcelist"
            if ($forcelistRead.State -notin @('ok', 'absent') -and $readState -eq 'ok') { $readState = $forcelistRead.State }
            $entries = [System.Collections.Generic.List[pscustomobject]]::new()
            $names = @($forcelistRead.Values.Keys | Where-Object { $_ -match '^\d+$' } | Sort-Object { [long]$_ })
            foreach ($name in $names) {
                $data = $forcelistRead.Values[$name]
                if ($data -isnot [string] -or [string]::IsNullOrWhiteSpace($data)) { continue }
                $cut = $data.IndexOf(';')
                $extId = ($cut -ge 0 ? $data.Substring(0, $cut) : $data).Trim()
                $url = $cut -ge 0 ? $data.Substring($cut + 1).Trim() : $null
                if ($url -eq '') { $url = $null }
                $blocked = $blockOffStore -and (Test-OffStoreUrl -UpdateUrl $url -StoreUpdateUrl $b.StoreUpdateUrl)
                $entries.Add([pscustomobject]@{
                        ValueName    = $name
                        ExtId        = $extId
                        UpdateUrl    = $url
                        InstallState = $blocked ? 'listed-but-blocked' : 'listed'
                    })
            }
            $rows.Add([pscustomobject]@{
                    Browser      = $b.Browser
                    Hive         = $hive
                    Kind         = 'forcelist'
                    Entries      = $entries.Count
                    Matched      = $forcelistRead.State -eq 'ok'
                    BlockedCount = @($entries | Where-Object InstallState -eq 'listed-but-blocked').Count
                    Forcelist    = $entries.ToArray()
                })

            $settingsRead = Read-ExtensionPolicyKey -Path $root
            if ($settingsRead.State -notin @('ok', 'absent') -and $readState -eq 'ok') { $readState = $settingsRead.State }
            $settingsText = $settingsRead.Values['ExtensionSettings']
            $installed = 0
            $settingsBlocked = 0
            if ($settingsText -is [string] -and $settingsText.Trim()) {
                try {
                    $settings = $settingsText | ConvertFrom-Json -AsHashtable -ErrorAction Stop
                } catch {
                    $settings = $null
                    if ($readState -eq 'ok') { $readState = 'error' }
                }
                if ($settings -is [hashtable]) {
                    foreach ($id in $settings.Keys) {
                        $entry = $settings[$id]
                        if ($id -eq '*' -or $entry -isnot [hashtable]) { continue }
                        if ([string]$entry['installation_mode'] -notin $script:ExtensionPolicyInstallModes) { continue }
                        $installed++
                        if ($blockOffStore -and (Test-OffStoreUrl -UpdateUrl ([string]$entry['update_url']) -StoreUpdateUrl $b.StoreUpdateUrl)) {
                            $settingsBlocked++
                        }
                    }
                }
            }
            $rows.Add([pscustomobject]@{
                    Browser      = $b.Browser
                    Hive         = $hive
                    Kind         = 'extension-settings'
                    Entries      = $installed
                    Matched      = $settingsText -is [string] -and [bool]$settingsText.Trim()
                    BlockedCount = $settingsBlocked
                    Forcelist    = @()
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
