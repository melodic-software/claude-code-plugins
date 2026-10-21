#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Assert-StateBaseLocation.ps1 -- the sync-root
rule: a OneDrive variable prefixing the path flags it; the path or an ancestor
carrying ReparsePoint plus a cloud attribute bit only warns, as does an
ordinary junction.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Assert-StateBaseLocation.ps1'
    $script:vars = @('OneDrive', 'OneDriveConsumer', 'OneDriveCommercial')
    $script:saved = @{}
    foreach ($v in $script:vars) { $script:saved[$v] = [Environment]::GetEnvironmentVariable($v) }

    function New-Junction {
        [CmdletBinding(SupportsShouldProcess = $true)]
        param([string] $Name)
        $link = Join-Path $TestDrive $Name
        if ($PSCmdlet.ShouldProcess($link, 'Create junction')) {
            $target = Join-Path $TestDrive "$Name-target"
            New-Item -ItemType Directory -Path $target -Force | Out-Null
            New-Item -ItemType Junction -Path $link -Target $target | Out-Null
        }
        return $link
    }
}

AfterAll {
    foreach ($v in $script:vars) { [Environment]::SetEnvironmentVariable($v, $script:saved[$v]) }
}

Describe 'Assert-StateBaseLocation' -Tag 'lib' {
    BeforeEach {
        foreach ($v in $script:vars) { [Environment]::SetEnvironmentVariable($v, $null) }
    }

    It 'flags a path under $env:<Variable>' -ForEach @(
        @{ Variable = 'OneDrive' }
        @{ Variable = 'OneDriveConsumer' }
        @{ Variable = 'OneDriveCommercial' }
    ) {
        $root = Join-Path $TestDrive "sync-$Variable"
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        [Environment]::SetEnvironmentVariable($Variable, $root)

        $result = Assert-StateBaseLocation -Path (Join-Path $root 'machine-health')

        $result.Synced | Should -BeTrue
        $result.Rule | Should -Be "`$env:$Variable"
        $result.Folder | Should -Be $root
    }

    It 'flags the variable folder itself, matching case-insensitively' {
        $root = Join-Path $TestDrive 'SyncRoot'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $env:OneDrive = $root

        (Assert-StateBaseLocation -Path $root.ToLowerInvariant()).Synced | Should -BeTrue
    }

    It 'does not flag a sibling whose name only starts with the variable folder' {
        $root = Join-Path $TestDrive 'OneDrive'
        $env:OneDrive = $root
        $sibling = Join-Path $TestDrive 'OneDriveBackup'
        New-Item -ItemType Directory -Path $sibling -Force | Out-Null

        (Assert-StateBaseLocation -Path $sibling).Synced | Should -BeFalse
    }

    # Only PINNED and UNPINNED stick when set through the file attributes; NTFS drops the two
    # RECALL bits, so no TestDrive folder can carry them.
    It 'warns but does not flag a folder under a ReparsePoint carrying cloud bit <Bit> with the variables unset' -ForEach @(
        @{ Bit = '0x80000'; Value = 0x80000 }
        @{ Bit = '0x100000'; Value = 0x100000 }
    ) {
        $link = New-Junction -Name "cloud-$Bit"
        $info = [System.IO.DirectoryInfo]::new($link)
        try {
            $info.Attributes = [Enum]::ToObject([System.IO.FileAttributes], ([int]$info.Attributes -bor $Value))
        } catch {
            Set-ItResult -Skipped -Because "this file system refused attribute $Bit on a junction: $($_.Exception.Message)"
            return
        }
        if (([int][System.IO.DirectoryInfo]::new($link).Attributes -band $Value) -eq 0) {
            Set-ItResult -Skipped -Because "this file system did not keep attribute $Bit on a junction"
            return
        }

        $result = Assert-StateBaseLocation -Path (Join-Path $link 'state-base\not-created-yet') -WarningVariable warned -WarningAction SilentlyContinue

        $result.Synced | Should -BeFalse
        $result.Rule | Should -BeNullOrEmpty
        @($warned).Count | Should -Be 1
        "$($warned[0])" | Should -BeLike "*$link*"
        "$($warned[0])" | Should -BeLike "*$Bit*"
    }

    It 'warns but does not flag a path under an ordinary junction' {
        $link = New-Junction -Name 'plain-junction'

        $result = Assert-StateBaseLocation -Path (Join-Path $link 'state-base') -WarningVariable warned -WarningAction SilentlyContinue

        $result.Synced | Should -BeFalse
        @($warned).Count | Should -Be 1
        "$($warned[0])" | Should -BeLike "*$link*"
    }

    It 'neither flags nor warns for a plain folder' {
        $plain = Join-Path $TestDrive 'plain'
        New-Item -ItemType Directory -Path $plain -Force | Out-Null

        $result = Assert-StateBaseLocation -Path $plain -WarningVariable warned -WarningAction SilentlyContinue

        $result.Synced | Should -BeFalse
        $result.Rule | Should -BeNullOrEmpty
        $warned | Should -BeNullOrEmpty
    }
}
