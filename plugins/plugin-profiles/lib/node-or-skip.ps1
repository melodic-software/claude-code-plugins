# GENERATED from lib/node-or-skip.ps1 by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# Run node with these arguments and its exit code, or exit 0 silently when node
# is not on PATH: the PowerShell half of node-or-skip.sh (read its header for
# the contract). stdin passes through to node untouched.
$node = Get-Command -Name node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $node) { exit 0 }
& $node.Source @args
exit $LASTEXITCODE
