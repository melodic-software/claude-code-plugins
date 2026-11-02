---
bump: minor
---

### Removed

- **The team layer is read only from `docs/conventions/code-metrics.yaml`** ([#12290](https://github.com/melodic-software/claude-code-plugins/issues/12290)). The older `.claude/code-metrics.yaml`, read in its place since 0.6.0 while the docs file was absent, is no longer read. While it exists, `/code-metrics:setup check` shows a WARN row naming it. `/code-metrics:setup apply` still carries its declared keys into the docs file when that file does not exist yet; then delete the old file.
