#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Measure-FolderSize.ps1 -- the storage-top-n
folder walk, its never-descend rules, its budget and the allocated pass.

.DESCRIPTION
Every tree is built under TestDrive with files of known byte counts, so each
expected size is the sum of the bytes the test wrote. The three OneDrive
variables are cleared for each test and restored after it, since they are
process-wide and the host may set them; a test that needs one sets it to a
TestDrive folder. Paths are compared in their long form (Get-Item FullName),
because TestDrive sits under %TEMP%, which can carry an 8.3 short name.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Measure-FolderSize.ps1'

    function Write-SizedFile {
        param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [int] $Bytes)
        New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
        [System.IO.File]::WriteAllBytes($Path, [byte[]]::new($Bytes))
    }

    function Get-LongName {
        param([Parameter(Mandatory)] [string] $Path)
        return (Get-Item -LiteralPath $Path -Force).FullName.TrimEnd('\')
    }

    # The check holds the real limits; tests pass their own, with a budget
    # no test tree reaches unless the test sets it.
    function Measure-TestRoot {
        param(
            [Parameter(Mandatory)] [string[]] $Root,
            [int] $Top = 15,
            [int] $AllocatedFileCap = 10000,
            [pscustomobject] $Budget = (New-ScanBudget -Milliseconds 600000)
        )
        return Measure-FolderSize -Root $Root -Top $Top -AllocatedFileCap $AllocatedFileCap -Budget $Budget
    }

    $script:OneDriveNames = @('OneDrive', 'OneDriveConsumer', 'OneDriveCommercial')
}

Describe 'Test-CloudSyncRoot' -Tag 'lib' {
    It 'matches a path equal to or under a OneDrive prefix, case-insensitively' {
        Test-CloudSyncRoot -Path 'C:\Users\Example\OneDrive' -Attributes 'Directory' -Prefix @('c:\users\example\onedrive') |
            Should -BeTrue
        Test-CloudSyncRoot -Path 'C:\Users\Example\OneDrive\Docs\' -Attributes 'Directory' -Prefix @('C:\Users\Example\OneDrive') |
            Should -BeTrue
    }

    It 'does not match a sibling that only shares the prefix text' {
        Test-CloudSyncRoot -Path 'C:\Users\Example\OneDriveX' -Attributes 'Directory' -Prefix @('C:\Users\Example\OneDrive') |
            Should -BeFalse
    }

    It 'matches ReparsePoint plus a cloud bit <Bit> with no prefix set' -ForEach @(
        @{ Bit = 0x40000 }, @{ Bit = 0x80000 }, @{ Bit = 0x100000 }, @{ Bit = 0x400000 }
    ) {
        Test-CloudSyncRoot -Path 'D:\Elsewhere\Synced' -Attributes ([System.Enum]::ToObject([System.IO.FileAttributes], 0x410 -bor $Bit)) -Prefix @() |
            Should -BeTrue
    }

    It 'does not match a plain junction (ReparsePoint without a cloud bit)' {
        Test-CloudSyncRoot -Path 'D:\Elsewhere\Junction' -Attributes ([System.Enum]::ToObject([System.IO.FileAttributes], 0x410)) -Prefix @() |
            Should -BeFalse
    }

    It 'does not match a cloud bit without ReparsePoint' {
        Test-CloudSyncRoot -Path 'D:\Elsewhere\Plain' -Attributes ([System.Enum]::ToObject([System.IO.FileAttributes], 0x400010)) -Prefix @() |
            Should -BeFalse
    }
}

