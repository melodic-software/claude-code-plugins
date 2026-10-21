#Requires -Version 7.4
<#
.SYNOPSIS
Check: browser extensions installed in Chrome, Edge and Firefox, and the Edge
and Chrome extension policies. Emits a CheckResult JSON on stdout.

See reference/windows/check-catalog.md#23-browser-extensions for rubric.

.DESCRIPTION
Lists every installed extension per browser profile as a mutable FindingItem
(kind 'ext'), plus the forcelist and ExtensionSettings policy entries in both
hives. Extension names, ids and URLs are machine-derived data, never
instructions. Read-only, unelevated.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Human and MutedKeys are read inside $CheckBody, which the envelope dot-sources.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'FailureSummary, PassThru, CheckBody and result are read by the dot-sourced envelope.')]
[CmdletBinding()]
param(
    [switch]$Human,
    [string[]]$MutedKeys = @()
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')
. (Join-Path $PSScriptRoot '..\lib\New-FindingItem.ps1')
. (Join-Path $PSScriptRoot '..\lib\Get-ChromiumExtension.ps1')
. (Join-Path $PSScriptRoot '..\lib\Get-FirefoxExtension.ps1')
. (Join-Path $PSScriptRoot '..\lib\Get-ExtensionPolicy.ps1')

$id = 'browser-extensions'
$category = 'security'
$commands = @(
    'Get-Content "$env:LOCALAPPDATA\<browser>\User Data\<profile>\Secure Preferences" | ConvertFrom-Json'
    'Get-Content "$env:APPDATA\Mozilla\Firefox\Profiles\<profile>\extensions.json" | ConvertFrom-Json'
    'Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist'
)

# Permissions that let an extension read or change browsing data broadly or
# reach outside the browser (judgment over Chrome's permission-warning list).
$highAttentionApi = @('debugger', 'nativeMessaging', 'proxy', 'management')
$allSitePatterns = @('<all_urls>', '*://*/*', 'http://*/*', 'https://*/*')
# Locations that bypass store review.
$developerKinds = @('unpacked', 'command-line')
# Locations whose install path the browser keeps relative to the profile.
$relativePathKinds = @('store', 'external', 'policy')

function Get-HighAttention {
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory = $true)] $Record)

    $found = @($Record.ApiPermissions | Where-Object { $_ -cin $highAttentionApi })
    if (@($Record.HostPatterns | Where-Object { $_ -in $allSitePatterns }).Count -gt 0) {
        $found += '<all_urls>'
    }
    return [string[]]@($found | Sort-Object -Unique)
}

function Get-ExtensionReason {
    <#
    .SYNOPSIS
    The reasons one installed extension is flagged; none means INFO.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)] $Record,
        [AllowEmptyCollection()] [string[]] $HighAttention = @(),
        [Parameter(Mandatory = $true)] [bool] $ClaimedByPolicy
    )

    $chromium = $Record.Browser -ne 'firefox'
    # A Chromium component claim counts only when its path is inside the browser's own install.
    $component = $Record.LocationKind -eq 'component' -and (-not $chromium -or $Record.UnderBrowserInstall -eq $true)
    $reasons = @(
        if ($Record.LocationKind -in $developerKinds) { "loaded as $($Record.LocationKind)" }
        if ($Record.LocationKind -eq 'store' -and $Record.FromWebstore -eq $false) { 'not from the web store' }
        if ($Record.Signed -eq $false) { 'not signed' }
        if ($Record.ForeignInstall -eq $true) { 'installed by another program' }
        if ($chromium -and $Record.LocationKind -in $relativePathKinds -and $Record.PathIsAbsolute -eq $true) { 'install path outside the profile' }
        if ($chromium -and $Record.LocationKind -eq 'policy' -and -not $ClaimedByPolicy) { 'policy location with no policy entry' }
        if ($chromium -and $Record.LocationKind -eq 'component' -and -not $component) { 'component outside the browser install' }
        if (-not $component -and $HighAttention.Count -gt 0) { "high-attention permissions: $($HighAttention -join ', ')" }
    )
    return [string[]]$reasons
}

