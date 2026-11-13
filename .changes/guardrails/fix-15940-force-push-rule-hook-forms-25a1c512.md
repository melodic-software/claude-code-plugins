---
bump: minor
---

### Added

- **block-dangerous-git can allow only a lease pinned to a full commit id ([#15940](https://github.com/melodic-software/claude-code-plugins/issues/15940)).** The new `block_dangerous_git_unpinned_lease` option (`allow` by default, `block`), or `unpinned_lease: block` in a repository's `docs/conventions/guardrails.yaml` at its local `origin/HEAD`, blocks a lease that pins no full commit id: `--force-with-lease` with `--force-if-includes`, or the empty expect `--force-with-lease=<ref>:`. Either layer set to `block` blocks it. The default is unchanged, since git documents both forms as safe. Every force-push block message now names only `--force-with-lease=<ref>:<full-sha>`, the form that passes under both values.
