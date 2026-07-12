#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SkillRoot = Split-Path -Parent $script:TestsRoot
    $script:ScriptPath = Join-Path $script:SkillRoot 'scripts\windows\checks\Test-ScheduledTasks.ps1'
    $script:LibRoot = Join-Path $script:SkillRoot 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Assert-CheckResult.ps1')

    # Dot-source the check script to expose Test-IsNeverRunScheduledTask in
    # this scope. The script's own dot-source guard (InvocationName -eq '.')
    # skips the main block, so this only defines the helper -- no orchestrator
    # code path runs.
    . $script:ScriptPath

    function Invoke-ScheduledTasksAsObject {
        $raw = & $script:ScriptPath
        $json = ($raw | Where-Object { $_ }) -join "`n"
        return $json | ConvertFrom-Json
    }
}

# NOTE: deeper severity-rubric coverage for this check is limited by Pester 5
# mock propagation into `&`-invoked child scripts for cmdlets from the
# ScheduledTasks module. See .claude/rules/powershell/testing.md
# "Mocks do NOT propagate through `&`-invoked `.ps1` scripts". Baseline + no-
# tasks paths are deterministic; the never-run filter is covered via the
# extracted Test-IsNeverRunScheduledTask helper below.

Describe 'Test-ScheduledTasks -- baseline' -Tag 'check' {
    It 'emits a schema-valid CheckResult when Get-ScheduledTask returns no tasks' {
        Mock Get-ScheduledTask { @() }
        $result = Invoke-ScheduledTasksAsObject
        { Assert-CheckResult $result } | Should -Not -Throw
        $result.id | Should -Be 'scheduled-tasks'
        $result.severity | Should -Be 'OK'
        $result.detail.failed_count | Should -Be 0
    }

    It 'emits UNKNOWN when Get-ScheduledTask throws' {
        Mock Get-ScheduledTask { throw 'Access denied' }
        $result = Invoke-ScheduledTasksAsObject
        $result.severity | Should -Be 'UNKNOWN'
        $result.ran_successfully | Should -BeFalse
    }
}

Describe 'Test-IsNeverRunScheduledTask -- helper' -Tag 'check' {
    It 'returns $true for $null TaskInfo (defensive)' {
        Test-IsNeverRunScheduledTask -TaskInfo $null | Should -BeTrue
    }

    It 'returns $true when LastTaskResult = 267011 (SCHED_S_TASK_HAS_NOT_RUN)' {
        $info = [pscustomobject]@{
            LastTaskResult = 267011
            LastRunTime    = (Get-Date).AddHours(-1)
        }
        Test-IsNeverRunScheduledTask -TaskInfo $info | Should -BeTrue
    }

    It 'returns $true when LastRunTime = Win32 sentinel 1999-11-30' {
        $info = [pscustomobject]@{
            LastTaskResult = 1
            LastRunTime    = [datetime]'1999-11-30 00:00:00'
        }
        Test-IsNeverRunScheduledTask -TaskInfo $info | Should -BeTrue
    }

    It 'returns $true when LastRunTime = alternate sentinel 1899-12-30' {
        $info = [pscustomobject]@{
            LastTaskResult = 1
            LastRunTime    = [datetime]'1899-12-30 00:00:00'
        }
        Test-IsNeverRunScheduledTask -TaskInfo $info | Should -BeTrue
    }

    It 'returns $true when LastRunTime is $null' {
        $info = [pscustomobject]@{
            LastTaskResult = 1
            LastRunTime    = $null
        }
        Test-IsNeverRunScheduledTask -TaskInfo $info | Should -BeTrue
    }

    It 'returns $false for a real recent failure (post-2000 LastRunTime, non-267011 result)' {
        $info = [pscustomobject]@{
            LastTaskResult = 1
            LastRunTime    = (Get-Date).AddHours(-1)
        }
        Test-IsNeverRunScheduledTask -TaskInfo $info | Should -BeFalse
    }

    It 'returns $false for SCHED_S_TASK_TERMINATED (267014) with real LastRunTime' {
        # 267014 = terminated by user. Intentionally NOT filtered -- termination
        # is a real event worth surfacing. If found noisy in practice, a
        # separate filter can be added.
        $info = [pscustomobject]@{
            LastTaskResult = 267014
            LastRunTime    = (Get-Date).AddDays(-2)
        }
        Test-IsNeverRunScheduledTask -TaskInfo $info | Should -BeFalse
    }
}