Describe 'Measure-FolderSize' -Tag 'lib' {
    BeforeEach {
        $script:savedOneDrive = @{}
        foreach ($name in $script:OneDriveNames) {
            $script:savedOneDrive[$name] = [System.Environment]::GetEnvironmentVariable($name)
            [System.Environment]::SetEnvironmentVariable($name, $null)
        }
        $script:root = Join-Path $TestDrive ('root-' + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
        $script:rootLong = Get-LongName $script:root
    }

    AfterEach {
        foreach ($name in $script:OneDriveNames) {
            [System.Environment]::SetEnvironmentVariable($name, $script:savedOneDrive[$name])
        }
    }

    It 'sums loose root files and each folder, and ranks the top N by logical bytes' {
        Write-SizedFile -Path (Join-Path $script:root 'loose.bin') -Bytes 7
        Write-SizedFile -Path (Join-Path $script:root 'small\a.bin') -Bytes 100
        Write-SizedFile -Path (Join-Path $script:root 'big\a.bin') -Bytes 200
        Write-SizedFile -Path (Join-Path $script:root 'big\deep\b.bin') -Bytes 100
        Write-SizedFile -Path (Join-Path $script:root 'mid\a.bin') -Bytes 250

        $r = Measure-TestRoot -Root $script:root -Top 2

        $r.scan_complete | Should -BeTrue
        $r.roots[0].status | Should -Be 'scanned'
        $r.roots[0].logical_bytes | Should -Be 657
        $r.roots[0].file_count | Should -Be 5
        @($r.folders).Count | Should -Be 2
        $r.folders[0].path | Should -Be (Join-Path $script:rootLong 'big')
        $r.folders[0].logical_bytes | Should -Be 300
        $r.folders[0].file_count | Should -Be 2
        $r.folders[1].path | Should -Be (Join-Path $script:rootLong 'mid')
        $r.folders[1].logical_bytes | Should -Be 250
    }

    It 'counts a Hidden folder' {
        Write-SizedFile -Path (Join-Path $script:root 'AppData\x.bin') -Bytes 300
        (Get-Item -LiteralPath (Join-Path $script:root 'AppData') -Force).Attributes = 'Directory, Hidden'

        $r = Measure-TestRoot -Root $script:root

        $r.folders[0].path | Should -Be (Join-Path $script:rootLong 'AppData')
        $r.folders[0].logical_bytes | Should -Be 300
    }

    It 'does not descend a junction and counts it once in skipped_reparse_dirs' {
        Write-SizedFile -Path (Join-Path $TestDrive 'outside\target.bin') -Bytes 1000
        Write-SizedFile -Path (Join-Path $script:root 'real\a.bin') -Bytes 10
        New-Item -ItemType Junction -Path (Join-Path $script:root 'real\link') -Target (Join-Path $TestDrive 'outside') | Out-Null

        $r = Measure-TestRoot -Root $script:root

        $r.skipped_reparse_dirs | Should -Be 1
        $r.roots[0].logical_bytes | Should -Be 10
        $r.folders[0].logical_bytes | Should -Be 10
    }

    It 'never descends a folder set as $env:OneDrive and returns it as one size-less item' {
        Write-SizedFile -Path (Join-Path $script:root 'Cloud\doc.bin') -Bytes 500
        Write-SizedFile -Path (Join-Path $script:root 'Cloud\sub\doc.bin') -Bytes 500
        Write-SizedFile -Path (Join-Path $script:root 'Local\a.bin') -Bytes 20
        $cloud = Get-LongName (Join-Path $script:root 'Cloud')
        $env:OneDrive = $cloud

        $r = Measure-TestRoot -Root $script:root

        $skipped = @($r.folders | Where-Object { $_.skip_reason -eq 'cloud-sync-root' })
        $skipped.Count | Should -Be 1
        $skipped[0].path | Should -Be $cloud
        $skipped[0].root | Should -Be $script:rootLong
        $skipped[0].logical_bytes | Should -BeNullOrEmpty
        $skipped[0].allocated_bytes | Should -BeNullOrEmpty
        $skipped[0].file_count | Should -BeNullOrEmpty
        $r.skipped_sync_roots | Should -Be 1
        $r.skipped_reparse_dirs | Should -Be 0
        $r.roots[0].logical_bytes | Should -Be 20
        @($r.folders | Where-Object { $_.path -eq $cloud -and $null -eq $_.skip_reason }).Count | Should -Be 0
    }

    It 'does not walk a root that is itself a junction' {
        Write-SizedFile -Path (Join-Path $TestDrive 'outside-root\sub\target.bin') -Bytes 1000
        $link = Join-Path $script:root 'linked-root'
        New-Item -ItemType Junction -Path $link -Target (Join-Path $TestDrive 'outside-root') | Out-Null

        $r = Measure-TestRoot -Root $link

        $r.roots[0].status | Should -Be 'reparse'
        $r.roots[0].input | Should -Be $link
        $r.roots[0].logical_bytes | Should -BeNullOrEmpty
        $r.skipped_reparse_dirs | Should -Be 1
        @($r.folders).Count | Should -Be 0
    }

    It 'returns the caller''s root string as input on each root and folder' {
        Write-SizedFile -Path (Join-Path $script:root 'a\a.bin') -Bytes 10
        $given = $script:root + '\'

        $r = Measure-TestRoot -Root $given

        $r.roots[0].input | Should -BeExactly $given
        $r.folders[0].input | Should -BeExactly $given
    }

    It 'records a sync root under a later root even when an earlier walk spends the budget' {
        Write-SizedFile -Path (Join-Path $script:root 'first\big\a.bin') -Bytes 10
        Write-SizedFile -Path (Join-Path $script:root 'second\Cloud\doc.bin') -Bytes 10
        $env:OneDrive = Get-LongName (Join-Path $script:root 'second\Cloud')
        $script:budget = New-ScanBudget -Milliseconds 600000
        Mock Invoke-FolderWalk {
            $script:budget.LimitMs = 0
            return [pscustomobject]@{ Bytes = [long]0; FileCount = 0; Complete = $false }
        }

        $r = Measure-TestRoot -Root (Join-Path $script:root 'first'), (Join-Path $script:root 'second') -Budget $script:budget

        $r.scan_complete | Should -BeFalse
        $r.skipped_sync_roots | Should -Be 1
        @($r.folders | Where-Object { $_.skip_reason -eq 'cloud-sync-root' })[0].path | Should -Be $env:OneDrive
    }

    It 'skips a root that lies under a sync root without listing it' {
        Write-SizedFile -Path (Join-Path $script:root 'inner\a.bin') -Bytes 40
        $env:OneDriveCommercial = $script:rootLong

        $r = Measure-TestRoot -Root (Join-Path $script:root 'inner')

        $r.roots[0].status | Should -Be 'cloud-sync-root'
        $r.roots[0].logical_bytes | Should -BeNullOrEmpty
        $r.skipped_sync_roots | Should -Be 1
        $r.folders[0].skip_reason | Should -Be 'cloud-sync-root'
    }

    Context 'access denied' {
        BeforeEach {
            $script:locked = Join-Path $script:root 'locked'
            Write-SizedFile -Path (Join-Path $script:locked 'secret.bin') -Bytes 900
            Write-SizedFile -Path (Join-Path $script:root 'open\a.bin') -Bytes 30
            $script:denyRule = [System.Security.AccessControl.FileSystemAccessRule]::new(
                [System.Security.Principal.WindowsIdentity]::GetCurrent().User,
                [System.Security.AccessControl.FileSystemRights]::ListDirectory,
                [System.Security.AccessControl.AccessControlType]::Deny)
            $info = [System.IO.DirectoryInfo]::new($script:locked)
            $acl = [System.IO.FileSystemAclExtensions]::GetAccessControl($info)
            $acl.AddAccessRule($script:denyRule)
            [System.IO.FileSystemAclExtensions]::SetAccessControl($info, $acl)
        }

        AfterEach {
            $info = [System.IO.DirectoryInfo]::new($script:locked)
            $acl = [System.IO.FileSystemAclExtensions]::GetAccessControl($info)
            [void]$acl.RemoveAccessRule($script:denyRule)
            [System.IO.FileSystemAclExtensions]::SetAccessControl($info, $acl)
        }

        It 'counts an unlistable directory in inaccessible_count and keeps scanning' {
            $r = Measure-TestRoot -Root $script:root

            $r.inaccessible_count | Should -Be 1
            $r.scan_complete | Should -BeTrue
            $r.roots[0].logical_bytes | Should -Be 30
        }
    }

    It 'reports scan_complete = false on a zero budget' {
        Write-SizedFile -Path (Join-Path $script:root 'a\a.bin') -Bytes 10

        $r = Measure-TestRoot -Root $script:root -Budget (New-ScanBudget -Milliseconds 0)

        $r.scan_complete | Should -BeFalse
        $r.roots[0].complete | Should -BeFalse
    }

    It 'leaves the folders after a budget cut in the allocated pass at allocated_bytes = null' {
        Write-SizedFile -Path (Join-Path $script:root 'first\a.bin') -Bytes 300
        Write-SizedFile -Path (Join-Path $script:root 'first\b.bin') -Bytes 300
        Write-SizedFile -Path (Join-Path $script:root 'second\a.bin') -Bytes 200
        Write-SizedFile -Path (Join-Path $script:root 'third\a.bin') -Bytes 100
        $script:budget = New-ScanBudget -Milliseconds 600000
        $script:sizeCalls = 0
        # The budget runs out on the second file read, after the first folder.
        Mock Get-AllocatedSize {
            $script:sizeCalls++
            if ($script:sizeCalls -ge 2) { $script:budget.LimitMs = 0 }
            return [long]4096
        }

        $r = Measure-TestRoot -Root $script:root -Budget $script:budget

        $r.scan_complete | Should -BeTrue
        $r.folders[0].path | Should -Be (Join-Path $script:rootLong 'first')
        $r.folders[0].allocated_bytes | Should -Be 8192
        $r.folders[1].allocated_bytes | Should -BeNullOrEmpty
        $r.folders[2].allocated_bytes | Should -BeNullOrEmpty
        $r.allocated_complete | Should -BeFalse
    }

    It 'gives a folder over the allocated file cap allocated_bytes = null' {
        Write-SizedFile -Path (Join-Path $script:root 'many\a.bin') -Bytes 100
        Write-SizedFile -Path (Join-Path $script:root 'many\b.bin') -Bytes 100
        Write-SizedFile -Path (Join-Path $script:root 'many\c.bin') -Bytes 100
        Write-SizedFile -Path (Join-Path $script:root 'few\a.bin') -Bytes 10
        Mock Get-AllocatedSize { return [long]4096 }

        $r = Measure-TestRoot -Root $script:root -AllocatedFileCap 2

        $many = $r.folders | Where-Object { $_.path -eq (Join-Path $script:rootLong 'many') }
        $few = $r.folders | Where-Object { $_.path -eq (Join-Path $script:rootLong 'few') }
        $many.allocated_bytes | Should -BeNullOrEmpty
        $few.allocated_bytes | Should -Be 4096
        $r.allocated_complete | Should -BeFalse
    }

    It 'reads allocated bytes through GetCompressedFileSizeW for a folder under the cap' {
        Write-SizedFile -Path (Join-Path $script:root 'real\a.bin') -Bytes 5000

        $r = Measure-TestRoot -Root $script:root

        $r.allocated_complete | Should -BeTrue
        $r.folders[0].allocated_bytes | Should -BeOfType [long]
        $r.folders[0].allocated_bytes | Should -BeGreaterThan 0
    }

    It 'reports a missing root as absent without failing the scan' {
        $r = Measure-TestRoot -Root (Join-Path $script:root 'nope')

        $r.roots[0].status | Should -Be 'absent'
        $r.scan_complete | Should -BeTrue
        @($r.folders).Count | Should -Be 0
    }
}
