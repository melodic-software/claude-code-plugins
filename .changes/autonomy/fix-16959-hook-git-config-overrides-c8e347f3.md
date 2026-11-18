---
bump: patch
---

### Security

- `hook-utils.sh`'s repository-root lookups and `lane-stop-gate.sh`'s branch read pass the overrides `hook::git_untrusted` uses, so those calls run with the repository's `core.fsmonitor`, git hooks and pager turned off, as the ignore check already does.
