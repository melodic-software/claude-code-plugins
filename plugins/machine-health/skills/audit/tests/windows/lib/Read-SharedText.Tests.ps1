#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Read-SharedText.ps1 -- the shared-open text read
behind Get-ApprovalState and Get-MuteState.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Read-SharedText.ps1'
    # Non-ASCII, so a read that ignored the UTF-8 encoding would garble it.
    $script:text = '{"a":"caf' + [char]0xE9 + '"}'
}

Describe 'Read-SharedText' -Tag 'lib' {
    BeforeEach {
        $script:path = Join-Path $TestDrive "$([guid]::NewGuid().ToString('n')).json"
        Set-Content -LiteralPath $script:path -Value $script:text -Encoding utf8BOM -NoNewline
    }

    It 'returns the whole text without the byte-order mark' {
        Read-SharedText -Path $script:path | Should -BeExactly $script:text
    }

    It 'reads while another handle holds the file with ReadWrite' {
        $holder = [System.IO.File]::Open($script:path, 'Open', 'ReadWrite', 'ReadWrite')
        try {
            Read-SharedText -Path $script:path | Should -BeExactly $script:text
        } finally {
            $holder.Dispose()
        }
    }

    It 'reads while another handle holds delete access, as a replacing writer does' {
        $holder = [System.IO.FileStream]::new($script:path, 'Open', 'ReadWrite',
            [System.IO.FileShare]'ReadWrite, Delete', 4096, [System.IO.FileOptions]::DeleteOnClose)
        try {
            Read-SharedText -Path $script:path | Should -BeExactly $script:text
        } finally {
            $holder.Dispose()
        }
    }

    It 'throws for a missing file' {
        { Read-SharedText -Path (Join-Path $TestDrive 'missing.json') } | Should -Throw
    }
}
