---
bump: patch
---

### Added

- `behavior-probes`: two auto-mode cases check that a custom `soft_deny` list without `"$defaults"` keeps a non-git default rule (a file-sourced `gh secret set` is denied; `gh secret list` runs). Record 6 now covers them and its rerun on Claude Code 2.1.322, where the denial label reads `[Destructive or Unwanted Actions]`.
