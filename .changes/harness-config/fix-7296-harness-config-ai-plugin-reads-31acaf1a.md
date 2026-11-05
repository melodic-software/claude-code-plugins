---
bump: patch
---

### Fixed

- `audit-instructions` says where its `context/`, `reference/` and `scripts/` paths sit under the plugin root, and opens plugin files with the Read tool by those paths, never through `cat` or `sed` and never by searching the plugin directory.
- `audit-instructions` reads the prior report by its path with the Read tool and treats not found as the no-prior case; it runs no `ls`, `touch`, `mkdir` or Glob against the plugin data directory, since `run-state.sh lease acquire` creates the run directory.
- `audit-instructions` names `run-state.sh` and `emit-findings.sh` by their paths instead of a bare name or a placeholder a context file cannot resolve.
