---
bump: patch
---

### Fixed

- **`block-root-delete-target` judges a PowerShell target holding a literal `$`.** A single-quoted or backtick-escaped `$` is no longer read as an expansion, so `Remove-Item -Recurse -Force 'D:\outside\a$b'` is judged as the path it names and refused outside the allowed roots, where it was let through. A Win32 stream suffix on such a target (`'D:\outside\dir::$INDEX_ALLOCATION'`, `:$I30:$INDEX_ALLOCATION`) is judged as the directory before it, and `'C:\::$INDEX_ALLOCATION'` is refused as a drive root. A `$` PowerShell expands is still left alone, and a single-quoted `'$X'` alone is still refused as a bare variable. `cmd /c rd /s` and `powershell -Command Remove-Item` issued from the Bash tool are now listed as a declared gap: the Bash lane matches `rm` only ([#6626](https://github.com/melodic-software/claude-code-plugins/issues/6626)).
