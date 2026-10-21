#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/checks/Test-StorageTopN.ps1.

.DESCRIPTION
Measure-FolderSize is mocked, so no test walks the real disk; the adapter's own
walk is covered by tests/windows/lib/Measure-FolderSize.Tests.ps1. Each mocked
record is built from literal sizes, and every expected total below is summed by
hand from those literals.

Mock bodies run in the check script's scope, where this file's $script:
variables are not visible, so each mock spells its paths out.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -Check 'Test-StorageTopN' -LibScript 'New-FindingItem.ps1', 'Measure-FolderSize.ps1'

    function Invoke-StorageTopNAsObject {
        param([string[]] $MutedKeys = @())
        return ConvertFrom-CheckOutput (& $script:ScriptPath -MutedKeys $MutedKeys)
    }

    function New-Folder {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Pure constructor: builds and returns an object, changes no system state.')]
        param([string] $Root, [string] $Path, [long] $Bytes, [Nullable[long]] $Allocated = $null)
        return [pscustomobject]@{
            input = $Root; root = $Root; path = $Path; logical_bytes = $Bytes; allocated_bytes = $Allocated
            file_count = 3; complete = $true; skip_reason = $null
        }
    }

    function New-SyncRootFolder {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Pure constructor: builds and returns an object, changes no system state.')]
        param([string] $Root, [string] $Path)
        return [pscustomobject]@{
            input = $Root; root = $Root; path = $Path; logical_bytes = $null; allocated_bytes = $null
            file_count = $null; complete = $null; skip_reason = 'cloud-sync-root'
        }
    }

    function New-ScanRecord {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Pure constructor: builds and returns an object, changes no system state.')]
        param(
            [object[]] $Roots = @(),
            [object[]] $Folders = @(),
            [bool] $ScanComplete = $true,
            [int] $SyncRoots = 0
        )
        return [pscustomobject]@{
            roots                = @($Roots)
            folders              = @($Folders)
            scan_complete        = $ScanComplete
            allocated_complete   = $true
            inaccessible_count   = 2
            skipped_reparse_dirs = 5
            skipped_sync_roots   = $SyncRoots
        }
    }

    function New-RootRecord {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Pure constructor: builds and returns an object, changes no system state.')]
        param([string] $Path, [long] $Bytes, [string] $Status = 'scanned')
        return [pscustomobject]@{ input = $Path; path = $Path; status = $Status; logical_bytes = $Bytes; file_count = 10; complete = $true }
    }

    function New-MutesScan {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Pure constructor: builds and returns an object, changes no system state.')]
        param([bool] $Complete)
        return New-ScanRecord -ScanComplete $Complete -Roots @(New-RootRecord -Path 'C:\Users\Example' -Bytes 300) -Folders @(
            New-Folder -Root 'C:\Users\Example' -Path 'C:\Users\Example\A' -Bytes 200
            New-Folder -Root 'C:\Users\Example' -Path 'C:\Users\Example\B' -Bytes 100
        )
    }
}

