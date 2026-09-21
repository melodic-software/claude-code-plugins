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

# Structure English prose cannot produce. A CommandAst is NOT on the list: prose
# about PowerShell parses as one, whether it names a -Switch (`the one
# -AllowExitCode judges`) or a cmdlet (`Set-Acl asks the provider to...`), so
# admitting it turns every comment in a PowerShell-documenting file into a
# finding. The cost is that a commented-out bare command line is missed.
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

# One JSON object per line, one line per input path.
foreach ($p in $Path) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        (Resolve-Path -LiteralPath $p).ProviderPath, [ref]$tokens, [ref]$errors) | Out-Null
    # Kind and Text flattened into one array rather than a list of pairs: on a
    # 97k-token file the per-token array allocation costs 2.1 s and this costs
    # 0.7 s. The Python side re-pairs them.
    $tk = [string[]]::new($tokens.Count * 2)
    $cm = [System.Collections.Generic.List[object[]]]::new()
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
    }
    Write-Json @{ errors = @($errors).Count; tokens = $tk; comments = $cm }
}
