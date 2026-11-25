# GENERATED from lib/node-or-skip.ps1 by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
$node = Get-Command -Name node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $node) { exit 0 }
& $node.Source @args
exit $LASTEXITCODE
