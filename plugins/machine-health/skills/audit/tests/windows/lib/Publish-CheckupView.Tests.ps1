#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Publish-CheckupView.ps1 -- the orchestrator's
decision page step: build through node, prune only after a built page, and
note the outcome in the report. node is mocked at Invoke-NativeCommand.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Publish-CheckupView.ps1'

    $script:Current = '2026-01-14T000000000Z'
    function Get-Stamp([int] $N) { '2026-01-{0:D2}T000000000Z' -f $N }
    function Get-NodeResult([string] $Status) {
        [pscustomobject]@{ status = $Status; source = 'node'; exit_code = ($Status -eq 'NonZero' ? 1 : 0); output = ''; error = $null }
    }
}

Describe 'Publish-CheckupView' -Tag 'lib' {
    BeforeEach {
        $script:StateBase = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $script:Views = Join-Path $script:StateBase 'views'
        New-Item -ItemType Directory -Path $script:Views -Force | Out-Null
        # Runs 1..14 complete, run 14 the current one: a prune deletes runs 1 and 2.
        foreach ($n in 1..14) {
            foreach ($suffix in '.html', '.json', '.ids.json') {
                Set-Content -LiteralPath (Join-Path $script:Views "checkup-$(Get-Stamp $n)$suffix") -Value 'x'
            }
        }
        $script:Report = Join-Path $script:StateBase 'health.md'
        Set-Content -LiteralPath $script:Report -Value '# report'
        $script:Oldest = Join-Path $script:Views "checkup-$(Get-Stamp 1).html"
        Mock Write-MachineHealthLog {}
        $script:Splat = @{
            StateBase = $script:StateBase; LatestPath = (Join-Path $script:StateBase 'latest.json')
            RunStamp = $script:Current; ReportPath = $script:Report
        }
    }

    It 'with node absent logs checkup_view_skipped node_missing, prunes nothing and says so in the report' {
        Mock Invoke-NativeCommand { Get-NodeResult 'Absent' }

        Publish-CheckupView @script:Splat -StateWritable $true | Should -BeNullOrEmpty

        Should -Invoke Write-MachineHealthLog -Times 1 -Exactly -ParameterFilter { $Message -eq 'checkup_view_skipped node_missing' }
        $script:Oldest | Should -Exist
        Get-Content -LiteralPath $script:Report -Raw | Should -Match '## Decision page[\s\S]*Node\.js was not found'
    }

    It 'with a failed build prunes nothing and points the report at the log' {
        Mock Invoke-NativeCommand { Get-NodeResult 'NonZero' }

        Publish-CheckupView @script:Splat -StateWritable $true | Should -BeNullOrEmpty

        $script:Oldest | Should -Exist
        Should -Invoke Write-MachineHealthLog -Times 1 -Exactly -ParameterFilter { $Message -like 'checkup_view_failed status=NonZero exit=1*' }
        Get-Content -LiteralPath $script:Report -Raw | Should -Match 'the page build failed'
    }

    It 'with a built page prunes the older runs and returns the page path' {
        Mock Invoke-NativeCommand { Get-NodeResult 'Ok' }

        $page = Publish-CheckupView @script:Splat -StateWritable $true

        $page | Should -Be (Join-Path $script:Views "checkup-$script:Current.html")
        foreach ($n in 1, 2) { Join-Path $script:Views "checkup-$(Get-Stamp $n).ids.json" | Should -Not -Exist }
        Join-Path $script:Views "checkup-$(Get-Stamp 3).ids.json" | Should -Exist
        Should -Invoke Write-MachineHealthLog -Times 1 -Exactly -ParameterFilter { $Message -eq 'checkup_view_pruned files=6' }
        Get-Content -LiteralPath $script:Report -Raw | Should -Match ([regex]::Escape($page))
    }

    It 'passes node the builder, the run and the shipped remediation ids' {
        Mock Invoke-NativeCommand { Get-NodeResult 'NonZero' }

        Publish-CheckupView @script:Splat -StateWritable $true | Out-Null

        Should -Invoke Invoke-NativeCommand -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'node' -and $ArgumentList[0] -like '*build-checkup-view.mjs' -and
            (Test-Path -LiteralPath $ArgumentList[0]) -and
            ($ArgumentList[1..6] -join '|') -eq "--latest|$($script:Splat.LatestPath)|--views-dir|$script:Views|--run-stamp|$script:Current" -and
            $ArgumentList[7] -eq '--remediations' -and $ArgumentList[8] -eq 'clear-temp-files,restart-stopped-service' -and
            $ArgumentList[9] -eq '--report' -and $ArgumentList[10] -eq 'health.md'
        }
    }

    It 'with a synced StateBase neither builds nor prunes, and leaves the report alone' {
        Mock Invoke-NativeCommand { Get-NodeResult 'Ok' }

        Publish-CheckupView @script:Splat -StateWritable $false | Should -BeNullOrEmpty

        Should -Invoke Invoke-NativeCommand -Times 0 -Exactly
        $script:Oldest | Should -Exist
        (Get-Content -LiteralPath $script:Report -Raw).Trim() | Should -Be '# report'
    }
}