Describe 'Test-StorageTopN' -Tag 'check' {
    It 'emits a schema-valid INFO result with one folder item per listed folder' {
        Mock Measure-FolderSize {
            New-ScanRecord -Roots @(New-RootRecord -Path 'C:\Users\Example' -Bytes 5000) -Folders @(
                New-Folder -Root 'C:\Users\Example' -Path 'C:\Users\Example\AppData' -Bytes 3000 -Allocated 3072
                New-Folder -Root 'C:\Users\Example' -Path 'C:\Users\Example\Downloads' -Bytes 1500
            )
        }

        $result = Invoke-StorageTopNAsObject

        { Assert-CheckResult $result } | Should -Not -Throw
        $result.id | Should -Be 'storage-top-n'
        $result.category | Should -Be 'storage'
        $result.needs_admin | Should -BeFalse
        $result.ran_successfully | Should -BeTrue
        $result.severity | Should -Be 'INFO'
        $result.detail.items_count | Should -Be 2
        $result.detail.muted_count | Should -Be 0
        $result.detail.top1_bytes | Should -Be 3000
        $result.detail.inaccessible_count | Should -Be 2
        $result.detail.skipped_reparse_dirs | Should -Be 5
        $first = $result.detail.items[0]
        $first.key | Should -MatchExactly '^folder:[0-9a-f]{16}$'
        $first.severity | Should -Be 'INFO'
        $first.path | Should -Be 'C:\Users\Example\AppData'
        $first.logical_bytes | Should -Be 3000
        $first.allocated_bytes | Should -Be 3072
        $result.detail.items[1].allocated_bytes | Should -BeNullOrEmpty
        $result.summary | Should -Match ([regex]::Escape('C:\Users\Example\AppData'))
    }

    It 'sizes the profile and the reclaim locations with the catalog limits' {
        Mock Measure-FolderSize { New-ScanRecord }

        $null = Invoke-StorageTopNAsObject

        # 15 per root, 10,000 files and 60 s: check-catalog.md section 20.
        Should -Invoke Measure-FolderSize -Times 1 -Exactly -ParameterFilter {
            ($Root -contains $env:USERPROFILE) -and ($Root -contains $env:TEMP) -and
            (@($Root | Where-Object { $_ -like '*\Windows.old' }).Count -eq 1) -and
            (@($Root | Where-Object { $_ -like '*\Package Cache' }).Count -eq 1) -and
            (@($Root | Where-Object { $_ -like '*\$Recycle.Bin\S-1-*' }).Count -eq 1) -and
            $Top -eq 15 -and $AllocatedFileCap -eq 10000 -and $Budget.LimitMs -eq 60000
        }
    }

    It 'tags a folder under the temp root with reclaim_hint temp and a profile folder with none' {
        Mock Measure-FolderSize {
            New-ScanRecord -Roots @(New-RootRecord -Path $env:TEMP -Bytes 100) -Folders @(
                New-Folder -Root $env:TEMP -Path 'C:\Example\Temp\setup-cache' -Bytes 100
                New-Folder -Root $env:USERPROFILE -Path 'C:\Example\Profile\Videos' -Bytes 50
            )
        }

        $result = Invoke-StorageTopNAsObject

        ($result.detail.items | Where-Object { $_.path -eq 'C:\Example\Temp\setup-cache' }).reclaim_hint | Should -Be 'temp'
        ($result.detail.items | Where-Object { $_.path -eq 'C:\Example\Profile\Videos' }).reclaim_hint | Should -BeNullOrEmpty
        $result.detail.roots[0].reclaim_hint | Should -Be 'temp'
    }

    It 'lists a skipped sync root as a size-less item titled "skipped: cloud sync root"' {
        Mock Measure-FolderSize {
            New-ScanRecord -SyncRoots 1 -Roots @(New-RootRecord -Path 'C:\Users\Example' -Bytes 10) -Folders @(
                New-SyncRootFolder -Root 'C:\Users\Example' -Path 'C:\Users\Example\OneDrive'
            )
        }

        $result = Invoke-StorageTopNAsObject

        { Assert-CheckResult $result } | Should -Not -Throw
        $result.detail.skipped_sync_roots | Should -Be 1
        $item = $result.detail.items[0]
        $item.skip_reason | Should -Be 'cloud-sync-root'
        $item.title | Should -Be 'C:\Users\Example\OneDrive (skipped: cloud sync root)'
        $item.logical_bytes | Should -BeNullOrEmpty
        $item.severity | Should -Be 'INFO'
    }

    It 'counts a nested root once in scanned_bytes' {
        Mock Measure-FolderSize {
            New-ScanRecord -Roots @(
                New-RootRecord -Path 'C:\Users\Example\AppData\Local\Temp' -Bytes 300
                New-RootRecord -Path 'C:\Windows.old' -Bytes 50
                New-RootRecord -Path 'C:\$Recycle.Bin\S-1-5-21-0' -Bytes 0 -Status 'absent'
                New-RootRecord -Path 'C:\Users\Example' -Bytes 1000
            )
        }

        $result = Invoke-StorageTopNAsObject

        # 1000 (profile, which holds the 300 of Temp) + 50 (Windows.old).
        $result.detail.scanned_bytes | Should -Be 1050
    }

    Context 'mutes' {
        BeforeEach {
            $script:keyA = Get-FindingKey -Kind 'folder' -Identity @('C:\Users\Example\A')
            $script:keyB = Get-FindingKey -Kind 'folder' -Identity @('C:\Users\Example\B')
        }

        It 'marks a muted item and keeps it in items' {
            Mock Measure-FolderSize { New-MutesScan -Complete $true }

            $result = Invoke-StorageTopNAsObject -MutedKeys @($script:keyA)

            $result.detail.items_count | Should -Be 2
            $result.detail.muted_count | Should -Be 1
            ($result.detail.items | Where-Object { $_.key -eq $script:keyA }).muted | Should -BeTrue
            ($result.detail.items | Where-Object { $_.key -eq $script:keyB }).muted | Should -BeFalse
            $result.severity | Should -Be 'INFO'
        }

        It 'reports OK when every item is muted and the scan completed' {
            Mock Measure-FolderSize { New-MutesScan -Complete $true }

            $result = Invoke-StorageTopNAsObject -MutedKeys @($script:keyA, $script:keyB)

            $result.severity | Should -Be 'OK'
        }

        It 'reports UNKNOWN when every item is muted and the budget cut the scan' {
            Mock Measure-FolderSize { New-MutesScan -Complete $false }

            $result = Invoke-StorageTopNAsObject -MutedKeys @($script:keyA, $script:keyB)

            { Assert-CheckResult $result } | Should -Not -Throw
            $result.severity | Should -Be 'UNKNOWN'
            $result.detail.scan_complete | Should -BeFalse
        }
    }

    It 'sizes a real tree end to end through the test-only -RootPath override' {
        $tree = Join-Path $TestDrive ('tree-' + [guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path (Join-Path $tree 'big') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tree 'small') -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $tree 'big\a.bin'), [byte[]]::new(3000))
        [System.IO.File]::WriteAllBytes((Join-Path $tree 'small\a.bin'), [byte[]]::new(100))
        $long = (Get-Item -LiteralPath $tree -Force).FullName.TrimEnd('\')

        $result = ConvertFrom-CheckOutput (& $script:ScriptPath -RootPath $tree)

        { Assert-CheckResult $result } | Should -Not -Throw
        $result.severity | Should -Be 'INFO'
        $result.detail.scan_complete | Should -BeTrue
        $result.detail.allocated_complete | Should -BeTrue
        $result.detail.scanned_bytes | Should -Be 3100
        $result.detail.items_count | Should -Be 2
        $result.detail.items[0].path | Should -Be (Join-Path $long 'big')
        $result.detail.items[0].logical_bytes | Should -Be 3000
        $result.detail.items[0].reclaim_hint | Should -BeNullOrEmpty
        $result.detail.items[0].allocated_bytes | Should -BeGreaterThan 0
        $result.detail.roots[0].status | Should -Be 'scanned'
    }

    It 'reports a failed UNKNOWN result when the adapter throws' {
        Mock Measure-FolderSize { throw 'walk exploded' }

        $result = Invoke-StorageTopNAsObject

        { Assert-CheckResult $result } | Should -Not -Throw
        $result.severity | Should -Be 'UNKNOWN'
        $result.ran_successfully | Should -BeFalse
    }
}
