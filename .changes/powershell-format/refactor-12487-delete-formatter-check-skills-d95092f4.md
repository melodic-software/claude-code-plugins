---
bump: major
---

### Removed

- The `check` skill is gone. To check this plugin's prerequisites, run `node "<plugin root>/lib/prerequisites.mjs" check "<plugin root>"`.
- The checker sees no PowerShell module, so `/powershell-format:setup check` is now the one report on PSScriptAnalyzer.
