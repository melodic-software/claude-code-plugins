# Editing the shell wiring

The wiring command must run under the POSIX shell. `sh` is invoked explicitly for exactly that
reason (the script's stated shell requirement); on a Windows agent with no POSIX shell installed
the runner routes task commands through the PowerShell shim and this wiring does not apply. The
routing claim is verified 2026-09-20 against runner 2.4 and the shell-selection reference
(<https://example.invalid/widget-runner/docs/shells>, "Windows agents": the runner runs task
commands through the POSIX shell when one is installed, or through the PowerShell shim when none
is installed). Recheck when that section stops naming both shells, or when a release note names
shell routing on Windows. State this with the printed edit: the wiring is applied once and is
not reapplied on upgrade.

## Applying the edit

Print the diff first and apply it only after the agent owner confirms.
