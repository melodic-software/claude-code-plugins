#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Enter-RunLock.ps1 -- the exclusive lock file
the orchestrator (run.lock) and Set-ApprovalState (approvals.lock) hold.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Enter-RunLock.ps1' -MockHelpers
}

Describe 'Enter-RunLock' -Tag 'lib' {
    BeforeEach {
        $script:dir = New-MachineHealthTempDir -Prefix 'machine-health-lock'
        $script:held = [System.Collections.Generic.List[System.IDisposable]]::new()
    }

    AfterEach {
        foreach ($h in $script:held) { $h.Dispose() }
        Remove-MachineHealthTempDir -Path $script:dir
    }

    It 'holds two lock names independently' {
        $run = Enter-RunLock -StateDir $script:dir -Name 'run'
        $script:held.Add($run)
        $approvals = Enter-RunLock -StateDir $script:dir -Name 'approvals'
        $script:held.Add($approvals)

        $run | Should -Not -BeNullOrEmpty
        $approvals | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath (Join-Path $script:dir 'run.lock') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:dir 'approvals.lock') | Should -BeTrue

        $run.Dispose()
        $again = Enter-RunLock -StateDir $script:dir -Name 'run'
        $script:held.Add($again)
        $again | Should -Not -BeNullOrEmpty
    }

    It 'returns $null for a lock another handle holds, without waiting by default' {
        $script:held.Add((Enter-RunLock -StateDir $script:dir -Name 'run'))

        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $second = Enter-RunLock -StateDir $script:dir -Name 'run'
        $watch.Stop()

        $second | Should -BeNullOrEmpty
        $watch.ElapsedMilliseconds | Should -BeLessThan 1000
    }

    It 'waits up to -TimeoutSeconds for a held lock, then returns $null' {
        $script:held.Add((Enter-RunLock -StateDir $script:dir -Name 'approvals'))

        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $second = Enter-RunLock -StateDir $script:dir -Name 'approvals' -TimeoutSeconds 1
        $watch.Stop()

        $second | Should -BeNullOrEmpty
        $watch.ElapsedMilliseconds | Should -BeGreaterOrEqual 1000
    }

    It 'leaves the lock file in place when released' {
        $lock = Enter-RunLock -StateDir $script:dir -Name 'run'
        $lock.Dispose()
        Test-Path -LiteralPath (Join-Path $script:dir 'run.lock') | Should -BeTrue
    }

    It 'rejects a lock name that is not a plain lowercase word' {
        { Enter-RunLock -StateDir $script:dir -Name '..\run' } | Should -Throw
    }
}
