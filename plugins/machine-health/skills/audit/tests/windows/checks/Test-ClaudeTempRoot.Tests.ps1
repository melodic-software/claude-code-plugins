#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/checks/Test-ClaudeTempRoot.ps1.

.DESCRIPTION
The check resolves its own root from the environment, so every test points
CLAUDE_CODE_TMPDIR at a fixture tree and restores the prior environment
afterwards. TEMP and LOCALAPPDATA are redirected too: they are the fallback
candidates, and a developer machine has a real populated %TEMP%\claude that
would otherwise leak into the result.

Coverage boundary: the size arms (>=1 GB INFO, >=5 GB WARN) are not exercised
here -- a fixture cannot allocate gigabytes, and a sparse-file workaround
depends on NTFS plus fsutil authority the suite must not assume. Those arms are
covered by running the check against a real populated root.
#>

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SkillRoot = Split-Path -Parent $script:TestsRoot
    $script:ScriptPath = Join-Path $script:SkillRoot 'scripts\windows\checks\Test-ClaudeTempRoot.ps1'
    $script:LibRoot = Join-Path $script:SkillRoot 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Assert-CheckResult.ps1')
    Import-Module (Join-Path $script:TestsRoot 'helpers\Mock-Helpers.psm1') -Force

    function Invoke-ClaudeTempRootAsObject {
        $raw = & $script:ScriptPath
        $json = ($raw | Where-Object { $_ }) -join "`n"
        return $json | ConvertFrom-Json
    }

    function New-SessionDir {
        param(
            [Parameter(Mandatory)] [string] $Root,
            [Parameter(Mandatory)] [string] $ProjectKey,
            [Parameter(Mandatory)] [string] $SessionId,
            [int] $AgeDays = 0,
            [int] $FileCount = 1
        )
        $path = Join-Path (Join-Path $Root $ProjectKey) $SessionId
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        for ($i = 0; $i -lt $FileCount; $i++) {
            Set-Content -LiteralPath (Join-Path $path "f$i.txt") -Value 'x' -NoNewline
        }
        if ($AgeDays -gt 0) {
            (Get-Item -LiteralPath $path -Force).CreationTime = (Get-Date).AddDays(-$AgeDays)
        }
        return $path
    }
}

