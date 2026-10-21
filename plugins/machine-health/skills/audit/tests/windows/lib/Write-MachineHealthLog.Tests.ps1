#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Write-MachineHealthLog.ps1 -- the run log line
writer and its opt-in stderr mode.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Write-MachineHealthLog.ps1'

    function Invoke-CapturingStderr {
        param([scriptblock] $Action)
        $original = [Console]::Error
        $writer = [System.IO.StringWriter]::new()
        [Console]::SetError($writer)
        try { & $Action } finally { [Console]::SetError($original) }
        return $writer.ToString()
    }
}

Describe 'Write-MachineHealthLog' -Tag 'lib' {
    It 'appends a timestamped line to -LogPath' {
        $log = Join-Path $TestDrive 'run.log'

        Write-MachineHealthLog -Message 'run_start x=1' -LogPath $log

        Get-Content -LiteralPath $log | Should -Match '^\d{4}-\d{2}-\d{2}T\S+ run_start x=1$'
    }

    It 'writes nothing anywhere without -LogPath' {
        $err = Invoke-CapturingStderr { Write-MachineHealthLog -Message 'quiet' }
        $err | Should -BeNullOrEmpty
    }

    It 'writes the line to stderr and no file with -ToStderr' {
        $log = Join-Path $TestDrive 'never.log'

        $err = Invoke-CapturingStderr { Write-MachineHealthLog -Message 'synced_mode y=2' -LogPath $log -ToStderr }

        $err | Should -Match '\d{4}-\d{2}-\d{2}T\S+ synced_mode y=2'
        Test-Path -LiteralPath $log | Should -BeFalse
    }
}
