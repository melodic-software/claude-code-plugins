#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/New-RunSnapshot.ps1: the scheduled-run fields and
Get-NewFindingKey, the per-check baseline diff against the previous latest.json.

.DESCRIPTION
Expected keys are worked out by hand from each fixture under the rule in the
Get-NewFindingKey help: a key is new when this run lists it unmuted under a check
whose previous entry is present and not UNKNOWN or SKIPPED, and that entry lacks it.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'New-RunSnapshot.ps1'

    $script:A = 'ext:000000000000000a'
    $script:B = 'ext:000000000000000b'
    $script:C = 'ext:000000000000000c'
    $script:D = 'task:000000000000000d'
    $script:E = 'ext:000000000000000e'

    function New-FixtureItem([string] $Key, [bool] $Muted = $false) {
        [pscustomobject]@{ key = $Key; severity = 'INFO'; muted = $Muted; title = "item $Key" }
    }
    function New-FixtureCheck([string] $Id, [string] $Severity, [object[]] $Items) {
        [pscustomobject]@{ id = $Id; severity = $Severity; detail = [pscustomobject]@{ items = @($Items) } }
    }
    function Write-Previous([object[]] $Checks) {
        $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('n') + '.json')
        @{ run_id = '2026-09-01T09:00:00.0000000+00:00'; checks = @($Checks) } | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $path -Encoding utf8
        $path
    }
}

Describe 'Get-NewFindingKey' -Tag 'lib' {
    It 'returns only the unmuted key a check with a baseline did not hold before' {
        $previous = Write-Previous @(New-FixtureCheck 'x' 'OK' @((New-FixtureItem $script:A), (New-FixtureItem $script:B)))
        $now = @(
            (New-FixtureCheck 'x' 'WARN' @((New-FixtureItem $script:B), (New-FixtureItem $script:C)))
            (New-FixtureCheck 'y' 'INFO' @(New-FixtureItem $script:D))
        )

        @(Get-NewFindingKey -PreviousPath $previous -Checks $now) | Should -Be @($script:C)
    }

    It 'leaves out a new key that is muted' {
        $previous = Write-Previous @(New-FixtureCheck 'x' 'OK' @(New-FixtureItem $script:A))
        $now = @(New-FixtureCheck 'x' 'OK' @((New-FixtureItem $script:C), (New-FixtureItem $script:E -Muted $true)))

        @(Get-NewFindingKey -PreviousPath $previous -Checks $now) | Should -Be @($script:C)
    }

    It 'takes no baseline from a check whose previous reading was <Severity>' -ForEach @(
        @{ Severity = 'UNKNOWN' }, @{ Severity = 'SKIPPED' }
    ) {
        $previous = Write-Previous @(
            (New-FixtureCheck 'x' $Severity @(New-FixtureItem $script:A))
            (New-FixtureCheck 'y' 'OK' @(New-FixtureItem $script:A))
        )
        $now = @(
            (New-FixtureCheck 'x' 'WARN' @(New-FixtureItem $script:C))
            (New-FixtureCheck 'y' 'WARN' @(New-FixtureItem $script:D))
        )

        @(Get-NewFindingKey -PreviousPath $previous -Checks $now) | Should -Be @($script:D)
    }

    It 'returns an empty list when the previous file is <Case>' -ForEach @(
        @{ Case = 'missing'; Text = $null }
        @{ Case = 'not JSON'; Text = '{ not json' }
    ) {
        $path = Join-Path $TestDrive "previous-$Case.json"
        if ($null -ne $Text) { Set-Content -LiteralPath $path -Value $Text -Encoding utf8 }
        $now = @(New-FixtureCheck 'x' 'WARN' @(New-FixtureItem $script:C))

        @(Get-NewFindingKey -PreviousPath $path -Checks $now).Count | Should -Be 0
    }
}

Describe 'New-RunSnapshot scheduled fields' -Tag 'lib' {
    BeforeAll {
        $script:Base = @{ RunId = '2026-10-01T09:00:00.0000000+00:00'; HostName = 'h'; OsVersion = '10'; Elevated = $false
            RunMode = 'on-demand'; DryRun = $false }
    }

    It 'writes new_finding_keys as a JSON array even when it holds one key, beside discovery_path' {
        $json = New-RunSnapshot @script:Base -NewFindingKeys @($script:C) -DiscoveryPath 'R:/reports/discovery-x.md' |
            ConvertTo-Json -Depth 5
        $node = [System.Text.Json.Nodes.JsonNode]::Parse($json)

        $node['new_finding_keys'].GetValueKind() | Should -Be 'Array'
        $node['new_finding_keys'].ToJsonString() | Should -Be "[`"$script:C`"]"
        $node['discovery_path'].GetValue[string]() | Should -Be 'R:/reports/discovery-x.md'
    }

    It 'writes an empty array when no key is new' {
        $node = [System.Text.Json.Nodes.JsonNode]::Parse((New-RunSnapshot @script:Base -DiscoveryPath 'R:/d.md' | ConvertTo-Json -Depth 5))

        $node['new_finding_keys'].ToJsonString() | Should -Be '[]'
    }

    It 'carries neither field without a discovery path' {
        $snapshot = New-RunSnapshot @script:Base -NewFindingKeys @($script:C)

        $snapshot.Keys | Should -Not -Contain 'new_finding_keys'
        $snapshot.Keys | Should -Not -Contain 'discovery_path'
    }
}
