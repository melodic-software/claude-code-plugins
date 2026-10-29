---
bump: minor
---

### Added

- `/guardrails:setup apply identity-domains` writes the `block-cross-domain` map, `identity-domains.json` in the plugin data directory, from the identity domains `/harness-ops:machine-profile` recorded ([#9749](https://github.com/melodic-software/claude-code-plugins/issues/9749)). Each domain's tree becomes its root, and a `gh` directory the profile records becomes its `gh_config_dir`. Owners, identity markers, `az_config_dir` and shared exceptions come from the operator or are left out. The map is written only after the operator confirms, and a different map already there is replaced only with `--replace`.
