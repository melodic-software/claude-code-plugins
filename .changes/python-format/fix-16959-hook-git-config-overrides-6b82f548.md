---
bump: patch
---

### Security

- `hook-utils.sh`'s repository-root lookups (`hook::in_git_working_tree`, `hook::repo_root_to`) pass the overrides `hook::git_untrusted` uses, so those git calls run with the repository's `core.fsmonitor`, git hooks and pager turned off, as its ignore check already does.