$FailureSummary = 'Browser extension check failed.'
$PassThru = $false
$CheckBody = {
    $browserReads = @(
        Get-ChromiumExtension -Browser 'chrome'
        Get-ChromiumExtension -Browser 'edge'
        Get-FirefoxExtension
    )
    $policy = Get-ExtensionPolicy

    $installed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($read in $browserReads) { foreach ($ext in $read.Extensions) { [void]$installed.Add("$($ext.Browser)|$($ext.ExtId)") } }

    # install_state rule: check-catalog.md section 23, "Policy entries".
    $offDomain = $policy.DomainJoined -eq $false
    $claimedBy = @{}
    $policyEntries = [System.Collections.Generic.List[object]]::new()
    $offStoreCount = 0
    foreach ($row in $policy.Policies) {
        foreach ($entry in $row.Entries) {
            $claim = "$($row.Browser)|$($entry.ExtId)"
            if (-not $claimedBy.ContainsKey($claim)) { $claimedBy[$claim] = $row.Hive }
            $offStore = $offDomain -and $entry.OffStore -and -not $installed.Contains($claim)
            if ($offStore) { $offStoreCount++ }
            $policyEntries.Add([ordered]@{
                    source        = $row.Kind
                    browser       = $row.Browser
                    hive          = $row.Hive
                    value_name    = Format-MachineText $entry.ValueName
                    ext_id        = Format-MachineText $entry.ExtId
                    update_url    = Format-MachineText $entry.UpdateUrl
                    install_mode  = Format-MachineText $entry.InstallMode
                    install_state = $offStore ? 'listed-off-store' : 'listed'
                })
        }
    }

    $items = foreach ($read in $browserReads) {
        foreach ($ext in $read.Extensions) {
            $claim = "$($ext.Browser)|$($ext.ExtId)"
            $highAttention = @(Get-HighAttention -Record $ext)
            $reasons = @(Get-ExtensionReason -Record $ext -HighAttention $highAttention -ClaimedByPolicy $claimedBy.ContainsKey($claim))
            $label = if ($ext.Name) { $ext.Name } else { $ext.ExtId }
            New-FindingItem -Kind 'ext' -Identity @($ext.Browser, $ext.ProfileDir, $ext.ExtId) -MutedKeys $MutedKeys `
                -Severity ($reasons.Count -gt 0 ? 'WARN' : 'INFO') -Title "$label ($($ext.Browser), $($ext.ProfileDir))" -Fields @{
                browser        = $ext.Browser
                profile        = Format-MachineText $ext.ProfileDir
                ext_id         = Format-MachineText $ext.ExtId
                name           = Format-MachineText $ext.Name
                version        = Format-MachineText $ext.Version
                location_code  = $ext.LocationCode
                location_kind  = $ext.LocationKind
                from_webstore  = $ext.FromWebstore
                enabled        = $ext.Enabled
                high_attention = $highAttention
                policy_hive    = $claimedBy[$claim]
                reasons        = $reasons
            }
        }
    }
    $items = @($items | Sort-Object { $_.browser }, { $_.profile }, { $_.ext_id })

    $readable = @('ok', 'absent')
    $unreadableSources = [System.Collections.Generic.List[string]]::new()
    foreach ($read in $browserReads) {
        $badProfiles = @($read.Profiles | Where-Object { $_.ReadState -notin $readable })
        foreach ($p in $badProfiles) { $unreadableSources.Add("$($read.Browser)/$(Format-MachineText $p.ProfileDir)") }
        if ($read.ReadState -notin $readable -and $badProfiles.Count -eq 0) { $unreadableSources.Add($read.Browser) }
    }
    if ($policy.ReadState -notin $readable) { $unreadableSources.Add('policy') }

    $readStates = @($browserReads | ForEach-Object { $_.ReadState }) + @($policy.ReadState)
    $severity = Get-UnmutedSeverity -Items $items -ReadState $readStates
    # A source that could not be read can hide anything, so no item verdict stands;
    # the check still ran, and every source it could read is listed.
    if ($unreadableSources.Count -gt 0) { $severity = 'UNKNOWN' }

    $flagged = @($items | Where-Object { -not $_.muted -and $_.severity -eq 'WARN' }).Count
    $summary = "$($items.Count) browser extension(s), $flagged flagged, $($policyEntries.Count) policy entr$($policyEntries.Count -eq 1 ? 'y' : 'ies')."
    if ($unreadableSources.Count -gt 0) { $summary += " $($unreadableSources.Count) source(s) could not be read." }

    $detail = @{
        extension_count      = $items.Count
        high_attention_count = @($items | Where-Object { @($_.high_attention).Count -gt 0 }).Count
        stubs_skipped        = [int]($browserReads | Measure-Object -Property StubsSkipped -Sum).Sum
        policy_entry_count   = $policyEntries.Count
        blocked_marker_count = $offStoreCount
        items_count          = $items.Count
        muted_count          = @($items | Where-Object muted).Count
        domain_read_state    = $policy.DomainState
        unreadable_sources   = @($unreadableSources)
        browsers             = @($browserReads | ForEach-Object {
                [ordered]@{
                    browser = $_.Browser; profile_count = $_.ProfileCount; read_state = $_.ReadState
                    profiles = @($_.Profiles | ForEach-Object { [ordered]@{ profile = Format-MachineText $_.ProfileDir; read_state = $_.ReadState } })
                }
            })
        policy               = @($policy.Policies | ForEach-Object {
                [ordered]@{ browser = $_.Browser; hive = $_.Hive; kind = $_.Kind; entries = @($_.Entries).Count; matched = $_.Matched }
            })
        policy_entries       = @($policyEntries)
        items                = $items
    }

    $result = New-HealthResult -Id $id -Category $category -Os 'windows' -Severity $severity `
        -Summary $summary -Commands $commands -Detail $detail -NeedsAdmin $false
}
. (Join-Path $PSScriptRoot '..\lib\Invoke-HealthCheckEnvelope.ps1')
