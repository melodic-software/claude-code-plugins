---
bump: patch
---

### Changed

- The `update` action's safety table states the current rule: the marketplace's daily drift workflow runs `--check` and files an `Upstream drift: playwright/playwright` issue when upstream moves, the issue lane runs `--apply` and the reference integration, and the change merges through a reviewed pull request. It no longer says nothing runs on a schedule. The README says the check runs daily and that the issue lane works the issue.
- The update action's finishing steps and `update.sh --apply` mark the global `npm install -g @playwright/cli@latest` upgrade as a step a person runs; the upstream-drift issue lane never runs it.
- The update action's finishing steps and `update.sh --apply` name a changelog fragment as the release record, since the plugin is in fragment mode, in place of a `plugin.json` version bump.
