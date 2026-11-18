---
bump: patch
---

### Security

- The format hook's adapter lookups (`.editorconfig` and `.shellcheckrc` discovery) run git through `rt_git`, which in a hook is `hook::git_untrusted`, so editing a shell file no longer starts a `core.fsmonitor` command or git hook named in that repository's config.
