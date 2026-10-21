#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-ElevatedAppEvidence.ps1'

    # 2026-03-04T05:06:07Z as a FILETIME, computed by hand:
    # (1772600767 Unix seconds + 11644473600) * 10^7.
    $script:LaunchFileTime = [long]134170743670000000
    $script:LaunchedAt = [datetime]::new(2026, 3, 4, 5, 6, 7, [DateTimeKind]::Utc)
    $script:Older = [datetime]::new(2026, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
    $script:Newer = [datetime]::new(2026, 2, 1, 0, 0, 0, [DateTimeKind]::Utc)

    function New-BamValue {
        param([long] $FileTime)
        $bytes = [byte[]]::new(24)
        [BitConverter]::GetBytes($FileTime).CopyTo($bytes, 0)
        return , $bytes
    }
}

Describe 'Get-ElevatedAppEvidence' -Tag 'lib' {
    Context 'Prefetch' {
        BeforeEach { Mock Get-ItemProperty { throw [System.Security.SecurityException]::new('denied') } }

        It 'keeps the latest write time per executable and ignores other files' {
            Mock Get-ChildItem {
                [pscustomobject]@{ Name = 'EDITOR.EXE-0A1B2C3D.pf'; LastWriteTimeUtc = $script:Older }
                [pscustomobject]@{ Name = 'EDITOR.EXE-4E5F6071.pf'; LastWriteTimeUtc = $script:Newer }
                [pscustomobject]@{ Name = 'Layout.ini'; LastWriteTimeUtc = $script:Newer }
            }

            $prefetch = (Get-ElevatedAppEvidence) | Where-Object Source -EQ 'prefetch'

            $prefetch.ReadState | Should -Be 'ok'
            @($prefetch.Entries).Count | Should -Be 1
            $prefetch.Entries[0].ExeName | Should -Be 'editor.exe'
            $prefetch.Entries[0].LastRun | Should -Be $script:Newer
        }

        It 'reports denied, never zero launches, when the unfiltered listing is refused' {
            Mock Get-ChildItem { throw [System.UnauthorizedAccessException]::new('denied') }

            $prefetch = (Get-ElevatedAppEvidence) | Where-Object Source -EQ 'prefetch'

            $prefetch.ReadState | Should -Be 'denied'
            @($prefetch.Entries).Count | Should -Be 0
        }

        It 'reports absent when the folder lists but holds no prefetch file' {
            Mock Get-ChildItem { [pscustomobject]@{ Name = 'Layout.ini'; LastWriteTimeUtc = $script:Newer } }
            ((Get-ElevatedAppEvidence) | Where-Object Source -EQ 'prefetch').ReadState | Should -Be 'absent'
        }
    }

    Context 'BAM' {
        BeforeEach { Mock Get-ChildItem { throw [System.UnauthorizedAccessException]::new('denied') } }

        It 'reads the volume-relative path and last run, skipping non-path values' {
            Mock Get-ItemProperty {
                [pscustomobject]@{
                    PSPath                                         = 'Registry::fixture'
                    Version                                        = 1
                    SequenceNumber                                 = 9
                    '\Device\HarddiskVolume3\Apps\Editor\Editor.exe' = (New-BamValue -FileTime $script:LaunchFileTime)
                    'Contoso.Notes_abc123'                         = (New-BamValue -FileTime $script:LaunchFileTime)
                }
            }

            $bam = (Get-ElevatedAppEvidence) | Where-Object Source -EQ 'bam'

            $bam.ReadState | Should -Be 'ok'
            @($bam.Entries).Count | Should -Be 1
            $bam.Entries[0].Path | Should -Be '\Apps\Editor\Editor.exe'
            $bam.Entries[0].ExeName | Should -Be 'editor.exe'
            $bam.Entries[0].LastRun | Should -Be $script:LaunchedAt
        }

        It 'reports denied without elevation' {
            Mock Get-ItemProperty { throw [System.Security.SecurityException]::new('denied') }
            ((Get-ElevatedAppEvidence) | Where-Object Source -EQ 'bam').ReadState | Should -Be 'denied'
        }
    }
}
