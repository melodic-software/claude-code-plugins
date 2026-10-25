---
bump: patch
---

### Fixed

- **Git hooks:** no git hook file the plugin installs starts a `bash` by name, which on Windows can be System32's WSL launcher. `commit-msg-convention` and the convention resolver it runs are POSIX sh, run with `sh`, so they need no bash beside git's sh. `pre-commit-content` and `reference-verify` start under `sh`, and the vendored check lib reruns them under the first bash on `PATH` outside System32; with none, bash is a missing tool under the check-placement contract (`checks.skipmissing`, else fail for an agent and a notice for a person). `reference-verify` starts `run-guards.sh` through the check lib's `checks_bash_run`, never a bash found by name, and the lefthook remote runs its scripts with `sh`. The vendored installer's plain dispatcher runs an entry that starts `#!/bin/sh` with `sh` (an older copy by its own first line until it is refreshed), its lefthook and husky run lines read `sh <path>`, and it replaces a dispatcher an earlier release wrote instead of refusing it as modified. Rerun `/guardrails:setup apply install-git-hooks` to pick it up ([#9774](https://github.com/melodic-software/claude-code-plugins/issues/9774)).
