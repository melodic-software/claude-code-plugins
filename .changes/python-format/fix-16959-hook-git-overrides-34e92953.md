---
bump: patch
---

### Security

- The format hook's adapter lookups (Ruff config discovery and the committed-`.venv` check) run git through `rt_git`, which in a hook is `hook::git_untrusted`, so editing a Python file no longer starts a `core.fsmonitor` command or git hook named in that repository's config.
