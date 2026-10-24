#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/New-RunSnapshot.ps1: the scheduled-run fields and
Get-NewFindingKey, the per-check baseline diff against the previous latest.json.

.DESCRIPTION
Expected keys are worked out by hand from each fixture under the rule in the
Get-NewFindingKey help: a key is new when this run lists it unmuted under a check
whose previous entry lists detail.items and is not SKIPPED, and that entry lacks it.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'New-RunSnapshot.ps1'

    $script:A = 'ext:000000000000000a'
    $script:B = 'ext:000000000000000b'
    $script:C = 'ext:000000000000000c'
    $script:D = 'task:000000000000000d'
    $script:E = 'ext:000000000000000e'

    function Get-FixtureItem([string] $Key, [bool] $Muted = $false) {
        [pscustomobject]@{ key = $Key; severity = 'INFO'; muted = $Muted; title = "item $Key" }
    }
    function Get-FixtureCheck([string] $Id, [string] $Severity, [object[]] $Items) {
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
        $previous = Write-Previous @(Get-FixtureCheck -Id 'x' -Severity 'OK' -Items @((Get-FixtureItem $script:A), (Get-FixtureItem $script:B)))
        $now = @(
            (Get-FixtureCheck -Id 'x' -Severity 'WARN' -Items @((Get-FixtureItem $script:B), (Get-FixtureItem $script:C)))
            (Get-FixtureCheck -Id 'y' -Severity 'INFO' -Items @(Get-FixtureItem $script:D))
        )

        @(Get-NewFindingKey -PreviousPath $previous -Checks $now) | Should -Be @($script:C)
    }

    It 'leaves out a new key that is muted' {
        $previous = Write-Previous @(Get-FixtureCheck -Id 'x' -Severity 'OK' -Items @(Get-FixtureItem $script:A))
        $now = @(Get-FixtureCheck -Id 'x' -Severity 'OK' -Items @((Get-FixtureItem $script:C), (Get-FixtureItem $script:E -Muted $true)))

        @(Get-NewFindingKey -PreviousPath $previous -Checks $now) | Should -Be @($script:C)
    }

    It 'takes no baseline from a check that was SKIPPED before' {
        $previous = Write-Previous @(
            (Get-FixtureCheck -Id 'x' -Severity 'SKIPPED' -Items @(Get-FixtureItem $script:A))
            (Get-FixtureCheck -Id 'y' -Severity 'OK' -Items @(Get-FixtureItem $script:A))
        )
        $now = @(
            (Get-FixtureCheck -Id 'x' -Severity 'WARN' -Items @(Get-FixtureItem $script:C))
            (Get-FixtureCheck -Id 'y' -Severity 'WARN' -Items @(Get-FixtureItem $script:D))
        )

        @(Get-NewFindingKey -PreviousPath $previous -Checks $now) | Should -Be @($script:D)
    }

    It 'takes no baseline from a previous entry that listed no items, such as a timed-out check' {
        $previous = Write-Previous @(
            [pscustomobject]@{ id = 'x'; severity = 'UNKNOWN'; detail = [pscustomobject]@{ reason = 'timeout' } }
            (Get-FixtureCheck -Id 'y' -Severity 'OK' -Items @(Get-FixtureItem $script:A))
        )
        $now = @(
            (Get-FixtureCheck -Id 'x' -Severity 'WARN' -Items @(Get-FixtureItem $script:C))
            (Get-FixtureCheck -Id 'y' -Severity 'WARN' -Items @(Get-FixtureItem $script:D))
        )

        @(Get-NewFindingKey -PreviousPath $previous -Checks $now) | Should -Be @($script:D)
    }

    It 'keeps the baseline of an UNKNOWN check that still listed items, as an unelevated partial read does' {
        $previous = Write-Previous @(Get-FixtureCheck -Id 'x' -Severity 'UNKNOWN' -Items @(Get-FixtureItem $script:A))
        $now = @(Get-FixtureCheck -Id 'x' -Severity 'UNKNOWN' -Items @((Get-FixtureItem $script:A), (Get-FixtureItem $script:C)))

        @(Get-NewFindingKey -PreviousPath $previous -Checks $now) | Should -Be @($script:C)
    }

    It 'returns an empty list when the previous file is <Case>' -ForEach @(
        @{ Case = 'missing'; Text = $null }
        @{ Case = 'not JSON'; Text = '{ not json' }
    ) {
        $path = Join-Path $TestDrive "previous-$Case.json"
        if ($null -ne $Text) { Set-Content -LiteralPath $path -Value $Text -Encoding utf8 }
        $now = @(Get-FixtureCheck -Id 'x' -Severity 'WARN' -Items @(Get-FixtureItem $script:C))

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
