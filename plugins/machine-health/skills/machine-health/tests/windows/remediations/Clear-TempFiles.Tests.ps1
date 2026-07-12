#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/remediations/Clear-TempFiles.ps1.

.DESCRIPTION
Pins three safety behaviors of the temp-file remediation:

1. Reparse-point safety. Get-ChildItem -Recurse follows directory
   junctions and symlinks by default on PowerShell 5.1. A malicious
   or misconfigured symlink under %TEMP% could point outside the
   temp tree (or at critical system paths), and the previous
   remediation would happily scan through it and delete files there.
   The fix: skip any file or directory with the ReparsePoint attribute.

2. Age filter: only files older than -AgeDays are eligible; newer
   files are preserved regardless of location.

3. Locked-file handling: Remove-Item failures don't break the whole
   remediation -- they're counted and reported.
#>

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SkillRoot = Split-Path -Parent $script:TestsRoot
    $script:ScriptPath = Join-Path $script:SkillRoot 'scripts\windows\remediations\Clear-TempFiles.ps1'

    function New-MockTempFile {
        param(
            [Parameter(Mandatory)] [string] $FullName,
            [Parameter(Mandatory)] [datetime] $LastWriteTime,
            [long] $Length = 1024,
            [switch] $IsReparsePoint
        )
        $attrs = if ($IsReparsePoint) {
            [System.IO.FileAttributes]::ReparsePoint
        } else {
            [System.IO.FileAttributes]::Normal
        }
        [pscustomobject]@{
            FullName      = $FullName
            LastWriteTime = $LastWriteTime
            Length        = $Length
            Attributes    = $attrs
        }
    }

    function Invoke-ClearTempFilesAsObject {
        param([int]$AgeDays = 7)
        $raw = & $script:ScriptPath -AgeDays $AgeDays
        $json = ($raw | Where-Object { $_ }) -join "`n"
        return $json | ConvertFrom-Json
    }
}

Describe 'Clear-TempFiles -- core delete loop' -Tag 'remediation' {
    BeforeAll {
        Mock Test-Path { $true }
        Mock Remove-Item {}
    }

    It 'deletes files older than the age cutoff' {
        $old = New-MockTempFile -FullName 'C:\temp\old.log' `
            -LastWriteTime (Get-Date).AddDays(-30) -Length 5000
        Mock Get-ChildItem { @($old) }.GetNewClosure()

        $result = Invoke-ClearTempFilesAsObject
        Should -Invoke Remove-Item -Times 1 -ParameterFilter {
            $LiteralPath -eq 'C:\temp\old.log'
        }
        $result.bytes_freed | Should -BeGreaterThan 0
    }

    It 'preserves files newer than the age cutoff' {
        $new = New-MockTempFile -FullName 'C:\temp\recent.log' `
            -LastWriteTime (Get-Date).AddDays(-1) -Length 5000
        Mock Get-ChildItem { @($new) }.GetNewClosure()

        Invoke-ClearTempFilesAsObject | Out-Null
        Should -Invoke Remove-Item -Times 0 -ParameterFilter {
            $LiteralPath -eq 'C:\temp\recent.log'
        }
    }
}

Describe 'Clear-TempFiles -- reparse-point safety' -Tag 'remediation' {
    BeforeAll {
        Mock Test-Path { $true }
        Mock Remove-Item {}
    }

    It 'skips files marked as reparse points (symlinks)' {
        $symlink = New-MockTempFile -FullName 'C:\temp\evil-symlink.txt' `
            -LastWriteTime (Get-Date).AddDays(-30) -Length 1000 -IsReparsePoint
        $normal = New-MockTempFile -FullName 'C:\temp\normal.log' `
            -LastWriteTime (Get-Date).AddDays(-30) -Length 2000
        Mock Get-ChildItem { @($symlink, $normal) }.GetNewClosure()

        Invoke-ClearTempFilesAsObject | Out-Null
        # Previous code would delete the symlinked file, and -Recurse would
        # walk into any symlinked directories. Fix: any entry with the
        # ReparsePoint attribute is skipped entirely.
        Should -Invoke Remove-Item -Times 0 -ParameterFilter {
            $LiteralPath -eq 'C:\temp\evil-symlink.txt'
        }
        Should -Invoke Remove-Item -Times 1 -ParameterFilter {
            $LiteralPath -eq 'C:\temp\normal.log'
        }
    }
}

Describe 'Clear-TempFiles -- failure handling' -Tag 'remediation' {
    BeforeAll {
        # Only one temp path exists on the mocked host -- keeps the delete
        # loop from processing the same fixture multiple times.
        Mock Test-Path -ParameterFilter { $LiteralPath -like '*Temp*' } -MockWith { $true }
        Mock Test-Path -MockWith { $false }
    }

    It 'counts locked files separately from successful deletes' {
        $locked = New-MockTempFile -FullName 'C:\temp\locked.dat' `
            -LastWriteTime (Get-Date).AddDays(-30) -Length 500
        $ok = New-MockTempFile -FullName 'C:\temp\ok.log' `
            -LastWriteTime (Get-Date).AddDays(-30) -Length 1000
        Mock Get-ChildItem { @($locked, $ok) }.GetNewClosure()
        Mock Remove-Item {
            if ($LiteralPath -like '*locked.dat') { throw 'File is in use' }
        }

        $result = Invoke-ClearTempFilesAsObject
        # Mocked Get-ChildItem returns the same fixture for each path
        # included after Test-Path filter; assert ratio rather than count.
        $result.after.deleted_count | Should -BeGreaterThan 0
        $result.after.skipped_locked | Should -Be $result.after.deleted_count
    }
}
