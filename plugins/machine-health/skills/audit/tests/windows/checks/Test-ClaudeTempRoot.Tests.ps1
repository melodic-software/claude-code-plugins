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
covered by running the check against a real populated root. The per-file
task-output arm is exercised through -TaskOutputWarnBytes, which lowers its
1 GB threshold to a size a fixture can write.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -Check 'Test-ClaudeTempRoot' -AsObject 'Invoke-ClaudeTempRootAsObject' -MockHelpers

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

    function New-TaskOutput {
        param(
            [Parameter(Mandatory)] [string] $SessionPath,
            [Parameter(Mandatory)] [string] $Name,
            [Parameter(Mandatory)] [int] $Bytes
        )
        $tasks = Join-Path $SessionPath 'tasks'
        New-Item -ItemType Directory -Path $tasks -Force | Out-Null
        $path = Join-Path $tasks $Name
        Set-Content -LiteralPath $path -Value ('x' * $Bytes) -NoNewline
        return $path
    }

    function Invoke-ClaudeTempRootWith {
        param([hashtable] $Parameters)
        return ConvertFrom-CheckOutput (& $script:ScriptPath @Parameters)
    }

    # Running the script would also run the envelope, so the listing function is
    # lifted out of the script's AST to be called with a stand-in clock.
    $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:ScriptPath, [ref]$null, [ref]$null)
    $listingAst = $scriptAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Find-LargestTaskOutput'
        }, $true)
    . ([scriptblock]::Create($listingAst.Extent.Text))

    function New-TickingClock {
        # Each read of Elapsed advances one second, so a budget runs out after a
        # known number of deadline tests rather than after wall-clock time.
        $clock = [pscustomobject]@{ Seconds = 0 }
        $clock | Add-Member -MemberType ScriptProperty -Name Elapsed -Value {
            $this.Seconds++
            [timespan]::FromSeconds($this.Seconds)
        }
        return $clock
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
            @($result.detail.largest_task_outputs).Count | Should -Be 0
            $result.detail.task_output_count | Should -Be 0
            $result.detail.task_output_over_count | Should -Be 0
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

    Context 'incomplete walk' {
        It 'reports UNKNOWN instead of a threshold verdict when a path cannot be read' {
            $root = Join-Path $script:tmpDir 'base\claude'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $session = New-SessionDir -Root $root -ProjectKey 'key' -SessionId 'aaa' -FileCount 1
            $blocked = Join-Path $session 'blocked'
            New-Item -ItemType Directory -Path $blocked -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $blocked 'hidden.bin') -Value 'unmeasurable'
            # Deny the current user list access so enumeration errors, without needing
            # elevation: the account still owns the directory and can restore the ACL.
            $denyRule = [System.Security.AccessControl.FileSystemAccessRule]::new(
                [System.Security.Principal.WindowsIdentity]::GetCurrent().User,
                'ListDirectory', 'ContainerInherit,ObjectInherit', 'None', 'Deny')
            $denied = $false
            try {
                $acl = Get-Acl -LiteralPath $blocked
                $acl.AddAccessRule($denyRule)
                Set-Acl -LiteralPath $blocked -AclObject $acl
                $denied = $true
            } catch {
                Set-ItResult -Skipped -Because 'the harness could not apply a deny ACL'
            }
            $env:CLAUDE_CODE_TMPDIR = Join-Path $script:tmpDir 'base'

            try {
                $result = Invoke-ClaudeTempRootAsObject
                { Assert-CheckResult $result } | Should -Not -Throw
                $result.severity | Should -Be 'UNKNOWN'
                $result.ran_successfully | Should -BeFalse
                $result.detail.unreadable_dir_count | Should -BeGreaterThan 0
                $result.error | Should -Match 'could not be read'
                $result.detail.total_bytes | Should -BeGreaterThan 0 `
                    -Because 'the partial floor still ships so the human sees what was measured'
            } finally {
                # The deny must come back off or AfterEach cannot delete the fixture.
                if ($denied) {
                    $acl = Get-Acl -LiteralPath $blocked
                    $null = $acl.RemoveAccessRule($denyRule)
                    Set-Acl -LiteralPath $blocked -AclObject $acl
                }
            }
        }

        It 'does not follow a junction out of the tree' {
            # Get-ChildItem -Recurse does not traverse reparse points without -FollowSymlink; the
            # hand-rolled walk must match, or a junction inflates the total and can cycle forever.
            $root = Join-Path $script:tmpDir 'base\claude'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $session = New-SessionDir -Root $root -ProjectKey 'key' -SessionId 'aaa' -FileCount 1

            $outside = Join-Path $script:tmpDir 'outside'
            New-Item -ItemType Directory -Path $outside -Force | Out-Null
            1..3 | ForEach-Object {
                Set-Content -LiteralPath (Join-Path $outside "elsewhere$_.txt") -Value 'not ours'
            }
            try {
                New-Item -ItemType Junction -Path (Join-Path $session 'link') `
                    -Target $outside -ErrorAction Stop | Out-Null
            } catch {
                Set-ItResult -Skipped -Because 'the harness could not create a junction'
            }
            $env:CLAUDE_CODE_TMPDIR = Join-Path $script:tmpDir 'base'

            $result = Invoke-ClaudeTempRootAsObject
            { Assert-CheckResult $result } | Should -Not -Throw
            $result.detail.file_count | Should -Be 1 `
                -Because 'only the session own file counts; the junction target lives elsewhere'
            $result.ran_successfully | Should -BeTrue
        }
    }

    Context 'background-task output files' {
        BeforeEach {
            $script:root = Join-Path $script:tmpDir 'base\claude'
            New-Item -ItemType Directory -Path $script:root -Force | Out-Null
            $env:CLAUDE_CODE_TMPDIR = Join-Path $script:tmpDir 'base'
        }

        It 'warns and names a task output at or above the per-file threshold' {
            $session = New-SessionDir -Root $script:root -ProjectKey 'key' -SessionId 'aaa'
            $big = New-TaskOutput -SessionPath $session -Name 'b1.output' -Bytes 4096
            $null = New-TaskOutput -SessionPath $session -Name 'b2.output' -Bytes 10

            $result = Invoke-ClaudeTempRootWith @{ TaskOutputWarnBytes = 1024 }
            { Assert-CheckResult $result } | Should -Not -Throw
            $result.severity | Should -Be 'WARN'
            $result.ran_successfully | Should -BeTrue
            $result.detail.task_output_count | Should -Be 2
            $top = @($result.detail.largest_task_outputs)[0]
            $top.path | Should -Be (Get-Item -LiteralPath $big -Force).FullName
            $top.bytes | Should -Be 4096
            $top.session_dir | Should -Be (Get-Item -LiteralPath $session -Force).FullName
            $underRoot = [System.IO.Path]::Combine('key', 'aaa', 'tasks', 'b1.output')
            $result.summary | Should -BeLike "*Task output *$underRoot is * GB, last write *" `
                -Because 'the file is named by full path or, past the summary cap, by its path under the root'
            $result.summary | Should -Match 'disk-hygiene:clean'
        }

        It 'shortens the named path to keep the summary within the schema cap' {
            $session = New-SessionDir -Root $script:root -ProjectKey ('k' * 100) -SessionId ('s' * 36)
            $null = New-TaskOutput -SessionPath $session -Name 'b1.output' -Bytes 4096

            $result = Invoke-ClaudeTempRootWith @{ TaskOutputWarnBytes = 1024 }
            { Assert-CheckResult $result } | Should -Not -Throw
            $result.severity | Should -Be 'WARN'
            $result.summary | Should -BeLike '*b1.output*'
            @($result.detail.largest_task_outputs)[0].path | Should -BeLike "*$('k' * 100)*b1.output"
        }

        It 'raises no per-file finding and leaves severity unchanged for small outputs' {
            $session = New-SessionDir -Root $script:root -ProjectKey 'key' -SessionId 'aaa'
            $null = New-TaskOutput -SessionPath $session -Name 's1.output' -Bytes 10
            $null = New-TaskOutput -SessionPath $session -Name 's2.output' -Bytes 20

            $result = Invoke-ClaudeTempRootAsObject
            { Assert-CheckResult $result } | Should -Not -Throw
            $result.severity | Should -Be 'OK'
            $result.summary | Should -Not -Match 'task output'
            $result.detail.task_output_count | Should -Be 2
            @($result.detail.largest_task_outputs).Count | Should -Be 2
            $result.detail.largest_task_output_gb | Should -Be 0
            $result.detail.task_output_truncated | Should -BeFalse
        }

        It 'keeps the per-file list in detail and summary when the walk budget is exceeded' {
            $session = New-SessionDir -Root $script:root -ProjectKey 'key' -SessionId 'aaa'
            $big = New-TaskOutput -SessionPath $session -Name 'runaway.output' -Bytes 4096

            $result = Invoke-ClaudeTempRootWith @{ TaskOutputWarnBytes = 1024; BudgetSeconds = 0 }
            { Assert-CheckResult $result } | Should -Not -Throw
            $result.severity | Should -Be 'UNKNOWN'
            $result.ran_successfully | Should -BeFalse
            $result.detail.scan_truncated | Should -BeTrue
            $result.detail.task_output_truncated | Should -BeFalse
            @($result.detail.largest_task_outputs)[0].path |
                Should -Be (Get-Item -LiteralPath $big -Force).FullName
            $result.summary | Should -Match 'incomplete'
            $result.summary | Should -BeLike '*runaway.output*'
            $result.summary | Should -Match 'listing complete'
        }

        It 'reads no file contents' {
            $session = New-SessionDir -Root $script:root -ProjectKey 'key' -SessionId 'aaa'
            $null = New-TaskOutput -SessionPath $session -Name 'secret.output' -Bytes 4096
            Mock Get-Content { throw 'task output contents must not be read' }
            Mock Select-String { throw 'task output contents must not be read' }
            Mock Get-FileHash { throw 'task output contents must not be read' }

            $result = Invoke-ClaudeTempRootWith @{ TaskOutputWarnBytes = 1024 }
            $result.severity | Should -Be 'WARN'
            Should -Invoke Get-Content -Times 0 -Exactly
            Should -Invoke Select-String -Times 0 -Exactly
            Should -Invoke Get-FileHash -Times 0 -Exactly
            ($result | ConvertTo-Json -Depth 10) | Should -Not -Match 'xxxx'
        }

        It 'reports long-form paths under the long-form root' {
            $session = New-SessionDir -Root $script:root -ProjectKey 'key' -SessionId 'aaa'
            $null = New-TaskOutput -SessionPath $session -Name 'a.output' -Bytes 10

            $result = Invoke-ClaudeTempRootAsObject
            $entry = @($result.detail.largest_task_outputs)[0]
            $entry.path | Should -Not -Match '~\d'
            $entry.session_dir | Should -Not -Match '~\d'
            $entry.path.StartsWith($result.detail.root_path) | Should -BeTrue
            $entry.last_write_utc | Should -BeOfType [datetime] `
                -Because 'an ISO 8601 round-trip string reads back from JSON as a DateTime'
        }

        It 'lists only the five largest, largest first, and counts the rest' {
            $session = New-SessionDir -Root $script:root -ProjectKey 'key' -SessionId 'aaa'
            1..7 | ForEach-Object {
                $null = New-TaskOutput -SessionPath $session -Name "t$_.output" -Bytes ($_ * 10)
            }

            $result = Invoke-ClaudeTempRootAsObject
            $list = @($result.detail.largest_task_outputs)
            $list.Count | Should -Be 5
            $result.detail.task_output_count | Should -Be 7
            $list.bytes | Should -Be @(70, 60, 50, 40, 30)
        }

        It 'counts every output over the threshold, not only the five it lists' {
            $session = New-SessionDir -Root $script:root -ProjectKey 'key' -SessionId 'aaa'
            1..7 | ForEach-Object {
                $null = New-TaskOutput -SessionPath $session -Name "big$_.output" -Bytes (2000 + $_)
            }

            $result = Invoke-ClaudeTempRootWith @{ TaskOutputWarnBytes = 1024 }
            { Assert-CheckResult $result } | Should -Not -Throw
            $result.severity | Should -Be 'WARN'
            @($result.detail.largest_task_outputs).Count | Should -Be 5
            $result.summary | Should -Match '; 6 more over the threshold'
            $result.detail.task_output_over_count | Should -Be 7
        }

        It 'stops inside one tasks directory once the listing budget runs out' {
            $session = New-SessionDir -Root $script:root -ProjectKey 'key' -SessionId 'aaa'
            1..50 | ForEach-Object {
                $null = New-TaskOutput -SessionPath $session -Name "t$_.output" -Bytes 1
            }

            $listing = Find-LargestTaskOutput -Root $script:root -Stopwatch (New-TickingClock) `
                -BudgetSeconds 10 -Top 5 -WarnBytes 1024
            $listing.Truncated | Should -BeTrue
            $listing.Count | Should -BeGreaterThan 0 `
                -Because 'the budget held through the project and session levels and ran out among the files'
            $listing.Count | Should -BeLessThan 50 `
                -Because 'the deadline is tested per entry, not once per directory'
        }

        It 'reports UNKNOWN when the listing is cut off even though the walk completes' {
            $session = New-SessionDir -Root $script:root -ProjectKey 'key' -SessionId 'aaa'
            $null = New-TaskOutput -SessionPath $session -Name 'unseen.output' -Bytes 4096

            $result = Invoke-ClaudeTempRootWith @{ TaskOutputWarnBytes = 1024; TaskOutputBudgetSeconds = 0 }
            { Assert-CheckResult $result } | Should -Not -Throw
            $result.detail.scan_truncated | Should -BeFalse
            $result.detail.task_output_truncated | Should -BeTrue
            $result.severity | Should -Be 'UNKNOWN' `
                -Because 'an output the listing never reached may be over the threshold'
            $result.ran_successfully | Should -BeFalse
            $result.error | Should -Match 'Task-output listing budget'
            $result.summary | Should -Match 'listing partial'
        }

        It 'lists only the tasks directory .output files of each session, not other files or depths' {
            $session = New-SessionDir -Root $script:root -ProjectKey 'key' -SessionId 'aaa'
            $null = New-TaskOutput -SessionPath $session -Name 'real.output' -Bytes 10
            $null = New-TaskOutput -SessionPath $session -Name 'notes.outputs' -Bytes 4096
            Set-Content -LiteralPath (Join-Path $session 'stray.output') -Value ('x' * 4096) -NoNewline
            $deep = Join-Path $session 'tasks\nested'
            New-Item -ItemType Directory -Path $deep -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $deep 'deep.output') -Value ('x' * 4096) -NoNewline

            $result = Invoke-ClaudeTempRootWith @{ TaskOutputWarnBytes = 1024 }
            $result.detail.task_output_count | Should -Be 1
            @($result.detail.largest_task_outputs)[0].path | Should -BeLike '*real.output'
            $result.severity | Should -Be 'OK'
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
            # Claude Code appends `claude` to the base on Windows; measuring a base with no claude
            # child would report an unrelated temp directory's contents as this finding.
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
