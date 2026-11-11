---
bump: patch
---

### Fixed

- The `setup` skill's git-hook decisions reference no longer restates when husky sets `core.hooksPath`; the `husky-install` row keeps its action: tell the user to run the project's install.
- The `setup` skill's git-hook decisions reference keeps its lefthook `use_stdin`, `parallel` and remote `source_dir` actions but drops the restated lefthook behavior and error string, pointing at lefthook's `use_stdin`, `parallel` and `remotes` docs instead.
- `setup check` no longer downgrades a tool a git-hook entry needs (`jq` for `reference-verify`) to INFO while every guard is off and that entry is installed: the entries run at commit or push outside Claude Code and read no toggle.
