---
bump: minor
---

### Removed

- **The team layer is read only from `docs/conventions/mutation-testing.yaml`** ([#12289](https://github.com/melodic-software/claude-code-plugins/issues/12289)). The older .claude/mutation-testing.md, read in its place for one release while the YAML file was absent, is no longer read. While it exists, `/mutation-testing:setup check` reports it as INFO. `/mutation-testing:setup apply` still carries its keys into the YAML file when that file does not exist yet; then delete the old file.
