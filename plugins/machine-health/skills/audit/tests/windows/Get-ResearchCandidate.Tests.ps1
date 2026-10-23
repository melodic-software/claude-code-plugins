#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/Get-ResearchCandidate.ps1, which picks the new findings a
scheduled audit researches.

.DESCRIPTION
The rule, from the script help: a candidate is an item whose key is in latest.json's
new_finding_keys, of kind startup, task, ext, listener, process or detection, a process
only at WARN or CRIT, one per kind and title, ordered CRIT, WARN, INFO, other, then by
check order; at most -Max of them. Every other new key is listed in not_researched, in
latest.json order. The expected lists below are worked out by hand from that rule.
#>

BeforeAll {
    . "$PSScriptRoot\..\helpers\Initialize-CheckSuite.ps1"
    $script:Script = Join-Path $script:SkillRoot 'scripts\windows\Get-ResearchCandidate.ps1'

    $script:Keys = @{
        E1 = 'ext:00000000000000e1'; E2 = 'ext:00000000000000e2'
        L1 = 'listener:00000000000000a1'; L2 = 'listener:00000000000000a2'
        P1 = 'process:00000000000000b1'; P2 = 'process:00000000000000b2'
        T1 = 'task:00000000000000c1'; A1 = 'app:00000000000000d1'
        S1 = 'startup:00000000000000f1'
    }
    function Get-FixtureItem([string] $Name, [string] $Severity, [string] $Title) {
        [ordered]@{ key = $script:Keys[$Name]; severity = $Severity; muted = $false; title = $Title }
    }
    # Eight new keys: two ext, two listeners with one title, an INFO and a WARN process, a task
    # and an app. startup-items also lists S1, which is not new.
    $script:Checks = @(
        [ordered]@{ id = 'browser-extensions'; severity = 'WARN'; detail = @{ items = @(
                    (Get-FixtureItem -Name 'E1' -Severity 'WARN' -Title 'Ext One'), (Get-FixtureItem -Name 'E2' -Severity 'INFO' -Title 'Ext Two')) } }
        [ordered]@{ id = 'network-listeners'; severity = 'INFO'; detail = @{ items = @(
                    (Get-FixtureItem -Name 'L1' -Severity 'INFO' -Title 'node.exe TCP'), (Get-FixtureItem -Name 'L2' -Severity 'INFO' -Title 'node.exe TCP')) } }
        [ordered]@{ id = 'top-processes'; severity = 'WARN'; detail = @{ items = @(
                    (Get-FixtureItem -Name 'P1' -Severity 'INFO' -Title 'quiet.exe'), (Get-FixtureItem -Name 'P2' -Severity 'WARN' -Title 'busy.exe')) } }
        [ordered]@{ id = 'startup-items'; severity = 'CRIT'; detail = @{ items = @(
                    (Get-FixtureItem -Name 'S1' -Severity 'CRIT' -Title 'Old Run key'), (Get-FixtureItem -Name 'T1' -Severity 'CRIT' -Title 'Updater task')) } }
        [ordered]@{ id = 'app-last-use'; severity = 'INFO'; detail = @{ items = @(Get-FixtureItem -Name 'A1' -Severity 'INFO' -Title 'Some App') } }
    )
    $script:AllNew = @('E1', 'E2', 'L1', 'L2', 'P1', 'P2', 'T1', 'A1' | ForEach-Object { $script:Keys[$_] })

    function Invoke-Candidate([string[]] $NewKeys, [int] $Max = 0, [switch] $NoField) {
        $latest = [ordered]@{ run_id = '2026-10-01T09:00:00.0000000+00:00'; checks = $script:Checks }
        if (-not $NoField) { $latest['new_finding_keys'] = @($NewKeys) }
        $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('n') + '.json')
        $latest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding utf8
        $extra = $Max ? @('-Max', $Max) : @()
        $out = & pwsh -NoProfile -NonInteractive -File $script:Script -LatestPath $path @extra
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Json = ($out -join "`n") }
    }
    $script:Pick = { param($Json, $List) @(([System.Text.Json.Nodes.JsonNode]::Parse($Json))[$List].AsArray() | ForEach-Object { $_['key'].GetValue[string]() }) }
}

Describe 'Get-ResearchCandidate' -Tag 'lib' {
    It 'picks five candidates worst first and lists the duplicate listener, the INFO process and the app as not researched' {
        $r = Invoke-Candidate $script:AllNew

        $r.ExitCode | Should -Be 0
        & $script:Pick $r.Json 'candidates' | Should -Be @('T1', 'E1', 'P2', 'E2', 'L1' | ForEach-Object { $script:Keys[$_] })
        & $script:Pick $r.Json 'not_researched' | Should -Be @('L2', 'P1', 'A1' | ForEach-Object { $script:Keys[$_] })
    }

    It 'keeps the duplicate listener, the INFO process and the app out under a cap the fixture never reaches' {
        $r = Invoke-Candidate $script:AllNew -Max 50

        & $script:Pick $r.Json 'candidates' | Should -Be @('T1', 'E1', 'P2', 'E2', 'L1' | ForEach-Object { $script:Keys[$_] })
        & $script:Pick $r.Json 'not_researched' | Should -Be @('L2', 'P1', 'A1' | ForEach-Object { $script:Keys[$_] })
    }

    It 'gives each candidate its kind, check id and title' {
        $first = ([System.Text.Json.Nodes.JsonNode]::Parse((Invoke-Candidate $script:AllNew).Json))['candidates'][0]

        $first.ToJsonString() | Should -Be ('{"key":"' + $script:Keys.T1 + '","kind":"task","check_id":"startup-items","title":"Updater task"}')
    }

    It 'moves candidates past -Max to not researched, in latest.json order' {
        $r = Invoke-Candidate $script:AllNew -Max 3

        & $script:Pick $r.Json 'candidates' | Should -Be @('T1', 'E1', 'P2' | ForEach-Object { $script:Keys[$_] })
        & $script:Pick $r.Json 'not_researched' | Should -Be @('E2', 'L1', 'L2', 'P1', 'A1' | ForEach-Object { $script:Keys[$_] })
    }

    It 'writes a one-candidate list as a JSON array' {
        $node = [System.Text.Json.Nodes.JsonNode]::Parse((Invoke-Candidate @($script:Keys.E1)).Json)

        $node['candidates'].GetValueKind() | Should -Be 'Array'
        $node['candidates'].Count | Should -Be 1
        $node['not_researched'].ToJsonString() | Should -Be '[]'
    }

    It 'returns two empty lists when <Case>' -ForEach @(
        @{ Case = 'no key is new'; NoField = $false }
        @{ Case = 'latest.json has no new_finding_keys'; NoField = $true }
    ) {
        $r = Invoke-Candidate @() -NoField:$NoField

        $r.ExitCode | Should -Be 0
        $r.Json | ConvertFrom-Json | ConvertTo-Json -Compress | Should -Be '{"candidates":[],"not_researched":[]}'
    }
}
