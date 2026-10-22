#Requires -Version 7.4

<#
.SYNOPSIS
Prepare, look up and start the elevated pass.

.DESCRIPTION
New-ElevatedLaunch pre-creates <StateBase>/logs/elevated-result-<runStamp>.json,
records its file ID from the creating handle, writes
<StateBase>/logs/elevated-run-<runStamp>.ps1 (one orchestrator command, UTF-8
without a byte order mark) and returns the launch record:
{ ScriptPath, ScriptSha256, ResultPath, ResultFileId, ArgumentString }.

Get-ElevatedLaunch rebuilds that record from <StateBase> and the shown hash,
so a later step needs no path but the state root. Start-ElevatedLaunch checks
the record's ArgumentString against a rebuild and starts pwsh elevated with
it, returning the exit code.

Mechanism and refusals: reference/windows/elevation-matrix.md, "How to run
elevated"; the ask and launch rules: SKILL.md, "Elevated pass".
#>

. (Join-Path $PSScriptRoot 'Open-NoFollowFile.ps1')
. (Join-Path $PSScriptRoot 'Assert-StateBaseLocation.ps1')
. (Join-Path $PSScriptRoot 'Resolve-SkillRoot.ps1')

# Control characters and the five characters PowerShell reads as a single quote.
$script:LaunchForbiddenCharacters = '[\p{Cc}''\u2018\u2019\u201A\u201B]'

function ConvertTo-SingleQuotedLiteral {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)] [string] $Value)

    if ($Value -match $script:LaunchForbiddenCharacters) {
        throw "Refused '$($Value -replace '\p{Cc}', '?')': the elevated pass takes no path holding a control character or a single quote."
    }
    return "'$Value'"
}

function Get-ElevatedLaunchArgument {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)] [string] $ScriptPath,
        [Parameter(Mandatory = $true)] [ValidatePattern('^[0-9A-F]{64}\z')] [string] $ScriptSha256
    )

    # Reads the bytes once, exits 3 on a hash mismatch, else runs those same bytes.
    $block = ('$b = [IO.File]::ReadAllBytes({0}); ' +
        'if ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b)) -cne ''{1}'') {{ exit 3 }}; ' +
        '& ([scriptblock]::Create([Text.UTF8Encoding]::new($false).GetString($b))); exit $LASTEXITCODE') -f
    (ConvertTo-SingleQuotedLiteral $ScriptPath), $ScriptSha256
    return "-NoProfile -Command ""$block"""
}

function New-ElevatedLaunch {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [string] $OutputBase,
        [Parameter(Mandatory = $true)] [string] $StateBase,
        [string] $SkillRoot = (Resolve-SkillRoot)
    )

    $OutputBase = [System.IO.Path]::GetFullPath($OutputBase)
    $StateBase = [System.IO.Path]::GetFullPath($StateBase)
    $orchestrator = Join-Path ([System.IO.Path]::GetFullPath($SkillRoot)) 'scripts\windows\Invoke-MachineHealthCheck.ps1'
    $quoted = @{
        Orchestrator = ConvertTo-SingleQuotedLiteral $orchestrator
        OutputBase   = ConvertTo-SingleQuotedLiteral $OutputBase
        StateBase    = ConvertTo-SingleQuotedLiteral $StateBase
    }
    if (-not [System.IO.File]::Exists($orchestrator)) { throw "Orchestrator not found: '$orchestrator'." }
    $location = Assert-StateBaseLocation -Path $StateBase -WarningAction SilentlyContinue
    if ($location.Synced) {
        throw "Refused: the state folder '$StateBase' is under a cloud sync root ($($location.Rule): '$($location.Folder)')."
    }

    $logsDir = Join-Path $StateBase 'logs'
    $runStamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHHmmssfffZ')
    $resultPath = Join-Path $logsDir "elevated-result-$runStamp.json"
    $scriptPath = Join-Path $logsDir "elevated-run-$runStamp.ps1"
    if (-not $PSCmdlet.ShouldProcess($logsDir, "Create $(Split-Path -Leaf $resultPath) and $(Split-Path -Leaf $scriptPath)")) {
        return
    }

    [void][System.IO.Directory]::CreateDirectory($logsDir)
    $created = [System.IO.File]::Open($resultPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None)
    try {
        $fileId = (Get-FileIdentity -Handle $created.SafeFileHandle).FileId
    } finally {
        $created.Dispose()
    }

    $command = ('& {0} -OutputBase {1} -StateBase {2} -RunMode on-demand -SkipBanner -ResultPath {3} -ResultFileId {4}' -f
        $quoted.Orchestrator, $quoted.OutputBase, $quoted.StateBase, (ConvertTo-SingleQuotedLiteral $resultPath),
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

    return [pscustomobject]@{
        ScriptPath     = $scriptPath
        ScriptSha256   = $sha256
        ResultPath     = $resultPath
        ResultFileId   = $fileId
        ArgumentString = Get-ElevatedLaunchArgument -ScriptPath $scriptPath -ScriptSha256 $sha256
    }
}

function Get-ElevatedLaunch {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [string] $StateBase,
        [Parameter(Mandatory = $true)] [ValidatePattern('^[0-9A-F]{64}\z')] [string] $ScriptSha256
    )

    $logsDir = Join-Path ([System.IO.Path]::GetFullPath($StateBase)) 'logs'
    $nameRule = '^elevated-run-(\d{4}-\d{2}-\d{2}T\d{9}Z)\.ps1$'
    foreach ($file in @(Get-ChildItem -LiteralPath $logsDir -File -Filter 'elevated-run-*.ps1' -ErrorAction SilentlyContinue)) {
        $match = [regex]::Match($file.Name, $nameRule)
        if (-not $match.Success) { continue }
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        if ([System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)) -cne $ScriptSha256) { continue }

        # The bytes hash to the shown value, so this is the command the owner read.
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            [System.Text.UTF8Encoding]::new($false).GetString($bytes), [ref]$null, [ref]$null)
        $elements = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))[0].CommandElements
        $fileId = $null
        for ($i = 0; $i -lt $elements.Count - 1; $i++) {
            if ($elements[$i] -is [System.Management.Automation.Language.CommandParameterAst] -and
                $elements[$i].ParameterName -eq 'ResultFileId') { $fileId = $elements[$i + 1].Value }
        }
        return [pscustomobject]@{
            ScriptPath     = $file.FullName
            ScriptSha256   = $ScriptSha256
            ResultPath     = Join-Path $logsDir "elevated-result-$($match.Groups[1].Value).json"
            ResultFileId   = $fileId
            ArgumentString = Get-ElevatedLaunchArgument -ScriptPath $file.FullName -ScriptSha256 $ScriptSha256
        }
    }
    throw "No elevated-run script under '$logsDir' has SHA-256 $ScriptSha256."
}

function Start-ElevatedLaunch {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)] [pscustomobject] $Launch,
        # Test seam: receives the argument string in place of the elevated Start-Process.
        [scriptblock] $Launcher = {
            param($ArgumentString)
            (Start-Process -FilePath 'pwsh' -Verb RunAs -Wait -PassThru -ArgumentList $ArgumentString).ExitCode
        }
    )

    $expected = Get-ElevatedLaunchArgument -ScriptPath $Launch.ScriptPath -ScriptSha256 $Launch.ScriptSha256
    if ($Launch.ArgumentString -cne $expected) {
        throw 'Refused: the launch record''s ArgumentString is not the one built from its script path and hash.'
    }
    if (-not $PSCmdlet.ShouldProcess($Launch.ScriptPath, 'Start pwsh elevated')) { return }
    return [int](& $Launcher $expected)
}
