#Requires -Version 7.4
# Public entry for the audit test suite: the Pester runner under tests/ is
# skill-private, so docs and CI call this wrapper instead.
& "$PSScriptRoot/../tests/Invoke-MachineHealthTests.ps1" @args
exit $LASTEXITCODE
