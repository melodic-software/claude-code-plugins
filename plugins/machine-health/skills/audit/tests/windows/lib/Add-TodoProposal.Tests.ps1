#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Add-TodoProposal.ps1 -- state-rooted TODO.md path,
proposal append, and the report's open-questions section.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Add-TodoProposal.ps1', 'Resolve-SkillRoot.ps1' -MockHelpers
}

Describe 'Add-TodoProposal' -Tag 'lib' {
    BeforeEach {
        $script:stateBase = New-MachineHealthTempDir -Prefix 'machine-health-todo'
    }

    AfterEach {
        Remove-MachineHealthTempDir -Path $script:stateBase
    }

    It 'resolves the TODO.md path under the state root, never the skill root' {
        $todoPath = Get-TodoPath -StateBase $script:stateBase
        $todoPath | Should -Be (Join-Path $script:stateBase 'TODO.md')
        $todoPath | Should -Not -BeLike "$(Resolve-SkillRoot)*"
    }

    It 'appends a proposal once and reports it as an open question' {
        $todoPath = Get-TodoPath -StateBase $script:stateBase
        $queued = @()
        foreach ($i in 1..2) {
            if (Add-TodoProposal -TodoPath $todoPath -Title 'Install module X' -Body 'Run Install-Module X.') {
                $queued += 'Install module X'
            }
        }

        $queued | Should -Be @('Install module X')
        @(Get-Content -LiteralPath $todoPath | Where-Object { $_ -eq '### Install module X' }).Count | Should -Be 1
        Get-Content -LiteralPath $todoPath -Raw | Should -Match 'Run Install-Module X\.'
        Get-OpenQuestionsMarkdown -QueuedTitle $queued -TodoPath $todoPath |
            Should -Be "- Install module X (queued in ``$todoPath``)"
    }

    It 'says no entries were queued when nothing was' {
        Get-OpenQuestionsMarkdown -TodoPath (Get-TodoPath -StateBase $script:stateBase) |
            Should -Be '_No new TODO entries this run._'
    }
}
