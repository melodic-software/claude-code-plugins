#Requires -Version 7.0
<#
.SYNOPSIS
    Read PowerShell files with the language's own parser, for change-shape.py and
    commented-out-code.py.
.DESCRIPTION
    Default: one record per input path: the parse-error count, every token as
    [Kind, Text], and every comment as [startLine, endLine, startColumn, text].
    The Python side owns the Comment/NewLine/#Requires filtering so both backends
    share one filter.

    -Bodies <path>: that file holds a JSON array of comment bodies; emits one
    boolean per body, true when the body parses cleanly and carries structure that
    prose cannot produce.
#>
[CmdletBinding(DefaultParameterSetName = 'Tokens')]
param(
    [Parameter(ParameterSetName = 'Bodies', Mandatory)][string]$Bodies,
    [Parameter(ParameterSetName = 'Tokens', Mandatory, ValueFromRemainingArguments)][string[]]$Path
)

# Redirected stdout defaults to the OEM codepage on Windows, where two different
# non-ASCII characters both become '?' and compare equal, a false-COMMENT-ONLY
# path in a proof tool.
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Asked of a fresh runspace, not hand-maintained, so the list cannot go stale. The
# supplement adds names that exist only inside a pipeline, function body, or match.
$script:reserved = @(
    (Get-Variable -Scope Global).Name
    '_', 'PSItem', 'args', 'input', 'this', 'null', 'true', 'false', 'Matches', 'Error', 'Host'
) | Sort-Object -Unique

# A CommandAst is NOT on the list: prose about PowerShell parses as one, so admitting
# it flags every comment in a PowerShell-documenting file. A bare command line is missed.
$script:evidence = @(
    'AssignmentStatementAst', 'IfStatementAst', 'ForEachStatementAst', 'ForStatementAst',
    'WhileStatementAst', 'FunctionDefinitionAst', 'TryStatementAst', 'HashtableAst',
    'MemberExpressionAst', 'InvokeMemberExpressionAst', 'ParamBlockAst'
)

function Test-CodeLike {
    param([string]$Body)
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Body, [ref]$null, [ref]$errors)
    if (@($errors).Count -gt 0) { return $false }
    $hits = $ast.FindAll({
            param($n)
            if ($n -is [System.Management.Automation.Language.PipelineAst]) {
                return $n.PipelineElements.Count -ge 2
            }
            return $script:evidence -contains $n.GetType().Name
        }, $true)
    return @($hits).Count -gt 0
}

# ConvertTo-Json costs seconds on a 100k-token file where the parse costs
# milliseconds; System.Text.Json reads the runtime type behind each `object`.
function Write-Json {
    param([hashtable]$Fields)
    $d = [System.Collections.Generic.Dictionary[string, object]]::new()
    foreach ($k in $Fields.Keys) { $d[$k] = $Fields[$k] }
    Write-Output ([System.Text.Json.JsonSerializer]::Serialize(
            $d, $d.GetType(), [System.Text.Json.JsonSerializerOptions]$null))
}

if ($PSCmdlet.ParameterSetName -eq 'Bodies') {
    $list = Get-Content -LiteralPath $Bodies -Raw -Encoding utf8 | ConvertFrom-Json
    $results = foreach ($body in @($list)) { [bool](Test-CodeLike $body) }
    Write-Json @{ results = [bool[]]@($results) }
    exit 0
}

# `"text $x here"` is ONE token, so a rename missing the interpolated `$x` would read
# clean. Nested tokens go to a recursive side list keyed on the string's index, and the
# string token itself stays, so editing the string is still a change. A side list
# because a `List.Add` per token in the main loop costs 3.9 s on 97k tokens against 1.0 s.
function Add-NestedTokens {
    param([System.Collections.Generic.List[string]]$Out, [int]$Index, $Token)
    foreach ($n in $Token.NestedTokens) {
        if ($null -eq $n) { continue }
        $Out.Add([string]$Index)
        if ($n -is [System.Management.Automation.Language.VariableToken]) {
            # `${x}` and `$x` are one variable. Normalizing to the bare spelling
            # is what lets the stale-name and collision guards see a reference
            # the rename missed, whichever spelling it wore.
            $Out.Add('InterpolatedVariable')
            $Out.Add('$' + $n.VariablePath.UserPath)
        }
        else {
            $Out.Add($n.Kind.ToString())
            $Out.Add($n.Text)
        }
        if ($n -is [System.Management.Automation.Language.StringExpandableToken]) {
            Add-NestedTokens $Out $Index $n
        }
    }
}

# One JSON object per line, one line per input path.
foreach ($p in $Path) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        (Resolve-Path -LiteralPath $p).ProviderPath, [ref]$tokens, [ref]$errors) | Out-Null
    # Kind and Text flattened into one list rather than a list of pairs: on a
    # 97k-token file the per-token array allocation costs 2.1 s and this costs
    # 0.7 s. The Python side re-pairs them.
    $tk = [string[]]::new($tokens.Count * 2)
    $cm = [System.Collections.Generic.List[object[]]]::new()
    $nested = [System.Collections.Generic.List[string]]::new()
    $i = 0
    foreach ($t in $tokens) {
        $kind = $t.Kind.ToString()
        $tk[$i++] = $kind
        $tk[$i++] = $t.Text
        if ($kind -eq 'Comment') {
            $cm.Add([object[]]@(
                    $t.Extent.StartLineNumber, $t.Extent.EndLineNumber,
                    $t.Extent.StartColumnNumber, $t.Text))
        }
        elseif ($t -is [System.Management.Automation.Language.StringExpandableToken]) {
            Add-NestedTokens $nested (($i - 2) / 2) $t
        }
    }
    Write-Json @{
        errors   = @($errors).Count; tokens = $tk; comments = $cm; nested = $nested
        reserved = [string[]]$script:reserved
    }
}