Describe 'Test-ClaudeTempRoot' -Tag 'check' {
    BeforeEach {
        $script:tmpDir = New-MachineHealthTempDir -Prefix 'machine-health-claude-temp'
        $script:priorTmpdir = $env:CLAUDE_CODE_TMPDIR
        $script:priorTemp = $env:TEMP
        $script:priorLocalAppData = $env:LOCALAPPDATA
        # Fallback candidates point somewhere guaranteed absent so only the
        # fixture can satisfy resolution.
        $env:TEMP = Join-Path $script:tmpDir 'no-temp-here'
        $env:LOCALAPPDATA = Join-Path $script:tmpDir 'no-localappdata-here'
    }

    AfterEach {
        $env:CLAUDE_CODE_TMPDIR = $script:priorTmpdir
        $env:TEMP = $script:priorTemp
        $env:LOCALAPPDATA = $script:priorLocalAppData
        Remove-MachineHealthTempDir -Path $script:tmpDir
    }

    Context 'root absent' {
        It 'exits quietly at OK when no candidate root exists' {
            $env:CLAUDE_CODE_TMPDIR = Join-Path $script:tmpDir 'absent'
            $result = Invoke-ClaudeTempRootAsObject
            { Assert-CheckResult $result } | Should -Not -Throw
            $result.id | Should -Be 'claude-temp-root'
            $result.category | Should -Be 'storage'
            $result.severity | Should -Be 'OK'
            $result.ran_successfully | Should -BeTrue
            $result.detail.root_exists | Should -BeFalse
            $result.summary | Should -Match 'not present'
        }
    }

    Context 'root present' {
        It 'reports OK for a small recent tree' {
            $root = Join-Path $script:tmpDir 'base\claude'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $null = New-SessionDir -Root $root -ProjectKey 'D--repos-x' -SessionId 'aaa' -FileCount 2
            $null = New-SessionDir -Root $root -ProjectKey 'D--repos-x' -SessionId 'bbb' -FileCount 1
            $env:CLAUDE_CODE_TMPDIR = Join-Path $script:tmpDir 'base'

            $result = Invoke-ClaudeTempRootAsObject
            { Assert-CheckResult $result } | Should -Not -Throw
            $result.severity | Should -Be 'OK'
            $result.detail.session_dir_count | Should -Be 2
            $result.detail.project_key_count | Should -Be 1
            $result.detail.file_count | Should -Be 3
            $result.detail.scan_truncated | Should -BeFalse
        }

        It 'counts session directories across project keys, not project keys alone' {
            $root = Join-Path $script:tmpDir 'base\claude'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $null = New-SessionDir -Root $root -ProjectKey 'key-one' -SessionId 'aaa'
            $null = New-SessionDir -Root $root -ProjectKey 'key-two' -SessionId 'bbb'
            $null = New-SessionDir -Root $root -ProjectKey 'key-two' -SessionId 'ccc'
            $env:CLAUDE_CODE_TMPDIR = Join-Path $script:tmpDir 'base'

            $result = Invoke-ClaudeTempRootAsObject
            $result.detail.project_key_count | Should -Be 2
            $result.detail.session_dir_count | Should -Be 3
        }

        It 'warns on an old session directory even when the tree is small' {
            $root = Join-Path $script:tmpDir 'base\claude'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $null = New-SessionDir -Root $root -ProjectKey 'key' -SessionId 'old' -AgeDays 20
            $env:CLAUDE_CODE_TMPDIR = Join-Path $script:tmpDir 'base'

            $result = Invoke-ClaudeTempRootAsObject
            { Assert-CheckResult $result } | Should -Not -Throw
            $result.severity | Should -Be 'WARN'
            $result.detail.oldest_session_age_days | Should -BeGreaterOrEqual 14
            $result.detail.total_gb | Should -BeLessThan 1
        }

        It 'measures age at the session level, not the project-key level' {
            # An old project key holding only fresh sessions must not trip the age arm:
            # a key directory is reused, so its own timestamp is not an age signal.
            $root = Join-Path $script:tmpDir 'base\claude'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $null = New-SessionDir -Root $root -ProjectKey 'key' -SessionId 'fresh'
            (Get-Item -LiteralPath (Join-Path $root 'key') -Force).CreationTime =
                (Get-Date).AddDays(-40)
            $env:CLAUDE_CODE_TMPDIR = Join-Path $script:tmpDir 'base'

            $result = Invoke-ClaudeTempRootAsObject
            $result.detail.oldest_session_age_days | Should -Be 0
            $result.severity | Should -Be 'OK'
        }

        It 'routes remediation to disk-hygiene and never remediates itself' {
            $root = Join-Path $script:tmpDir 'base\claude'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $sessionPath = New-SessionDir -Root $root -ProjectKey 'key' -SessionId 'old' -AgeDays 20
            $env:CLAUDE_CODE_TMPDIR = Join-Path $script:tmpDir 'base'

            $result = Invoke-ClaudeTempRootAsObject
            $result.detail.remediation_route | Should -Be 'disk-hygiene:clean'
            $result.summary | Should -Match 'disk-hygiene:clean'
            Test-Path -LiteralPath $sessionPath | Should -BeTrue
        }
    }

    Context 'root resolution' {
        It 'prefers a claude subdirectory under CLAUDE_CODE_TMPDIR' {
            $base = Join-Path $script:tmpDir 'base'
            New-Item -ItemType Directory -Path (Join-Path $base 'claude') -Force | Out-Null
            $env:CLAUDE_CODE_TMPDIR = $base

            $result = Invoke-ClaudeTempRootAsObject
            $result.detail.root_source | Should -Be 'CLAUDE_CODE_TMPDIR/claude'
            $result.detail.root_path | Should -Be (Join-Path $base 'claude')
        }

        It 'never treats a bare CLAUDE_CODE_TMPDIR base as the root' {
            # Claude Code appends `claude` to the base on Windows, so a base with no
            # claude child means it has not written there. Measuring the bare base
            # would report an unrelated temp directory's contents as this finding.
            $base = Join-Path $script:tmpDir 'base'
            New-Item -ItemType Directory -Path (Join-Path $base 'unrelated') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $base 'unrelated\big.bin') -Value 'not ours'
            $env:CLAUDE_CODE_TMPDIR = $base

            $result = Invoke-ClaudeTempRootAsObject
            $result.detail.root_exists | Should -BeFalse
            $result.severity | Should -Be 'OK'
            $result.detail.file_count | Should -Be 0
            $result.detail.root_path | Should -Be (Join-Path $base 'claude')
        }

        It 'falls back to TEMP\claude when CLAUDE_CODE_TMPDIR is unset' {
            $env:CLAUDE_CODE_TMPDIR = ''
            $temp = Join-Path $script:tmpDir 'systemp'
            New-Item -ItemType Directory -Path (Join-Path $temp 'claude') -Force | Out-Null
            $env:TEMP = $temp

            $result = Invoke-ClaudeTempRootAsObject
            $result.detail.root_source | Should -Be 'TEMP/claude'
        }

        It 'falls back to LOCALAPPDATA\Temp\claude when TEMP has no claude directory' {
            $env:CLAUDE_CODE_TMPDIR = ''
            $lad = Join-Path $script:tmpDir 'lad'
            New-Item -ItemType Directory -Path (Join-Path $lad 'Temp\claude') -Force | Out-Null
            $env:LOCALAPPDATA = $lad

            $result = Invoke-ClaudeTempRootAsObject
            $result.detail.root_source | Should -Be 'LOCALAPPDATA/Temp/claude'
        }

        It 'normalizes an 8.3 short-name root to its long form' {
            # %TEMP% commonly carries a short name (KYLESE~1). Long-form normalization
            # is what makes root_path comparable to what the human sees.
            $base = Join-Path $script:tmpDir 'base'
            $longName = Join-Path $base 'claude'
            New-Item -ItemType Directory -Path $longName -Force | Out-Null
            $env:CLAUDE_CODE_TMPDIR = $base

            $result = Invoke-ClaudeTempRootAsObject
            $result.detail.root_path | Should -Not -Match '~\d'
        }
    }

    Context 'schema conformance' {
        It 'emits a duration within the schema cap on a populated tree' {
            $root = Join-Path $script:tmpDir 'base\claude'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            1..5 | ForEach-Object {
                $null = New-SessionDir -Root $root -ProjectKey 'key' -SessionId "s$_" -FileCount 3
            }
            $env:CLAUDE_CODE_TMPDIR = Join-Path $script:tmpDir 'base'

            $result = Invoke-ClaudeTempRootAsObject
            { Assert-CheckResult $result } | Should -Not -Throw
            $result.duration_ms | Should -BeLessOrEqual 90000
            $result.needs_admin | Should -BeFalse
        }
    }
}
