---
bump: patch
---

### Security

- The format hook's adapter and gate lookups (markdownlint config discovery, the committed-`node_modules` check and the code-config trust record) run git through `rt_git`, which in a hook is `hook::git_untrusted`, so editing a Markdown file no longer starts a `core.fsmonitor` command or git hook named in that repository's config.
