---
bump: patch
---

### Changed

- `/code-tidying:audit-dead-code`, `/code-tidying:batch-simplify` and the `/code-tidying:tidy`
  self-update lane and exclusions reference no longer restate upstream behavior (LSP reference
  counting, detector exit codes, gopls and staticcheck suppression, knip and vulture config
  details, how injected commands run, git's `--since` parsing, frontmatter loading, hook
  locations, `userConfig` types). Each keeps its own rule and links the upstream section with an
  as-of date and a recheck trigger. The self-update lane drops its note on how consumers update.
