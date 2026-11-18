---
bump: patch
---

### Security

- `worktree-remove-gate.sh`'s `git status` no longer starts the `core.fsmonitor` command a repository's own config names: it and the gate's other git calls, `worktree-add-containment-gate.sh`, `pr-linkage-mcp-gate.sh` and `hook-utils.sh`'s repository-root lookups pass the overrides `hook::git_untrusted` uses. Not yet covered: the git calls in `scripts/worktree-create.sh` and the helpers it uses, which `worktree-create-gate.sh` runs (issue #16959 tracks them), and other commands a repository's config can name, such as a `.gitattributes` content filter, which `git status` in `worktree-remove-gate.sh` can still start.
