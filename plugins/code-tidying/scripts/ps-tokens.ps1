#Requires -Version 7.0
<#
.SYNOPSIS
    Read PowerShell files with the language's own parser, for change-shape.py and
    commented-out-code.py.
.DESCRIPTION
    Default: one record per input path: the parse-error count, every token as
    [Kind, Text], every comment as [startLine, endLine, startColumn, text], the
    text the parser decoded, and each comment's [startOffset, endOffset] into
    that text in UTF-16 code units. The Python side owns the
    Comment/NewLine/#Requires filtering so both backends share one filter.

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

$script:reserved = @(
    (Get-Variable -Scope Global).Name
    '_', 'PSItem', 'args', 'input', 'this', 'null', 'true', 'false', 'Matches', 'Error', 'Host'
) | Sort-Object -Unique

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

function Add-NestedTokens {
    param([System.Collections.Generic.List[string]]$Out, [int]$Index, $Token)
    foreach ($n in $Token.NestedTokens) {
        if ($null -eq $n) { continue }
        $Out.Add([string]$Index)
        if ($n -is [System.Management.Automation.Language.VariableToken]) {
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

foreach ($p in $Path) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        (Resolve-Path -LiteralPath $p).ProviderPath, [ref]$tokens, [ref]$errors) | Out-Null
    $tk = [string[]]::new($tokens.Count * 2)
    $cm = [System.Collections.Generic.List[object[]]]::new()
    $sp = [System.Collections.Generic.List[int[]]]::new()
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
            $sp.Add([int[]]@($t.Extent.StartOffset, $t.Extent.EndOffset))
        }
        elseif ($t -is [System.Management.Automation.Language.StringExpandableToken]) {
            Add-NestedTokens $nested (($i - 2) / 2) $t
        }
    }
    Write-Json @{
        errors   = @($errors).Count; tokens = $tk; comments = $cm; nested = $nested
        reserved = [string[]]$script:reserved; spans = $sp
        text     = $tokens[0].Extent.StartScriptPosition.GetFullScript()
    }
}
