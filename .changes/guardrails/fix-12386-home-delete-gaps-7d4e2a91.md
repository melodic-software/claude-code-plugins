---
bump: patch
---

### Fixed

- `block-root-delete-target` refuses five home deletes it allowed: `$SHELL -c "rm -rf ~"` and `"$SHELL" -c ...` (a `$SHELL` or `$BASH` command word is read as `sh`), `cmd /k del /s /q %USERPROFILE%` (a `del` or `erase` with `/s`, run together too as in `/qs`, in a `cmd /c` line is judged like `rd /s`, and a `%NAME%` cmd expands is judged as `$NAME`), `bash -c "rm -rf ~"` and `wsl rm -rf ~` from the PowerShell tool (judged as the Bash tool judges them; a bash, sh, dash or mksh child's `*` skips dot names, so `bash -c 'rm -rf *'` at the toplevel stays allowed), and `cmd /c "powershell -c Remove-Item -Recurse ~"` from the PowerShell tool (a `pwsh` or `powershell` in a `cmd /c` line is walked as PowerShell). In-tree and read-only equivalents stay allowed.
