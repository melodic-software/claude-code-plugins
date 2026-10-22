#Requires -Version 7.4

<#
.SYNOPSIS
Prepare the elevated pass: pre-create the result file, write the one-command
script, and return its SHA-256 and the launch argument string.

.DESCRIPTION
Runs in the standard session, before the owner is asked
(reference/windows/elevation-matrix.md, "How to run elevated"):

 1. Pre-creates the empty <StateBase>/logs/elevated-result-<runStamp>.json and
    records its file ID (volume serial plus file index).
 2. Writes <StateBase>/logs/elevated-run-<runStamp>.ps1, UTF-8 without a byte
    order mark, holding one command: the orchestrator in -ResultPath mode with
    that file and ID. Returns the script's SHA-256 (uppercase hex, the form
    Get-FileHash prints).
 3. Builds the one string for Start-Process -ArgumentList: pwsh -NoProfile
    -Command with a block that reads the script's bytes once, exits 3 without
    running anything when their SHA-256 is not the returned hash, and otherwise
    runs those same bytes as a script block. The hash stays readable on the
    command line the owner approves.

Both files are created new, never overwritten. A StateBase under a cloud sync
root is refused, as every other state write is.

Returns { ScriptPath, ScriptSha256, ResultPath, ResultFileId, ArgumentString }.
#>

. (Join-Path $PSScriptRoot 'Open-NoFollowFile.ps1')
. (Join-Path $PSScriptRoot 'Assert-StateBaseLocation.ps1')
. (Join-Path $PSScriptRoot 'Resolve-SkillRoot.ps1')

function ConvertTo-SingleQuotedLiteral {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)] [string] $Value)

    # PowerShell also ends a single-quoted string at the typographic single quotes, so each is doubled too.
    return "'" + ($Value -replace '[''\u2018\u2019\u201A\u201B]', '$0$0') + "'"
}

function New-ElevatedLaunch {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [string] $OutputBase,
        [Parameter(Mandatory = $true)] [string] $StateBase,
        [string] $SkillRoot = (Resolve-SkillRoot),
        [datetime] $Now = (Get-Date)
    )

    $OutputBase = [System.IO.Path]::GetFullPath($OutputBase)
    $StateBase = [System.IO.Path]::GetFullPath($StateBase)
    $orchestrator = Join-Path ([System.IO.Path]::GetFullPath($SkillRoot)) 'scripts\windows\Invoke-MachineHealthCheck.ps1'
    if (-not [System.IO.File]::Exists($orchestrator)) { throw "Orchestrator not found: '$orchestrator'." }
    $location = Assert-StateBaseLocation -Path $StateBase -WarningAction SilentlyContinue
    if ($location.Synced) {
        throw "Refused: the state folder '$StateBase' is under a cloud sync root ($($location.Rule): '$($location.Folder)')."
    }

    $logsDir = Join-Path $StateBase 'logs'
    $runStamp = $Now.ToUniversalTime().ToString('yyyy-MM-ddTHHmmssfffZ')
    $resultPath = Join-Path $logsDir "elevated-result-$runStamp.json"
    $scriptPath = Join-Path $logsDir "elevated-run-$runStamp.ps1"
    if (-not $PSCmdlet.ShouldProcess($logsDir, "Create $(Split-Path -Leaf $resultPath) and $(Split-Path -Leaf $scriptPath)")) {
        return
    }

    [void][System.IO.Directory]::CreateDirectory($logsDir)
    [System.IO.File]::Open($resultPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None).Dispose()
    $handle = Open-NoFollowFile -Path $resultPath
    try {
        $fileId = (Get-FileIdentity -Handle $handle).FileId
    } finally {
        $handle.Dispose()
    }

    $command = ('& {0} -OutputBase {1} -StateBase {2} -RunMode on-demand -SkipBanner -ResultPath {3} -ResultFileId {4}' -f
        (ConvertTo-SingleQuotedLiteral $orchestrator), (ConvertTo-SingleQuotedLiteral $OutputBase),
        (ConvertTo-SingleQuotedLiteral $StateBase), (ConvertTo-SingleQuotedLiteral $resultPath),
        (ConvertTo-SingleQuotedLiteral $fileId))
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($command)
    $stream = [System.IO.File]::Open($scriptPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None)
    try {
        $stream.Write($bytes, 0, $bytes.Length)
    } finally {
        $stream.Dispose()
    }
    $sha256 = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes))

    # A Windows path cannot hold a double quote, so the block needs no escaping inside its quotes.
    $block = ('$b = [IO.File]::ReadAllBytes({0}); ' +
        'if ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b)) -cne ''{1}'') {{ exit 3 }}; ' +
        '& ([scriptblock]::Create([Text.UTF8Encoding]::new($false).GetString($b))); exit $LASTEXITCODE') -f
    (ConvertTo-SingleQuotedLiteral $scriptPath), $sha256

    return [pscustomobject]@{
        ScriptPath     = $scriptPath
        ScriptSha256   = $sha256
        ResultPath     = $resultPath
        ResultFileId   = $fileId
        ArgumentString = "-NoProfile -Command ""$block"""
    }
}
