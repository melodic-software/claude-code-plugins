#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/checks/Test-DriveRootLitter.ps1.

.DESCRIPTION
Every test points -SystemRootPath (and usually an empty -DataRootPath) at a
fixture directory, so the real machine's volume roots never leak into a
result. The shipped baseline in reference/windows/drive-root-baseline.jsonc
is used as-is: the tests double as a guard that the shipped data still admits
the stock Windows layout and still catches the litter shapes.
#>

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SkillRoot = Split-Path -Parent $script:TestsRoot
    $script:ScriptPath = Join-Path $script:SkillRoot 'scripts\windows\checks\Test-DriveRootLitter.ps1'
    $script:LibRoot = Join-Path $script:SkillRoot 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Assert-CheckResult.ps1')
    Import-Module (Join-Path $script:TestsRoot 'helpers\Mock-Helpers.psm1') -Force
    . (Join-Path $script:TestsRoot 'helpers\Invoke-CheckScript.ps1')

    function Invoke-DriveRootLitterAsObject {
        param(
            [Parameter(Mandatory)] [string] $SystemRootPath,
            [string[]] $DataRootPath = @(),
            [string] $BaselinePath
        )
        $extra = @{}
        if ($BaselinePath) { $extra['BaselinePath'] = $BaselinePath }
        return ConvertFrom-CheckOutput (& $script:ScriptPath `
                -SystemRootPath $SystemRootPath -DataRootPath $DataRootPath @extra)
    }

    function New-BaselineOnlyRoot {
        <#
        .SYNOPSIS
        Builds a fixture root holding only entries the shipped baseline expects
        at a system-drive root -- a representative subset of directories and
        files, including the housekeeping names shared by every volume.
        #>
        param([Parameter(Mandatory)] [string] $Path)
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        foreach ($d in @('Windows', 'Program Files', 'Program Files (x86)', 'ProgramData',
                'Users', 'PerfLogs', 'Recovery', '$Recycle.Bin', 'System Volume Information',
                'Config.Msi', 'OneDriveTemp', 'inetpub')) {
            New-Item -ItemType Directory -Path (Join-Path $Path $d) -Force | Out-Null
        }
        foreach ($f in @('pagefile.sys', 'swapfile.sys', 'DumpStack.log.tmp', 'bootmgr')) {
            Set-Content -LiteralPath (Join-Path $Path $f) -Value 'x' -NoNewline
        }
        return $Path
    }
}

Describe 'Test-DriveRootLitter' -Tag 'check' {
    BeforeEach {
        $script:tmpDir = New-MachineHealthTempDir -Prefix 'machine-health-drive-root'
        $script:sysRoot = New-BaselineOnlyRoot -Path (Join-Path $script:tmpDir 'sysroot')
    }

    AfterEach {
        Remove-MachineHealthTempDir -Path $script:tmpDir
    }

    Context 'baseline-only root' {
        It 'reports OK with zero residue for a stock system-drive layout' {
            $result = Invoke-DriveRootLitterAsObject -SystemRootPath $script:sysRoot
            { Assert-CheckResult $result } | Should -Not -Throw
            $result.id | Should -Be 'drive-root-litter'
            $result.category | Should -Be 'storage'
            $result.severity | Should -Be 'OK'
            $result.ran_successfully | Should -BeTrue
            $result.needs_admin | Should -BeFalse
            $result.detail.residue_count | Should -Be 0
            $result.summary | Should -Match 'clean'
        }

        It 'matches baseline names case-insensitively' {
            Rename-Item -LiteralPath (Join-Path $script:sysRoot 'Windows') -NewName 'WINDOWS'
            $result = Invoke-DriveRootLitterAsObject -SystemRootPath $script:sysRoot
            $result.detail.residue_count | Should -Be 0
        }
    }

    Context 'unexpected entries on the system drive' {
        It 'reports a stray directory as INFO residue' {
            New-Item -ItemType Directory -Path (Join-Path $script:sysRoot 'tmp') -Force | Out-Null

            $result = Invoke-DriveRootLitterAsObject -SystemRootPath $script:sysRoot
            { Assert-CheckResult $result } | Should -Not -Throw
            $result.severity | Should -Be 'INFO'
            $result.detail.residue_count | Should -Be 1
            $result.detail.residue[0].name | Should -Be 'tmp'
            $result.detail.residue[0].type | Should -Be 'directory'
            $result.detail.residue[0].is_empty | Should -BeTrue
            $result.summary | Should -Match 'tmp'
        }

        It 'reports a stray file as INFO residue with its size' {
            Set-Content -LiteralPath (Join-Path $script:sysRoot 'log.txt') -Value '' -NoNewline

            $result = Invoke-DriveRootLitterAsObject -SystemRootPath $script:sysRoot
            { Assert-CheckResult $result } | Should -Not -Throw
            $result.severity | Should -Be 'INFO'
            $result.detail.residue_count | Should -Be 1
            $result.detail.residue[0].name | Should -Be 'log.txt'
            $result.detail.residue[0].type | Should -Be 'file'
            $result.detail.residue[0].size_bytes | Should -Be 0
        }

        It 'matches type-aware: a stray FILE named like an expected DIRECTORY is residue' {
            Remove-Item -LiteralPath (Join-Path $script:sysRoot 'Recovery') -Force
            Set-Content -LiteralPath (Join-Path $script:sysRoot 'Recovery') -Value 'not a dir'

            $result = Invoke-DriveRootLitterAsObject -SystemRootPath $script:sysRoot
            $result.detail.residue_count | Should -Be 1
            $result.detail.residue[0].type | Should -Be 'file'
        }

        It 'never mutates what it finds' {
            $stray = Join-Path $script:sysRoot 'tmp'
            New-Item -ItemType Directory -Path $stray -Force | Out-Null
            $strayFile = Join-Path $script:sysRoot 'log.txt'
            Set-Content -LiteralPath $strayFile -Value '' -NoNewline
            $before = @(Get-ChildItem -LiteralPath $script:sysRoot -Force | Sort-Object Name)

            $result = Invoke-DriveRootLitterAsObject -SystemRootPath $script:sysRoot
            $result.detail.residue_count | Should -Be 2
            $after = @(Get-ChildItem -LiteralPath $script:sysRoot -Force | Sort-Object Name)
            @($after).Count | Should -Be @($before).Count
            Test-Path -LiteralPath $stray | Should -BeTrue
            Test-Path -LiteralPath $strayFile | Should -BeTrue
            $result.detail.remediation_route | Should -Be 'disk-hygiene:clean'
        }

        It 'emits deterministic residue ordering across runs' {
            foreach ($n in @('zzz-stray', 'aaa-stray', 'mmm-stray')) {
                New-Item -ItemType Directory -Path (Join-Path $script:sysRoot $n) -Force | Out-Null
            }
            $first = Invoke-DriveRootLitterAsObject -SystemRootPath $script:sysRoot
            $second = Invoke-DriveRootLitterAsObject -SystemRootPath $script:sysRoot
            @($first.detail.residue.name) | Should -Be @('aaa-stray', 'mmm-stray', 'zzz-stray')
            ($first.detail.residue | ConvertTo-Json -Depth 5) |
                Should -Be ($second.detail.residue | ConvertTo-Json -Depth 5) `
                -Because 'identical machine state must produce identical findings (identical_streak)'
        }
    }

    Context 'severity ladder' {
        It 'stays OK at zero residue' {
            (Invoke-DriveRootLitterAsObject -SystemRootPath $script:sysRoot).severity |
                Should -Be 'OK'
        }

        It 'caps a handful of residue entries at INFO, never higher' {
            1..9 | ForEach-Object {
                Set-Content -LiteralPath (Join-Path $script:sysRoot "stray$_.bin") -Value 'x'
            }
            $result = Invoke-DriveRootLitterAsObject -SystemRootPath $script:sysRoot
            $result.detail.residue_count | Should -Be 9
            $result.severity | Should -Be 'INFO'
        }

        It 'reports WARN at >=10 residue entries and never CRIT' {
            1..12 | ForEach-Object {
                Set-Content -LiteralPath (Join-Path $script:sysRoot "stray$_.bin") -Value 'x'
            }
            $result = Invoke-DriveRootLitterAsObject -SystemRootPath $script:sysRoot
            $result.detail.residue_count | Should -Be 12
            $result.severity | Should -Be 'WARN'
        }
    }

    Context 'non-system volume posture' {
        It 'presumes user content legitimate and reports only litter-name shapes' {
            $dataRoot = Join-Path $script:tmpDir 'dataroot'
            foreach ($d in @('repos', 'worktrees', 'media', 'tmp')) {
                New-Item -ItemType Directory -Path (Join-Path $dataRoot $d) -Force | Out-Null
            }
            Set-Content -LiteralPath (Join-Path $dataRoot 'log.txt') -Value '' -NoNewline
            Set-Content -LiteralPath (Join-Path $dataRoot 'notes.md') -Value 'mine'

            $result = Invoke-DriveRootLitterAsObject -SystemRootPath $script:sysRoot `
                -DataRootPath @($dataRoot)
            { Assert-CheckResult $result } | Should -Not -Throw
            $result.detail.residue_count | Should -Be 2
            @($result.detail.residue.name) | Should -Be @('log.txt', 'tmp')
            @($result.detail.volumes).Count | Should -Be 2
            @($result.detail.volumes | Where-Object posture -eq 'litter-names').residue_count |
                Should -Be 2
        }

        It 'treats volume housekeeping on a data root as expected, not litter' {
            $dataRoot = Join-Path $script:tmpDir 'dataroot'
            foreach ($d in @('$Recycle.Bin', 'System Volume Information')) {
                New-Item -ItemType Directory -Path (Join-Path $dataRoot $d) -Force | Out-Null
            }
            $result = Invoke-DriveRootLitterAsObject -SystemRootPath $script:sysRoot `
                -DataRootPath @($dataRoot)
            $result.detail.residue_count | Should -Be 0
        }
    }

    Context 'degraded inputs' {
        It 'reports UNKNOWN when the baseline file is missing' {
            $result = Invoke-DriveRootLitterAsObject -SystemRootPath $script:sysRoot `
                -BaselinePath (Join-Path $script:tmpDir 'absent-baseline.jsonc')
            { Assert-CheckResult $result } | Should -Not -Throw
            $result.severity | Should -Be 'UNKNOWN'
            $result.ran_successfully | Should -BeFalse
        }

        It 'reports UNKNOWN when the baseline file is malformed' {
            $bad = Join-Path $script:tmpDir 'bad-baseline.jsonc'
            Set-Content -LiteralPath $bad -Value '{ "all_volumes": { } }'
            $result = Invoke-DriveRootLitterAsObject -SystemRootPath $script:sysRoot `
                -BaselinePath $bad
            $result.severity | Should -Be 'UNKNOWN'
            $result.ran_successfully | Should -BeFalse
            $result.error | Should -Match 'directories'
        }

        It 'reports UNKNOWN with partial residue when a root cannot be listed' {
            New-Item -ItemType Directory -Path (Join-Path $script:sysRoot 'tmp') -Force | Out-Null
            $result = Invoke-DriveRootLitterAsObject -SystemRootPath $script:sysRoot `
                -DataRootPath @(Join-Path $script:tmpDir 'no-such-root')
            { Assert-CheckResult $result } | Should -Not -Throw
            $result.severity | Should -Be 'UNKNOWN'
            $result.ran_successfully | Should -BeFalse
            $result.detail.unreadable_root_count | Should -Be 1
            $result.detail.residue_count | Should -Be 1 `
                -Because 'the residue found on listable roots still ships as a floor'
        }
    }

    Context 'schema conformance' {
        It 'emits a schema-valid result with residue path concatenation readable' {
            New-Item -ItemType Directory -Path (Join-Path $script:sysRoot 'tmp') -Force | Out-Null
            $result = Invoke-DriveRootLitterAsObject -SystemRootPath $script:sysRoot
            { Assert-CheckResult $result } | Should -Not -Throw
            $result.duration_ms | Should -BeLessOrEqual 90000
            $entry = $result.detail.residue[0]
            "$($entry.volume)$($entry.name)" | Should -Be (Join-Path $script:sysRoot 'tmp')
        }
    }
}
