#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Remove-OldCheckupView.ps1 -- views/ retention by
exact paths, newest 12 runs kept.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Remove-OldCheckupView.ps1'

    # Run n of 14 has the stamp 2026-01-<n>T000000000Z, so run 14 is the newest.
    function Get-Stamp([int] $N) { '2026-01-{0:D2}T000000000Z' -f $N }
    function Add-ViewRun([string] $Dir, [int] $N) {
        foreach ($suffix in '.html', '.json', '.ids.json') {
            Set-Content -LiteralPath (Join-Path $Dir "checkup-$(Get-Stamp $N)$suffix") -Value 'x'
        }
    }
}

Describe 'Remove-OldCheckupView' -Tag 'lib' {
    BeforeEach {
        $script:Views = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $script:Views | Out-Null
        foreach ($n in 1..14) { Add-ViewRun $script:Views $n }
        Set-Content -LiteralPath (Join-Path $script:Views 'notes.txt') -Value 'keep me'
        Set-Content -LiteralPath (Join-Path $script:Views 'checkup-2026-01-01T000000000Z.html.bak') -Value 'keep me'
    }

    It 'deletes the three exact paths of the two oldest of 14 runs and keeps the newest 12' {
        $deleted = @(Remove-OldCheckupView -ViewsDir $script:Views -CurrentStamp (Get-Stamp 14))

        $deleted.Count | Should -Be 6
        foreach ($n in 1, 2) {
            foreach ($suffix in '.html', '.json', '.ids.json') {
                Join-Path $script:Views "checkup-$(Get-Stamp $n)$suffix" | Should -Not -Exist
            }
        }
        foreach ($n in 3..14) {
            Join-Path $script:Views "checkup-$(Get-Stamp $n).ids.json" | Should -Exist
        }
    }

    It 'leaves files that are not a run page alone' {
        Remove-OldCheckupView -ViewsDir $script:Views -CurrentStamp (Get-Stamp 14) | Out-Null

        Join-Path $script:Views 'notes.txt' | Should -Exist
        Join-Path $script:Views 'checkup-2026-01-01T000000000Z.html.bak' | Should -Exist
    }

    It 'deletes nothing when the current run has no complete page (the build failed)' {
        Remove-Item -LiteralPath (Join-Path $script:Views "checkup-$(Get-Stamp 14).html")

        $deleted = @(Remove-OldCheckupView -ViewsDir $script:Views -CurrentStamp (Get-Stamp 14))

        $deleted.Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $script:Views -File).Count | Should -Be (14 * 3 - 1 + 2)
    }

    It 'deletes nothing with 12 runs or fewer' {
        foreach ($n in 1, 2) {
            foreach ($suffix in '.html', '.json', '.ids.json') {
                Remove-Item -LiteralPath (Join-Path $script:Views "checkup-$(Get-Stamp $n)$suffix")
            }
        }

        @(Remove-OldCheckupView -ViewsDir $script:Views -CurrentStamp (Get-Stamp 14)).Count | Should -Be 0
    }

    It 'deletes nothing under -WhatIf' {
        @(Remove-OldCheckupView -ViewsDir $script:Views -CurrentStamp (Get-Stamp 14) -WhatIf).Count | Should -Be 0
        Join-Path $script:Views "checkup-$(Get-Stamp 1).html" | Should -Exist
    }
}
