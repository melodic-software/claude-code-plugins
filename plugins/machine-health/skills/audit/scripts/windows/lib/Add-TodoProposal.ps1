#Requires -Version 7.4

<#
.SYNOPSIS
State-rooted TODO.md helpers: resolve its path, append a proposal, and render
the report's "Open questions" section from the proposals a run queued.

.DESCRIPTION
TODO.md is machine state, so it lives under the state root and never in the
plugin install directory (the shipped skills/audit/TODO.md is policy
documentation). A proposal is one `### <Title>` section; a section whose title
is already in the file is not appended twice.
#>

function Get-TodoPath {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $StateBase)

    return Join-Path $StateBase 'TODO.md'
}

# Returns $true when the proposal was appended, $false when it was already queued.
function Add-TodoProposal {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $TodoPath,
        [Parameter(Mandatory)] [string] $Title,
        [Parameter(Mandatory)] [string] $Body
    )

    $heading = "### $Title"
    if ((Test-Path -LiteralPath $TodoPath) -and
        (Get-Content -LiteralPath $TodoPath -ErrorAction Stop) -contains $heading) {
        return $false
    }
    Add-Content -LiteralPath $TodoPath -Value "`n$heading`n`n$Body`n" -Encoding utf8 -ErrorAction Stop
    return $true
}

function Get-OpenQuestionsMarkdown {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyCollection()] [string[]] $QueuedTitle = @(),
        [Parameter(Mandatory)] [string] $TodoPath
    )

    if ($QueuedTitle.Count -eq 0) { return '_No new TODO entries this run._' }
    return (($QueuedTitle | ForEach-Object { "- $_ (queued in ``$TodoPath``)" }) -join "`n")
}
