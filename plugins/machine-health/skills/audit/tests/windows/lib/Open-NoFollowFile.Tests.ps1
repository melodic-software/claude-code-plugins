#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Open-NoFollowFile.ps1. Expected file IDs come from
fsutil and Win32_LogicalDisk, and from what a hard link is: a second name for
the same file.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Open-NoFollowFile.ps1'

    function Get-IdentityOf {
        param([string] $Path)
        $handle = Open-NoFollowFile -Path $Path
        try { Get-FileIdentity -Handle $handle } finally { $handle.Dispose() }
    }
}

Describe 'Open-NoFollowFile and Get-FileIdentity' -Tag 'lib' {
    BeforeEach {
        $script:dir = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:dir | Out-Null
        $script:file = Join-Path $script:dir 'a.json'
        Set-Content -LiteralPath $script:file -Value 'a' -NoNewline
    }

    It 'returns the volume serial and file index that fsutil and Win32_LogicalDisk report' {
        $identity = Get-IdentityOf $script:file

        $fsutil = (& fsutil file queryfileid $script:file) -join ' '
        $fsutil | Should -Match '0x([0-9a-fA-F]{32})'
        $index = ([regex]::Match($fsutil, '0x([0-9a-fA-F]{32})').Groups[1].Value).Substring(16).ToUpperInvariant()
        $drive = [System.IO.Path]::GetPathRoot($script:file).TrimEnd('\')
        $serial = (Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$drive'").VolumeSerialNumber

        $identity.FileId | Should -BeExactly "$($serial.ToUpperInvariant())-$index"
        $identity.IsReparsePoint | Should -BeFalse
        $identity.IsDirectory | Should -BeFalse
    }

    It 'gives two names of one hard-linked file the same ID and a different file another' {
        $link = Join-Path $script:dir 'link.json'
        New-Item -ItemType HardLink -Path $link -Target $script:file | Out-Null
        $other = Join-Path $script:dir 'other.json'
        Set-Content -LiteralPath $other -Value 'b' -NoNewline

        (Get-IdentityOf $link).FileId | Should -BeExactly (Get-IdentityOf $script:file).FileId
        (Get-IdentityOf $other).FileId | Should -Not -Be (Get-IdentityOf $script:file).FileId
    }

    It 'opens a symbolic link as itself, flagged as a reparse point' {
        $link = Join-Path $script:dir 'symlink.json'
        New-Item -ItemType SymbolicLink -Path $link -Target $script:file | Out-Null

        $identity = Get-IdentityOf $link
        $identity.IsReparsePoint | Should -BeTrue
        $identity.FileId | Should -Not -Be (Get-IdentityOf $script:file).FileId
    }

    It 'opens a file whose path is longer than MAX_PATH, keeping the ID it had before a rename moved it there' {
        $deep = $script:dir
        while ($deep.Length -lt 300) { $deep = Join-Path $deep ('d' * 40) }
        [void][System.IO.Directory]::CreateDirectory($deep)
        $long = Join-Path $deep 'elevated-result.json'
        $long.Length | Should -BeGreaterThan 260
        $shortId = (Get-IdentityOf $script:file).FileId

        # A rename on one volume keeps the file record, so the ID must not change.
        [System.IO.File]::Move($script:file, $long)

        (Get-IdentityOf $long).FileId | Should -BeExactly $shortId
    }

    It 'refuses to open a junction' {
        $targetDir = Join-Path $script:dir 'target'
        New-Item -ItemType Directory -Path $targetDir | Out-Null
        $junction = Join-Path $script:dir 'junction'
        New-Item -ItemType Junction -Path $junction -Target $targetDir | Out-Null

        { Open-NoFollowFile -Path $junction } | Should -Throw '*Cannot open*'
    }

    It 'refuses a missing file and creates none' {
        $missing = Join-Path $script:dir 'missing.json'

        { Open-NoFollowFile -Path $missing -Access ReadWrite } | Should -Throw '*Cannot open*'
        Test-Path -LiteralPath $missing | Should -BeFalse
    }
}
