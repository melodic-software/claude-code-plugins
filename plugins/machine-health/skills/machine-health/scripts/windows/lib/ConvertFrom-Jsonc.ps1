#Requires -Version 7.4

<#
.SYNOPSIS
Parse JSON with Comments (JSONC). Returns the parsed object.

.DESCRIPTION
The catalog and other author-facing config files use JSONC so humans can
annotate fields. ConvertFrom-Json does not tolerate comments, and
regex-based strippers fail on the common cases:

    "url": "https://example.com"       // this is a comment
    "path": "C:\\Users\\<user>\\file"  // regex can mis-detect unclosed strings
    /* block comment that straddles
       multiple lines */

Remove-JsoncComment walks the input one character at a time, tracking
whether we are inside a quoted string and whether the previous character was
a backslash (escape). Only then is it safe to look for // and /* tokens.

ConvertFrom-Jsonc composes Remove-JsoncComment with ConvertFrom-Json.
#>

function Remove-JsoncComment {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] [AllowEmptyString()] [string] $Text
    )
    process {
        if ([string]::IsNullOrEmpty($Text)) { return '' }

        $builder = [System.Text.StringBuilder]::new($Text.Length)
        $length = $Text.Length
        $i = 0
        $inString = $false
        $escaped = $false

        while ($i -lt $length) {
            $ch = $Text[$i]

            if ($escaped) {
                [void]$builder.Append($ch)
                $escaped = $false
                $i++
                continue
            }

            if ($inString) {
                if ($ch -eq '\') {
                    [void]$builder.Append($ch)
                    $escaped = $true
                    $i++
                    continue
                }
                if ($ch -eq '"') {
                    $inString = $false
                }
                [void]$builder.Append($ch)
                $i++
                continue
            }

            if ($ch -eq '"') {
                $inString = $true
                [void]$builder.Append($ch)
                $i++
                continue
            }

            if ($ch -eq '/' -and ($i + 1) -lt $length) {
                $next = $Text[$i + 1]
                if ($next -eq '/') {
                    # Line comment - skip to newline (keep the newline for line numbers).
                    $i += 2
                    while ($i -lt $length -and $Text[$i] -ne "`n") { $i++ }
                    continue
                }
                if ($next -eq '*') {
                    # Block comment - skip until closing */. Preserve newlines so
                    # downstream parse errors report correct line numbers.
                    $i += 2
                    while ($i -lt $length) {
                        if (($i + 1) -lt $length -and $Text[$i] -eq '*' -and $Text[$i + 1] -eq '/') {
                            $i += 2
                            break
                        }
                        if ($Text[$i] -eq "`n") { [void]$builder.Append("`n") }
                        $i++
                    }
                    continue
                }
            }

            [void]$builder.Append($ch)
            $i++
        }

        return $builder.ToString()
    }
}

function ConvertFrom-Jsonc {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] [AllowEmptyString()] [string] $InputText,
        [int] $Depth = 10
    )
    process {
        $stripped = Remove-JsoncComment -Text $InputText
        if ([string]::IsNullOrWhiteSpace($stripped)) { return $null }
        return $stripped | ConvertFrom-Json -Depth $Depth -ErrorAction Stop
    }
}
