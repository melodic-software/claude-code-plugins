#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Write-StateFile.ps1 -- the atomic replace recipe
that is the only writer of approvals.json and mutes.json.

.DESCRIPTION
Pins the plan's contract: first write into an empty directory, a replace that
succeeds while a reader shares ReadWrite | Delete, 5 retries at 100 ms doubling
against a reader that does not share Delete (then an error naming the file with
the temp file left), and one re-read and re-apply when the destination appears
between the existence test and the first-write move.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Write-StateFile.ps1' -MockHelpers
}

Describe 'Write-StateFile' -Tag 'lib' {
    BeforeEach {
        $script:dir = New-MachineHealthTempDir -Prefix 'machine-health-statefile'
        $script:path = Join-Path $script:dir 'approvals.json'
    }

    AfterEach {
        Remove-MachineHealthTempDir -Path $script:dir
    }

    It 'writes the first file into an empty directory and leaves no temp file' {
        $seen = [System.Collections.Generic.List[object]]::new()

        $written = Write-StateFile -Path $script:path -Update { param($current) $seen.Add($current); '{"a":1}' }

        $written | Should -BeTrue
        $seen.Count | Should -Be 1
        $seen[0] | Should -BeNullOrEmpty
        [System.IO.File]::ReadAllText($script:path) | Should -Be '{"a":1}'
        @(Get-ChildItem -LiteralPath $script:dir -Filter '*.tmp').Count | Should -Be 0
    }

    It 'hands -Update the current text and replaces the file with its result' {
        [System.IO.File]::WriteAllText($script:path, 'old')

        $null = Write-StateFile -Path $script:path -Update { param($current) "$current+new" }

        [System.IO.File]::ReadAllText($script:path) | Should -Be 'old+new'
    }

    It 'leaves the file untouched when -Update returns $null' {
        [System.IO.File]::WriteAllText($script:path, 'old')

        $written = Write-StateFile -Path $script:path -Update { param($current) $null }

        $written | Should -BeFalse
        [System.IO.File]::ReadAllText($script:path) | Should -Be 'old'
        @(Get-ChildItem -LiteralPath $script:dir -Filter '*.tmp').Count | Should -Be 0
    }

    It 'replaces the file while a reader holds it open with ReadWrite | Delete' {
        [System.IO.File]::WriteAllText($script:path, 'old')
        $reader = [System.IO.File]::Open($script:path, 'Open', 'Read', [System.IO.FileShare]'ReadWrite, Delete')
        try {
            $null = Write-StateFile -Path $script:path -Update { param($current) 'new' }
            # The open handle still reads the file it opened: the swap never exposes a partial write.
            [System.IO.StreamReader]::new($reader).ReadToEnd() | Should -Be 'old'
        } finally {
            $reader.Dispose()
        }
        [System.IO.File]::ReadAllText($script:path) | Should -Be 'new'
    }

    Context 'a reader that does not share Delete' {
        BeforeEach {
            [System.IO.File]::WriteAllText($script:path, 'old')
            $script:delays = [System.Collections.Generic.List[int]]::new()
            Mock Start-Sleep { $script:delays.Add($Milliseconds) }
            $script:reader = [System.IO.File]::Open($script:path, 'Open', 'Read', [System.IO.FileShare]::Read)
        }

        AfterEach {
            $script:reader.Dispose()
        }

        It 'retries 5 times at 100 ms doubling, then throws naming the file and leaves the temp file' {
            { Write-StateFile -Path $script:path -Update { param($current) 'new' } } |
                Should -Throw -ExpectedMessage "*$($script:path)*"

            $script:delays | Should -Be @(100, 200, 400, 800, 1600)
            $temps = @(Get-ChildItem -LiteralPath $script:dir -Filter '*.tmp')
            $temps.Count | Should -Be 1
            [System.IO.File]::ReadAllText($temps[0].FullName) | Should -Be 'new'
            $script:reader.Dispose()
            [System.IO.File]::ReadAllText($script:path) | Should -Be 'old'
        }
    }

    It 're-reads and re-applies once when the destination appears before the first-write move' {
        $calls = [System.Collections.Generic.List[object]]::new()
        $target = $script:path
        $update = {
            param($current)
            $calls.Add($current)
            if ($calls.Count -eq 1) {
                # Another writer creates the file after the existence test, before the move.
                [System.IO.File]::WriteAllText($target, 'theirs')
                return 'mine'
            }
            return "$current+mine"
        }

        $written = Write-StateFile -Path $script:path -Update $update

        $written | Should -BeTrue
        $calls.Count | Should -Be 2
        $calls[0] | Should -BeNullOrEmpty
        $calls[1] | Should -Be 'theirs'
        [System.IO.File]::ReadAllText($script:path) | Should -Be 'theirs+mine'
        @(Get-ChildItem -LiteralPath $script:dir -Filter '*.tmp').Count | Should -Be 0
    }

    It 'propagates an -Update failure without creating a temp file' {
        [System.IO.File]::WriteAllText($script:path, 'old')

        { Write-StateFile -Path $script:path -Update { param($current) throw 'invalid document' } } |
            Should -Throw -ExpectedMessage '*invalid document*'

        [System.IO.File]::ReadAllText($script:path) | Should -Be 'old'
        @(Get-ChildItem -LiteralPath $script:dir -Filter '*.tmp').Count | Should -Be 0
    }
}
