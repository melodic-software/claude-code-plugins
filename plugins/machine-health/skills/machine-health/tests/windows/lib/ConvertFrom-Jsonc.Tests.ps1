#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/ConvertFrom-Jsonc.ps1 -- a JSONC (JSON with
Comments) parser.

.DESCRIPTION
The catalog and other author-facing files use JSONC. The previous regex-based
stripper in the orchestrator mangled URLs (https://), path separators, and
escaped quotes. These tests pin the state-machine behavior: comments strip,
string contents are preserved verbatim, block comments are supported, and
line numbers are preserved for downstream parse-error reporting.
#>

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:LibRoot = Join-Path (Split-Path -Parent $script:TestsRoot) 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'ConvertFrom-Jsonc.ps1')
}

Describe 'Remove-JsoncComment' -Tag 'lib' {
    Context 'line comments' {
        It 'strips a trailing // comment' {
            $in = '{ "x": 1 } // trailing'
            $out = Remove-JsoncComment -Text $in
            $out.Trim() | Should -Be '{ "x": 1 }'
        }

        It 'strips a full-line // comment' {
            $in = "// header`n{`n  `"x`": 1`n}"
            $out = Remove-JsoncComment -Text $in
            ($out | ConvertFrom-Json).x | Should -Be 1
        }

        It 'preserves // inside a string literal (URL scheme)' {
            $in = '{ "url": "https://example.com/path" }'
            $out = Remove-JsoncComment -Text $in
            ($out | ConvertFrom-Json).url | Should -Be 'https://example.com/path'
        }

        It 'preserves // inside a string and strips a trailing comment on the same line' {
            $in = '{ "url": "https://example.com" } // docs link'
            $out = Remove-JsoncComment -Text $in
            $parsed = $out | ConvertFrom-Json
            $parsed.url | Should -Be 'https://example.com'
        }

        It 'preserves a // inside a string that ends near the line end' {
            $in = '{ "pattern": "a//b" } // trailing'
            $out = Remove-JsoncComment -Text $in
            ($out | ConvertFrom-Json).pattern | Should -Be 'a//b'
        }
    }

    Context 'block comments' {
        It 'strips a single-line /* */ comment' {
            $in = '{ /* hello */ "x": 1 }'
            $out = Remove-JsoncComment -Text $in
            ($out | ConvertFrom-Json).x | Should -Be 1
        }

        It 'strips a multi-line block comment and preserves newlines for line numbers' {
            $in = "{`n  /*`n    hello`n  */`n  `"x`": 1`n}"
            $out = Remove-JsoncComment -Text $in
            ($out | ConvertFrom-Json).x | Should -Be 1
            ($out -split "`n").Count | Should -BeGreaterOrEqual 5
        }

        It 'preserves /* inside a string literal' {
            $in = '{ "pattern": "/* not a comment */" }'
            $out = Remove-JsoncComment -Text $in
            ($out | ConvertFrom-Json).pattern | Should -Be '/* not a comment */'
        }
    }

    Context 'escape sequences inside strings' {
        It 'handles escaped quotes without ending the string early' {
            $in = '{ "q": "he said \"hi\" // still in string" }'
            $out = Remove-JsoncComment -Text $in
            ($out | ConvertFrom-Json).q | Should -Be 'he said "hi" // still in string'
        }

        It 'handles backslash-backslash correctly (Windows paths)' {
            $in = '{ "path": "C:\\Users\\me" }'
            $out = Remove-JsoncComment -Text $in
            ($out | ConvertFrom-Json).path | Should -Be 'C:\Users\me'
        }
    }

    Context 'boundary cases' {
        It 'returns empty string for empty input' {
            Remove-JsoncComment -Text '' | Should -Be ''
        }

        It 'preserves input that has no comments' {
            $in = '{ "x": 1, "y": [1, 2, 3] }'
            (Remove-JsoncComment -Text $in).Trim() | Should -Be $in
        }

        It 'tolerates an unterminated block comment gracefully (strips to EOF)' {
            $in = "{ `"x`": 1 /* forgotten close"
            $out = Remove-JsoncComment -Text $in
            # The unterminated comment consumes the rest -- parser will fail, but
            # the function itself must not throw.
            $out | Should -Not -BeNull
        }

        It 'accepts pipeline input' {
            $out = '{ "x": 1 } // tail' | Remove-JsoncComment
            ($out | ConvertFrom-Json).x | Should -Be 1
        }
    }
}

Describe 'ConvertFrom-Jsonc' -Tag 'lib' {
    It 'parses a JSONC document with mixed comments' {
        $doc = @'
{
  // header comment
  "name": "test",
  /* block
     comment */
  "values": [1, 2, 3],
  "url": "https://example.com" // trailing
}
'@
        $parsed = $doc | ConvertFrom-Jsonc
        $parsed.name | Should -Be 'test'
        $parsed.values.Count | Should -Be 3
        $parsed.url | Should -Be 'https://example.com'
    }

    It 'returns $null for empty or whitespace-only input' {
        ConvertFrom-Jsonc -InputText '' | Should -BeNullOrEmpty
        ConvertFrom-Jsonc -InputText '   ' | Should -BeNullOrEmpty
        ConvertFrom-Jsonc -InputText "// only a comment`n" | Should -BeNullOrEmpty
    }

    It 'honors the -Depth parameter for nested structures' {
        $deep = '{ "a": { "b": { "c": { "d": { "e": "leaf" } } } } }'
        $parsed = ConvertFrom-Jsonc -InputText $deep -Depth 10
        $parsed.a.b.c.d.e | Should -Be 'leaf'
    }

    It 'throws on malformed JSON after comment stripping' {
        { ConvertFrom-Jsonc -InputText '{ "x": // broken' } | Should -Throw
    }
}
