# Run prerequisites.mjs from this directory with the same arguments and exit code.
# Without node on PATH, print one fixed line and exit 1, because the checker
# cannot run and node is itself a missing required dependency.
#
#   pwsh -NoProfile -File prerequisites.ps1 check <plugin-root> [--for <scope>]
$node = Get-Command -Name node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $node) {
    [Console]::Out.WriteLine('prerequisites: node was not found on PATH, so no prerequisite was checked. Install Node.js from https://nodejs.org/en/download, then run this check again.')
    exit 1
}
& $node.Source (Join-Path -Path $PSScriptRoot -ChildPath 'prerequisites.mjs') @args
exit $LASTEXITCODE
