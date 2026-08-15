#Requires -Version 7.4
# Public entry surface for the machine-health audit test suite. The Pester
# runner under tests/ is skill-private; external consumers (docs, CI) invoke
# this wrapper instead of reaching into it. All arguments pass through.
& "$PSScriptRoot/../tests/Invoke-MachineHealthTests.ps1" @args
exit $LASTEXITCODE
