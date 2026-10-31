---
bump: minor
---

### Added

- `block-root-delete-target` judges a PowerShell delete run through another command as the delete itself, so its target must sit strictly inside the git toplevel, the session scratchpad or an allowed root, and one aimed at a root, at HOME or outside them is refused. That covers the string `Invoke-Expression` or `iex` runs, the `-Command` text of `pwsh` or `powershell`, an `-EncodedCommand` decoded from base64 of UTF-16LE, the program and argument list of `Start-Process`, a pipeline removal (`gci X | Remove-Item`, `gci X | % { $_.Delete() }`) judged by the `Get-ChildItem` or `Get-Item` path that feeds it, and a .NET delete (`[IO.Directory]::Delete`, `[IO.File]::Delete`, `(Get-Item X).Delete()`) judged by its path argument. A removal fed by anything but such a listing is refused, and an `-EncodedCommand` that is not literal base64 of printable ASCII text is denied whether or not the session is attended. A mechanism named inside quoted prose, such as a `git commit -m` message, stays allowed.

### Changed

- `block-root-delete-target` no longer refuses every PowerShell pipeline into `Remove-Item -Recurse` with no path: when a `Get-ChildItem` or `Get-Item` feeds it, that listing's path is judged instead, so `gci build | Remove-Item -Recurse` from a repository passes.
