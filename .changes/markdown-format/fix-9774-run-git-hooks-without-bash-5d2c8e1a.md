---
bump: patch
---

### Fixed

- **Git hook entry:** `markdown-check.sh` starts under `sh` and starts no `bash` by name, which on Windows can be System32's WSL launcher. The vendored check lib reruns it under the first bash on `PATH` outside System32; with none, bash is a missing tool under the check-placement contract (`checks.skipmissing`, else fail for an agent and a notice for a person). The vendored installer's plain dispatcher runs an entry that starts `#!/bin/sh` with `sh` (an older copy by its own first line until it is refreshed), its lefthook and husky run lines read `sh <path>`, and it replaces a dispatcher an earlier release wrote instead of refusing it as modified. Rerun `/markdown-format:setup apply install-git-hooks` to pick it up ([#9774](https://github.com/melodic-software/claude-code-plugins/issues/9774)).
