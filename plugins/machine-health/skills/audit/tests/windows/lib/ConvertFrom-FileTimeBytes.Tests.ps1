#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'ConvertFrom-FileTimeBytes.ps1'

    # 2026-03-04T05:06:07Z as a FILETIME, computed by hand:
    # (1772600767 Unix seconds + 11644473600) * 10^7.
    $script:FileTime = [long]134170743670000000
    $script:Expected = [datetime]::new(2026, 3, 4, 5, 6, 7, [DateTimeKind]::Utc)

    function New-Value {
        param([int] $Length, [int] $Offset, [long] $FileTime)
        $bytes = [byte[]]::new($Length)
        [BitConverter]::GetBytes($FileTime).CopyTo($bytes, $Offset)
        return , $bytes
    }
}

Describe 'ConvertFrom-FileTimeBytes' -Tag 'lib' {
    It 'reads the UTC time at offset <Offset>' -ForEach @(
        @{ Offset = 0 }
        @{ Offset = 4 }
        @{ Offset = 60 }
    ) {
        $bytes = New-Value -Length 72 -Offset $Offset -FileTime $script:FileTime
        $time = ConvertFrom-FileTimeBytes -Bytes $bytes -Offset $Offset
        $time | Should -Be $script:Expected
        $time.Kind | Should -Be ([DateTimeKind]::Utc)
    }

    It 'returns nothing when the value is too short to hold 8 bytes at the offset' {
        ConvertFrom-FileTimeBytes -Bytes ([byte[]]::new(11)) -Offset 4 | Should -BeNullOrEmpty
    }

    It 'returns nothing for a zero time' {
        ConvertFrom-FileTimeBytes -Bytes ([byte[]]::new(12)) -Offset 4 | Should -BeNullOrEmpty
    }

    It 'returns nothing, rather than throwing, for a time past the DateTime range' {
        $bytes = New-Value -Length 8 -Offset 0 -FileTime ([long]::MaxValue)
        { ConvertFrom-FileTimeBytes -Bytes $bytes -Offset 0 } | Should -Not -Throw
        ConvertFrom-FileTimeBytes -Bytes $bytes -Offset 0 | Should -BeNullOrEmpty
    }
}
