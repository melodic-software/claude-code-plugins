---
bump: patch
---

### Fixed

- `reap-project-plugin-records.sh` and the worktree audit's Step 2b now cover local-scope plugin install records for dead worktrees as well as project-scope ones. The reap uninstalls each record with its own scope (`-s project` or `-s local`, always `--keep-data`, never `-s user`), and the audit rows show each path's scopes.
