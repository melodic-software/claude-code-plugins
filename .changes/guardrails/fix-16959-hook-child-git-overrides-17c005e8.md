---
bump: patch
---

### Security

- `hpp::resolve_scan_root`, which `hardcoded-path-check` and `block-github-post-content` run against the project directory, passes the overrides `hook::git_untrusted` uses to its `git rev-parse`, so the repository's `core.fsmonitor`, git hooks and pager stay off there too.
