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

$FailureSummary = 'Browser extension check failed.'
$PassThru = $false
$CheckBody = {
    $browserReads = @(
        Get-ChromiumExtension -Browser 'chrome'
        Get-ChromiumExtension -Browser 'edge'
        Get-FirefoxExtension
    )
    $policy = Get-ExtensionPolicy

    $forcedBy = @{}
    $policyEntries = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $policy.Policies) {
        foreach ($entry in $row.Forcelist) {
            $policyEntries.Add([ordered]@{
                    browser       = $row.Browser
                    hive          = $row.Hive
                    value_name    = $entry.ValueName
                    ext_id        = $entry.ExtId
                    update_url    = $entry.UpdateUrl
                    install_state = $entry.InstallState
                })
            $forcedKey = "$($row.Browser)|$($entry.ExtId)"
            if (-not $forcedBy.ContainsKey($forcedKey)) { $forcedBy[$forcedKey] = $row.Hive }
        }
    }

    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($read in $browserReads) {
        foreach ($ext in $read.Extensions) {
            $highAttention = @(Get-HighAttention -Record $ext)
            $reasons = [System.Collections.Generic.List[string]]::new()
            if ($ext.LocationKind -in $developerKinds) { $reasons.Add("loaded as $($ext.LocationKind)") }
            if ($ext.LocationKind -eq 'store' -and $ext.FromWebstore -eq $false) { $reasons.Add('not from the web store') }
            if ($ext.Signed -eq $false) { $reasons.Add('not signed') }
            if ($ext.ForeignInstall -eq $true) { $reasons.Add('installed by another program') }
            if ($ext.LocationKind -ne 'component' -and $highAttention.Count -gt 0) {
                $reasons.Add("high-attention permissions: $($highAttention -join ', ')")
            }

            $title = if ($ext.Name) { "$($ext.Name) ($($ext.Browser), $($ext.ProfileName))" } else { "$($ext.ExtId) ($($ext.Browser), $($ext.ProfileName))" }
            $items.Add((New-FindingItem -Kind 'ext' -Identity @($ext.Browser, $ext.ProfileDir, $ext.ExtId) `
                        -MutedKeys $MutedKeys -Severity ($reasons.Count -gt 0 ? 'WARN' : 'INFO') -Title $title -Fields @{
                        browser        = $ext.Browser
                        profile        = $ext.ProfileName
                        ext_id         = $ext.ExtId
                        name           = $ext.Name
                        version        = $ext.Version
                        location_code  = $ext.LocationCode
                        location_kind  = $ext.LocationKind
                        from_webstore  = $ext.FromWebstore
                        enabled        = $ext.Enabled
                        high_attention = $highAttention
                        policy_hive    = $forcedBy["$($ext.Browser)|$($ext.ExtId)"]
                        reasons        = @($reasons)
                    }))
        }
    }
    $items = @($items | Sort-Object { $_.browser }, { $_.profile }, { $_.ext_id })

    $readStates = @($browserReads | ForEach-Object { $_.ReadState }) + @($policy.ReadState)
    # Domain membership only decides the blocked label; it cannot hide an extension.
    $severity = Get-UnmutedSeverity -Items $items -ReadState $readStates

    $mutedCount = @($items | Where-Object muted).Count
    $flagged = @($items | Where-Object { -not $_.muted -and $_.severity -eq 'WARN' })
    $blockedCount = ($policy.Policies | Measure-Object -Property BlockedCount -Sum).Sum
    $unreadable = @($browserReads | Where-Object { $_.ReadState -notin @('ok', 'absent') } | ForEach-Object { $_.Browser })
    if ($policy.ReadState -notin @('ok', 'absent')) { $unreadable += 'policy' }

    $summary = "$($items.Count) browser extension(s), $($flagged.Count) flagged, $($policyEntries.Count) forcelist entr$($policyEntries.Count -eq 1 ? 'y' : 'ies')."
    if ($unreadable.Count -gt 0) { $summary += " Could not read: $($unreadable -join ', ')." }

    $detail = @{
        extension_count      = $items.Count
        high_attention_count = @($items | Where-Object { @($_.high_attention).Count -gt 0 }).Count
        stubs_skipped        = [int]($browserReads | Measure-Object -Property StubsSkipped -Sum).Sum
        policy_entry_count   = $policyEntries.Count
        blocked_marker_count = [int]$blockedCount
        items_count          = $items.Count
        muted_count          = $mutedCount
        domain_read_state    = $policy.DomainState
        browsers             = @($browserReads | ForEach-Object {
                [ordered]@{ browser = $_.Browser; profile_count = $_.ProfileCount; read_state = $_.ReadState }
            })
        policy               = @($policy.Policies | ForEach-Object {
                [ordered]@{ browser = $_.Browser; hive = $_.Hive; kind = $_.Kind; entries = $_.Entries; matched = $_.Matched }
            })
        policy_entries       = @($policyEntries)
        items                = $items
    }

    $failure = @{}
    if ($unreadable.Count -gt 0) {
        $failure = @{ RanSuccessfully = $false; ErrorMessage = "Unreadable extension source(s): $($unreadable -join ', ')." }
    }
    $result = New-HealthResult -Id $id -Category $category -Os 'windows' -Severity $severity `
        -Summary $summary -Commands $commands -Detail $detail -NeedsAdmin $false @failure
}
. (Join-Path $PSScriptRoot '..\lib\Invoke-HealthCheckEnvelope.ps1')
