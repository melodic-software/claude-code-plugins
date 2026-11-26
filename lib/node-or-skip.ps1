$node = Get-Command -Name node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $node) { exit 0 }
& $node.Source @args
exit $LASTEXITCODE
