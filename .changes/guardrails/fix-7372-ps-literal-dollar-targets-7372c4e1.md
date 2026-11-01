---
bump: patch
---

### Fixed

- `block-root-delete-target` no longer refuses a PowerShell delete target whose every `$` is literal (single-quoted or backtick-escaped), such as `Remove-Item -Recurse '$env:TEMP'`, `'$HOME\x'`, `'$(x)'` or `cmd /c rd /s /q '$env:TEMP'`: such a target names a path of that name and is judged as that path. The same target inside an expanding outer string (`pwsh -c "..."`, `iex "..."`, `Start-Process pwsh -ArgumentList "..."`) is still judged as an expansion, because the outer string expands it first ([#7372](https://github.com/melodic-software/claude-code-plugins/issues/7372)).
